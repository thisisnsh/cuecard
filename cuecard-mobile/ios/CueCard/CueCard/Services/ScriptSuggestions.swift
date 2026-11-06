import Foundation
import FoundationModels

/// A small change Apple's on-device model proposes for the script, for the
/// user to accept or reject: a spelling fix, a cue or an anchor put in, or
/// words set in bold or italic.
struct ScriptSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case spelling, cue, anchor, bold, italic
    }

    let id = UUID()
    let kind: Kind
    /// Where it applies in the script, kept current as other suggestions are
    /// accepted ahead of it.
    var range: NSRange
    /// The words there now.
    let original: String
    /// What they become once it's accepted.
    let replacement: String
}

/// What the reader made of a review, for the rating sent after it.
struct SuggestionsMetrics: Equatable {
    /// Reviewing a deck in the cards editor, not a teleprompter script.
    var isDeck = false
    var found = 0
    var accepted = 0
    var rejected = 0
}

/// CueCard's own switch for Apple Intelligence, in Settings. On unless the
/// user turns it off; off, Suggestions and Ask AI are gone everywhere.
enum AppleIntelligenceSetting {
    static let enabledKey = "cuecard_apple_intelligence_enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// How much Apple Intelligence has been used in CueCard on this iPhone, shown
/// in Settings and sent with a report about it.
enum AIUsage {
    private static let reviewsKey = "cuecard_ai_suggestion_reviews"
    private static let foundKey = "cuecard_ai_suggestions_found"
    private static let acceptedKey = "cuecard_ai_suggestions_accepted"
    private static let questionsKey = "cuecard_ai_help_questions"

    /// Suggestion reviews seen through to the end.
    static var reviews: Int { UserDefaults.standard.integer(forKey: reviewsKey) }
    static var suggestionsFound: Int { UserDefaults.standard.integer(forKey: foundKey) }
    static var suggestionsAccepted: Int { UserDefaults.standard.integer(forKey: acceptedKey) }
    /// Questions asked in Help.
    static var questions: Int { UserDefaults.standard.integer(forKey: questionsKey) }

    static func recordReview(_ metrics: SuggestionsMetrics) {
        add(1, to: reviewsKey)
        add(metrics.found, to: foundKey)
        add(metrics.accepted, to: acceptedKey)
    }

    static func recordQuestion() {
        add(1, to: questionsKey)
    }

    private static func add(_ amount: Int, to key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + amount, forKey: key)
    }
}

/// Whether this iPhone has Apple's on-device model to ask — for suggestions
/// and for answers in Help — and if not, whether the user could do
/// something about that. Turned off in Settings, it's as if there were none.
enum OnDeviceModelAvailability: Equatable {
    case available
    /// Apple Intelligence is off, or still getting ready: what uses it shows,
    /// and says why it can't help yet.
    case unavailable(String)
    /// No on-device model on this iPhone or this version of iOS.
    case unsupported

    static var current: OnDeviceModelAvailability {
        AppleIntelligenceSetting.isEnabled ? onDevice : .unsupported
    }

    /// What this iPhone can do, whatever the switch in Settings says.
    static var onDevice: OnDeviceModelAvailability {
        guard #available(iOS 26.0, *) else { return .unsupported }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(String(localized: "Turn on Apple Intelligence in Settings to use this."))
        case .unavailable(.modelNotReady):
            return .unavailable(String(localized: "Apple Intelligence is still getting ready on this iPhone. Try again in a little while."))
        case .unavailable:
            return .unsupported
        }
    }
}

/// The suggestions for the script being reviewed, as the model finds them.
///
/// Everything runs on the iPhone; the script never leaves it. While a review
/// is open, the only edits made to the script are the suggestions accepted
/// here. Anything else changing it — another note opened — ends the review.
@MainActor
final class ScriptReview: ObservableObject {
    /// A review is open: the editor shows the suggestions and the panel.
    @Published private(set) var isActive = false
    /// The model is still reading the script.
    @Published private(set) var isRunning = false
    /// What's left to decide on, in the order it appears in the script.
    @Published private(set) var suggestions: [ScriptSuggestion] = []
    @Published var focusedID: ScriptSuggestion.ID?
    /// Why the review stopped short, to show the user.
    @Published var errorMessage: String?

    /// A review the user saw through, waiting to be rated.
    @Published var finished: SuggestionsMetrics?

    private var metrics = SuggestionsMetrics()
    /// Anything has been suggested in this review, so running out of
    /// suggestions means they've all been decided rather than none found.
    var hasSuggested: Bool { metrics.found > 0 }

    /// The script as it stands with every accepted suggestion in.
    private var script = ""
    /// Every accepted change since the model was handed the script, so what
    /// it finds can be moved to where those words are now.
    private var edits: [(location: Int, delta: Int)] = []
    private var task: Task<Void, Never>?

    var focused: ScriptSuggestion? {
        suggestions.first { $0.id == focusedID }
    }

    var focusedIndex: Int? {
        suggestions.firstIndex { $0.id == focusedID }
    }

    /// Review `script`. A deck of cards comes with the characters a card
    /// holds, so nothing suggested runs a card past it.
    func start(script: String, cardLimit: Int? = nil) {
        guard #available(iOS 26.0, *) else { return }
        end()
        metrics.isDeck = cardLimit != nil
        self.script = script
        isActive = true
        isRunning = true

        task = Task { [weak self] in
            do {
                for try await found in ScriptSuggester.suggestions(for: script, cardLimit: cardLimit) {
                    self?.add(found)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = ScriptSuggester.message(for: error)
                self?.end()
                return
            }
            self?.finishRunning()
        }
    }

    /// Close the review, dropping whatever hasn't been decided.
    func end() {
        task?.cancel()
        task = nil
        isActive = false
        isRunning = false
        suggestions = []
        focusedID = nil
        metrics = SuggestionsMetrics()
        edits = []
    }

    /// Close a review the user saw through. If it suggested anything, there's
    /// something for them to rate.
    func finish() {
        let result = metrics
        end()
        AIUsage.recordReview(result)
        if result.found > 0 { finished = result }
    }

    /// The script changed. Unless it's to what accepting gave it, the
    /// suggestions no longer line up with it.
    func scriptDidChange(to newScript: String) {
        guard isActive, newScript != script else { return }
        end()
    }

    /// Take the suggestion in. Returns the edit for the editor to make, with
    /// the next suggestion in focus.
    func accept(_ id: ScriptSuggestion.ID) -> (range: NSRange, replacement: String)? {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return nil }
        let suggestion = suggestions.remove(at: index)
        metrics.accepted += 1
        let delta = (suggestion.replacement as NSString).length - suggestion.range.length
        script = (script as NSString).replacingCharacters(in: suggestion.range, with: suggestion.replacement)
        edits.append((suggestion.range.location, delta))
        for i in suggestions.indices where suggestions[i].range.location >= NSMaxRange(suggestion.range) {
            suggestions[i].range.location += delta
        }
        AnalyticsEvents.logButtonClick("suggestion_accept", screen: "home", parameters: ["kind": suggestion.kind.analyticsName])
        focusAfterRemoving(at: index)
        return (suggestion.range, suggestion.replacement)
    }

    /// Every suggestion left, back to front so each edit leaves the ranges of
    /// the ones still to make where they are.
    func acceptAll() -> [(range: NSRange, replacement: String)] {
        AnalyticsEvents.logButtonClick("suggestion_accept_all", screen: "home", parameters: ["count": suggestions.count])
        metrics.accepted += suggestions.count
        let all = suggestions.sorted { $0.range.location > $1.range.location }
        for suggestion in all {
            script = (script as NSString).replacingCharacters(in: suggestion.range, with: suggestion.replacement)
            edits.append((suggestion.range.location,
                          (suggestion.replacement as NSString).length - suggestion.range.length))
        }
        suggestions = []
        focusedID = nil
        finishIfDone()
        return all.map { ($0.range, $0.replacement) }
    }

    func reject(_ id: ScriptSuggestion.ID) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        let suggestion = suggestions.remove(at: index)
        metrics.rejected += 1
        AnalyticsEvents.logButtonClick("suggestion_reject", screen: "home", parameters: ["kind": suggestion.kind.analyticsName])
        focusAfterRemoving(at: index)
    }

    func focusNext() {
        guard let index = focusedIndex, !suggestions.isEmpty else { return }
        focusedID = suggestions[(index + 1) % suggestions.count].id
    }

    func focusPrevious() {
        guard let index = focusedIndex, !suggestions.isEmpty else { return }
        focusedID = suggestions[(index - 1 + suggestions.count) % suggestions.count].id
    }

    /// The suggestion tapped on in the editor, if one was.
    func focus(at location: Int) {
        if let tapped = suggestions.first(where: {
            $0.range.location <= location && location <= NSMaxRange($0.range)
        }) {
            focusedID = tapped.id
        }
    }

    private func focusAfterRemoving(at index: Int) {
        if suggestions.isEmpty {
            focusedID = nil
            finishIfDone()
        } else {
            focusedID = suggestions[min(index, suggestions.count - 1)].id
        }
    }

    /// Found against the script as it was handed over: moved past whatever
    /// has been accepted since, and kept only if its words are still there.
    private func add(_ found: [ScriptSuggestion]) {
        let text = script as NSString
        for var suggestion in found {
            for edit in edits where edit.location < suggestion.range.location {
                suggestion.range.location += edit.delta
            }
            guard NSMaxRange(suggestion.range) <= text.length,
                  text.substring(with: suggestion.range) == suggestion.original,
                  !suggestions.contains(where: { NSIntersectionRange($0.range, suggestion.range).length > 0 })
            else { continue }
            suggestions.append(suggestion)
            metrics.found += 1
        }
        suggestions.sort { $0.range.location < $1.range.location }
        if focusedID == nil { focusedID = suggestions.first?.id }
    }

    private func finishRunning() {
        isRunning = false
        task = nil
        AnalyticsEvents.logButtonClick("suggestions_finished", screen: "home",
                                       parameters: ["found": hasSuggested ? 1 : 0])
        finishIfDone()
    }

    /// Everything suggested has been decided on, so the review closes. With
    /// nothing found at all, it stays open to say so.
    private func finishIfDone() {
        guard !isRunning, suggestions.isEmpty, hasSuggested else { return }
        finish()
    }
}

extension ScriptSuggestion.Kind {
    var analyticsName: String {
        switch self {
        case .spelling: "spelling"
        case .cue: "cue"
        case .anchor: "anchor"
        case .bold: "bold"
        case .italic: "italic"
        }
    }
}

// MARK: - The model

/// Reads the script with the on-device model a passage at a time, and checks
/// what it suggests against the script before passing it on: the model
/// is small and gets things wrong, and a suggestion that doesn't fit the
/// script's own rules is dropped rather than shown.
@available(iOS 26.0, *)
enum ScriptSuggester {
    /// About how much script goes to the model at once. Its context holds a
    /// few thousand tokens, instructions and answer included.
    private static let passageLength = 1500

    /// Suggestions for each passage, as the model finishes it. For a deck,
    /// `cardLimit` is the characters a card holds.
    static func suggestions(for script: String, cardLimit: Int? = nil) -> AsyncThrowingStream<[ScriptSuggestion], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let protected = protectedRanges(in: script)
                let emphases = RichText.emphases(in: script, skipping: TeleprompterParser.cueMatches(in: script).map(\.range))
                var cards = cardLimit.map { CardBudget(script: script, limit: $0) }
                do {
                    for passage in passages(in: script) {
                        try Task.checkCancellation()
                        do {
                            let review = try await review(of: (script as NSString).substring(with: passage),
                                                          isDeck: cardLimit != nil)
                            let found = validated(review.changes, in: passage, of: script,
                                                  protected: protected, emphases: emphases, cards: &cards)
                            if !found.isEmpty { continuation.yield(found) }
                        } catch let error as LanguageModelSession.GenerationError {
                            switch error {
                            case .unsupportedLanguageOrLocale, .assetsUnavailable:
                                throw error
                            default:
                                // A passage the model couldn't make sense of, or wouldn't
                                // read, is passed over; the rest are still worth reading.
                                continue
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError, case .unsupportedLanguageOrLocale = error {
            return String(localized: "Suggestions aren't available for this script's language yet.")
        }
        return String(localized: "Suggestions couldn't be made right now. Try again in a little while.")
    }

    private static let instructions = """
        You review a script someone will read aloud from a teleprompter, and suggest a few small \
        changes to it. Most passages need few changes or none. When a passage is fine, suggest nothing.


        """ + markup + spellingAndCues + """

        - anchor: the first words of a new major section in a long script. value is empty.
        """ + emphasisAndRules

    /// For a deck of cards: no anchors, which are for jumping through the
    /// teleprompter, and only the cues a card has room for.
    private static let deckInstructions = """
        You review a deck of cue cards someone will read aloud, one short card at a time, and suggest \
        a few small changes to it. Most passages need few changes or none. When a passage is fine, \
        suggest nothing. A line with [separator] ends one card and starts the next.


        """ + markup + spellingAndCues + emphasisAndRules + """

        - Never suggest an anchor. Cards are short: suggest a cue only where a card has room for it.
        """

    private static let markup = """
        The script has its own markup:
        - Words in square brackets, like [pause] or [smile], are a delivery cue for the speaker. \
        They aren't read aloud.
        - [anchor] marks the start of a section the speaker can jump to.
        - *words* are bold and _words_ are italic.

        The kinds of change:
        """

    private static let spellingAndCues = """

        - spelling: a misspelled word or a clear grammar slip. text is the wrong words; value is \
        the same words corrected. Never reword or rewrite a sentence.
        - cue: a delivery cue at a natural moment, such as pause, breathe, smile, slow down or look up. \
        text is the words the cue comes right after; value is the cue's words, one to four, without brackets. \
        At most one or two in a passage.
        """

    private static let emphasisAndRules = """

        - bold: a word or short phrase to stress strongly. value is empty. Rare.
        - italic: a word or short phrase to say with lighter emphasis. value is empty. Rare.

        Rules:
        - text is copied exactly from the passage: a few words, all on one line.
        - Never change anything inside square brackets, and never add a cue or anchor where there is one already.
        - Keep to the script's language.
        """

    private static func review(of passage: String, isDeck: Bool) async throws -> ModelReview {
        let session = LanguageModelSession(model: SystemLanguageModel.default,
                                           instructions: isDeck ? deckInstructions : instructions)
        let response = try await session.respond(
            to: "Passage:\n\(passage)",
            generating: ModelReview.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content
    }

    // MARK: Passages

    /// The script split into passages at line ends, a long line at its sentences.
    /// A passage with no words in it, only tags, isn't sent.
    static func passages(in script: String) -> [NSRange] {
        let text = script as NSString
        var units: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, line, enclosing, _ in
            if line.length <= passageLength {
                units.append(enclosing)
                return
            }
            var last = line.location
            text.enumerateSubstrings(in: line, options: [.bySentences, .substringNotRequired]) { _, _, sentence, _ in
                units.append(NSRange(location: last, length: NSMaxRange(sentence) - last))
                last = NSMaxRange(sentence)
            }
            if NSMaxRange(enclosing) > last {
                units.append(NSRange(location: last, length: NSMaxRange(enclosing) - last))
            }
        }

        var passages: [NSRange] = []
        var current: NSRange?
        for unit in units {
            if let open = current, open.length + unit.length <= passageLength {
                current = NSUnionRange(open, unit)
            } else {
                if let open = current { passages.append(open) }
                current = unit
            }
        }
        if let current { passages.append(current) }

        return passages.filter { passage in
            // The tags come grouped by what they are, not in script order, and
            // can overlap, so what's left is worked out instead of cut out.
            let plain = text.substring(with: passage) as NSString
            var words = IndexSet(integersIn: 0..<plain.length)
            for tag in protectedRanges(in: plain as String) {
                guard let tag = Range(tag) else { continue }
                words.remove(integersIn: tag)
            }
            return words.rangeView.contains { run in
                plain.substring(with: NSRange(run)).rangeOfCharacter(from: .letters) != nil
            }
        }
    }

    // MARK: Checking what the model says

    /// Tags the model mustn't change, or put anything inside.
    private static func protectedRanges(in script: String) -> [NSRange] {
        TeleprompterParser.cueMatches(in: script).map(\.range)
            + TeleprompterParser.anchorRanges(in: script)
            + TeleprompterParser.imageMatches(in: script).map(\.range)
            + CueCards.separatorRanges(in: script)
    }

    /// The most of each kind kept from one passage, so a review never buries
    /// the script in suggestions.
    private static let limits: [ScriptSuggestion.Kind: Int] = [
        .spelling: 6, .cue: 2, .anchor: 1, .bold: 1, .italic: 1
    ]

    private static func validated(_ changes: [ModelChange], in passage: NSRange, of script: String,
                                  protected: [NSRange], emphases: [Emphasis],
                                  cards: inout CardBudget?) -> [ScriptSuggestion] {
        let text = script as NSString
        var kept: [ScriptSuggestion] = []
        var counts: [ScriptSuggestion.Kind: Int] = [:]

        for change in changes {
            let kind = change.kind.kind
            // Cards are turned, not jumped through.
            if cards != nil, kind == .anchor { continue }
            guard counts[kind, default: 0] < limits[kind, default: 0],
                  var range = locate(change.text, in: passage, of: text) else { continue }
            if kind == .bold || kind == .italic { range = text.trimmingPunctuation(in: range) }
            guard range.length > 0,
                  !protected.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  !kept.contains(where: { NSIntersectionRange($0.range, range).length > 0 }),
                  let suggestion = suggestion(kind, at: range, value: change.value, in: text,
                                              protected: protected, emphases: emphases),
                  cards?.takes(suggestion) ?? true
            else { continue }
            kept.append(suggestion)
            counts[kind, default: 0] += 1
        }
        return kept
    }

    /// Where the words the model copied are in the passage: whole words, on one line.
    private static func locate(_ words: String, in passage: NSRange, of text: NSString) -> NSRange? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words.rangeOfCharacter(from: .newlines) == nil else { return nil }
        var search = passage
        while search.length > 0 {
            let found = text.range(of: words, options: [], range: search)
            guard found.location != NSNotFound else { return nil }
            if text.isWordBoundary(at: found.location), text.isWordBoundary(at: NSMaxRange(found)) {
                return found
            }
            search = NSRange(location: found.location + 1, length: NSMaxRange(passage) - found.location - 1)
        }
        return nil
    }

    private static func suggestion(_ kind: ScriptSuggestion.Kind, at range: NSRange, value: String, in text: NSString,
                                   protected: [NSRange], emphases: [Emphasis]) -> ScriptSuggestion? {
        let original = text.substring(with: range)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let markup = CharacterSet(charactersIn: "[]*_")
        let replacement: String

        switch kind {
        case .spelling:
            // A fix, not a rewrite: a few words, changed by a few letters.
            guard !value.isEmpty, value != original,
                  value.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  original.rangeOfCharacter(from: markup) == nil,
                  original.split(separator: " ").count <= 6,
                  original.editDistance(to: value) <= max(2, original.count / 3)
            else { return nil }
            replacement = value

        case .cue:
            let cue = value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            let end = NSMaxRange(range)
            guard !cue.isEmpty, cue.count <= 30, cue.split(separator: " ").count <= 4,
                  cue.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  !hasTag(near: end, in: text, protected: protected)
            else { return nil }
            replacement = original + text.spacedInsertion(of: TeleprompterParser.cueTag(text: cue), at: end).text

        case .anchor:
            // At the start of a line, past the first, with none there already.
            let line = text.lineRange(for: NSRange(location: range.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
            guard line.location > 0, before.trimmingCharacters(in: .whitespaces).isEmpty,
                  !hasTag(near: range.location, in: text, protected: protected)
            else { return nil }
            replacement = text.spacedInsertion(of: TeleprompterParser.anchorTag, at: range.location).text + original

        case .bold, .italic:
            guard original.count <= 40, original.split(separator: " ").count <= 5,
                  original.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  !emphases.contains(where: { NSIntersectionRange($0.range, range).length > 0 })
            else { return nil }
            let marker = (kind == .bold ? EmphasisStyle.bold : .italic).marker
            replacement = marker + original + marker
        }

        return ScriptSuggestion(kind: kind, range: range, original: original, replacement: replacement)
    }

    /// A tag right at `location`, give or take a space, so another isn't put beside it.
    private static func hasTag(near location: Int, in text: NSString, protected: [NSRange]) -> Bool {
        protected.contains { $0.location <= location + 2 && location - 2 <= NSMaxRange($0) }
    }
}

// MARK: - Cards

/// How much more each card of a deck can hold, so the suggestions for it,
/// taken together, never run it past its limit.
private struct CardBudget {
    private let cards: [NSRange]
    private var room: [Int]

    init(script: String, limit: Int) {
        let text = script as NSString
        cards = CueCards.cardRanges(in: script)
        room = cards.map { limit - CueCards.measure(card: text.substring(with: $0), limit: limit).length }
    }

    /// Whether the card the suggestion is on has room for what it adds, and
    /// if so, count it as taken. A suggestion that adds nothing always fits.
    mutating func takes(_ suggestion: ScriptSuggestion) -> Bool {
        guard let index = cards.firstIndex(where: {
            $0.location <= suggestion.range.location && NSMaxRange(suggestion.range) <= NSMaxRange($0)
        }) else { return false }
        let limit = Int.max / 2
        let added = CueCards.measure(card: suggestion.replacement, limit: limit).length
            - CueCards.measure(card: suggestion.original, limit: limit).length
        guard added > 0 else { return true }
        guard added <= room[index] else { return false }
        room[index] -= added
        return true
    }
}

// MARK: - What the model writes

@available(iOS 26.0, *)
@Generable
private struct ModelReview {
    @Guide(description: "The changes worth making, in the order they appear. Empty when the passage is fine.",
           .maximumCount(8))
    var changes: [ModelChange]
}

@available(iOS 26.0, *)
@Generable
private struct ModelChange {
    @Guide(description: "The kind of change.")
    var kind: ModelKind
    @Guide(description: "A few words copied exactly from the passage, all on one line.")
    var text: String
    @Guide(description: "For spelling, the corrected words. For cue, the cue's words without brackets. Otherwise empty.")
    var value: String
}

@available(iOS 26.0, *)
@Generable
private enum ModelKind {
    case spelling, cue, anchor, bold, italic

    var kind: ScriptSuggestion.Kind {
        switch self {
        case .spelling: .spelling
        case .cue: .cue
        case .anchor: .anchor
        case .bold: .bold
        case .italic: .italic
        }
    }
}

// MARK: - Helpers

private extension NSString {
    /// Nothing that's part of a word on either side of `location`.
    func isWordBoundary(at location: Int) -> Bool {
        guard location > 0, location < length else { return true }
        let before = Unicode.Scalar(character(at: location - 1))
        let after = Unicode.Scalar(character(at: location))
        let word = CharacterSet.alphanumerics
        return !(before.map(word.contains) ?? false) || !(after.map(word.contains) ?? false)
    }

    /// `range` without the spaces and punctuation at either end.
    func trimmingPunctuation(in range: NSRange) -> NSRange {
        let edge = CharacterSet.whitespaces.union(.punctuationCharacters)
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, let scalar = Unicode.Scalar(character(at: start)), edge.contains(scalar) { start += 1 }
        while end > start, let scalar = Unicode.Scalar(character(at: end - 1)), edge.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}

private extension String {
    /// Letters added, taken out or changed to turn this into `other`.
    func editDistance(to other: String) -> Int {
        let a = Array(self), b = Array(other)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + Swift.min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }
}
