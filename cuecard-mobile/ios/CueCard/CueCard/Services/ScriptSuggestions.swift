import Foundation
import FoundationModels

/// A small change Apple's on-device model proposes for the script, for the
/// user to accept or reject: a spelling fix, words missing from a sentence
/// put back, a phrase rewritten to say better, a cue or an anchor put in, a
/// long line broken in two, or words set in bold or italic.
struct ScriptSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case spelling, missingWords, rewrite, cue, anchor, lineBreak, bold, italic
    }

    let id = UUID()
    let kind: Kind
    /// Where it applies in the script, kept current as other suggestions are
    /// accepted ahead of it. A cue, or words only put in, is empty, at the
    /// spot it goes: a fix to the words before it is a suggestion of its own.
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

/// CueCard's own switches for its Apple Intelligence features, in Settings,
/// one for each. Each is on unless the user turns it off; off, the feature
/// is gone everywhere.
enum AppleIntelligenceSetting {
    /// Suggestions AI in the editor.
    static let suggestionsKey = "cuecard_ai_suggestions_enabled"
    /// Help AI, answering questions in Help.
    static let askAIKey = "cuecard_ai_ask_enabled"
    /// Follow Me AI's button in the teleprompter.
    static let followVoiceKey = "cuecard_follow_voice_enabled"

    /// The feature under `key` is on.
    static func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
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
/// something about that. For a feature turned off in Settings, it's as if
/// there were none.
enum OnDeviceModelAvailability: Equatable {
    case available
    /// Apple Intelligence is off, or still getting ready: what uses it shows,
    /// and says why it can't help yet.
    case unavailable(String)
    /// No on-device model on this iPhone or this version of iOS.
    case unsupported

    /// For Suggestions AI, which can be turned off on its own.
    static var forSuggestions: OnDeviceModelAvailability {
        AppleIntelligenceSetting.isEnabled(AppleIntelligenceSetting.suggestionsKey) ? onDevice : .unsupported
    }

    /// For Help AI, which can be turned off on its own.
    static var forAskAI: OnDeviceModelAvailability {
        AppleIntelligenceSetting.isEnabled(AppleIntelligenceSetting.askAIKey) ? onDevice : .unsupported
    }

    /// What this iPhone can do, whatever the switches in Settings say.
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
    /// A review is open: the editor shows the suggestions, and the bar
    /// below it how many are left.
    @Published private(set) var isActive = false
    /// The model is still reading the script.
    @Published private(set) var isRunning = false
    /// What's left to decide on, in the order it appears in the script.
    @Published private(set) var suggestions: [ScriptSuggestion] = []
    /// The one tapped on in the editor, with Accept and Reject above it.
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

    /// Take the suggestion in. Returns the edit to make to the script.
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
        didRemove(suggestion)
        return (suggestion.range, suggestion.replacement)
    }

    func reject(_ id: ScriptSuggestion.ID) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        let suggestion = suggestions.remove(at: index)
        metrics.rejected += 1
        AnalyticsEvents.logButtonClick("suggestion_reject", screen: "home", parameters: ["kind": suggestion.kind.analyticsName])
        didRemove(suggestion)
    }

    /// Decided on: nothing's tapped on now, and with none left, the review
    /// is done.
    private func didRemove(_ suggestion: ScriptSuggestion) {
        if focusedID == suggestion.id { focusedID = nil }
        finishIfDone()
    }

    /// Found against the script as it was handed over: moved past whatever
    /// has been accepted since, and kept only if its words are still there.
    private func add(_ found: [ScriptSuggestion]) {
        let text = script as NSString
        for var suggestion in found {
            // Words put in where it starts, like a cue, go ahead of it.
            for edit in edits where edit.location <= suggestion.range.location {
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
        case .missingWords: "missing_words"
        case .rewrite: "rewrite"
        case .cue: "cue"
        case .anchor: "anchor"
        case .lineBreak: "line_break"
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
///
/// Each passage is read up to five times, for one kind of thing each time:
/// lines with words missing, typing mistakes, rewrites, delivery, then
/// paragraphs.
/// The model does far better asked for one thing than for all of them at
/// once.
@available(iOS 26.0, *)
enum ScriptSuggester {
    /// About how much script goes to the model at once. Its context holds a
    /// few thousand tokens, instructions and answer included.
    private static let passageLength = 1500

    /// A line at least this long is worth breaking into paragraphs.
    private static let longLine = 160

    /// The least room between two cues, so the ones suggested don't bunch up.
    private static let cueSpacing = 80

    /// Suggestions for each passage, as the model finishes it. For a deck,
    /// `cardLimit` is the characters a card holds.
    static func suggestions(for script: String, cardLimit: Int? = nil) -> AsyncThrowingStream<[ScriptSuggestion], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let isDeck = cardLimit != nil
                let cues = TeleprompterParser.cueMatches(in: script).map(\.range)
                let context = Context(
                    text: script as NSString,
                    protected: protectedRanges(in: script),
                    cues: cues,
                    emphases: RichText.emphases(in: script, skipping: cues),
                    paragraphBreak: isDeck || !script.contains("\n\n") ? "\n" : "\n\n"
                )
                var cards = cardLimit.map { CardBudget(script: script, limit: $0) }
                var taken: [NSRange] = []
                do {
                    for passage in passages(in: script) {
                        let text = context.text.substring(with: passage)
                        for pass in Pass.allCases where pass.applies(to: text) {
                            try Task.checkCancellation()
                            do {
                                let proposals = try await pass.run(on: text, isDeck: isDeck)
                                let found = validated(proposals, in: passage, context: context,
                                                      taken: &taken, cards: &cards)
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

    // MARK: Asking

    /// What the model is asked to look for in a passage, one reading each.
    private enum Pass: CaseIterable {
        /// Lines that start or stop partway through a sentence, which a
        /// small model reads straight past unless they're pointed out.
        case completion
        /// Typing mistakes.
        case proofread
        /// Phrases and sentences that would say better another way.
        case rewrite
        /// Cues, anchors, and words to stress.
        case delivery
        /// Where a long line breaks into paragraphs.
        case paragraphs

        /// Only a passage with a line that looks cut short has anything to
        /// complete, and only one with a long line anything to break.
        func applies(to passage: String) -> Bool {
            switch self {
            case .completion:
                return !incompleteLines(in: passage).isEmpty
            case .paragraphs:
                var hasLongLine = false
                passage.enumerateLines { line, stop in
                    if (line as NSString).length >= longLine { hasLongLine = true; stop = true }
                }
                return hasLongLine
            case .proofread, .rewrite, .delivery:
                return true
            }
        }

        func run(on passage: String, isDeck: Bool) async throws -> [Proposal] {
            let prompt = "Passage:\n\(passage)"
            let options = GenerationOptions(samplingMode: .greedy)
            switch self {
            case .completion:
                // One line at a time, told which end is broken, and only
                // asked for the line repaired: the line itself is already
                // known, so nothing hangs on the model copying it exactly.
                var proposals: [Proposal] = []
                for broken in incompleteLines(in: passage) {
                    let session = LanguageModelSession(model: SystemLanguageModel.default,
                                                       instructions: completionInstructions(isDeck: isDeck))
                    let problem = [
                        broken.startsPartway ? "It starts partway through a sentence: words are missing before it." : nil,
                        broken.stopsPartway ? "It stops before its sentence ends: words are missing after it." : nil
                    ].compactMap { $0 }.joined(separator: " ")
                    do {
                        let repaired = try await session.respond(
                            to: "\(prompt)\n\nLine to repair:\n\(broken.line)\n\n\(problem)",
                            generating: ModelRepair.self, options: options
                        ).content.line
                        proposals.append(Proposal(kind: .missingWords, text: broken.line, value: repaired))
                    } catch let error as LanguageModelSession.GenerationError {
                        // A line the model wouldn't repair leaves the others still to try.
                        switch error {
                        case .unsupportedLanguageOrLocale, .assetsUnavailable: throw error
                        default: continue
                        }
                    }
                }
                return proposals
            case .proofread:
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                                                   instructions: proofreadInstructions(isDeck: isDeck))
                return try await session.respond(to: prompt, generating: ModelProofread.self, options: options)
                    .content.changes.map { Proposal(kind: .spelling, text: $0.text, value: $0.correction) }
            case .rewrite:
                // Free to be inventive here, unlike the readings that check.
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                                                   instructions: rewriteInstructions(isDeck: isDeck))
                return try await session.respond(to: prompt, generating: ModelRewrites.self,
                                                 options: GenerationOptions(temperature: 0.8))
                    .content.changes.map { Proposal(kind: .rewrite, text: $0.text, value: $0.rewrite) }
            case .delivery:
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                                                   instructions: deliveryInstructions(isDeck: isDeck))
                return try await session.respond(to: prompt, generating: ModelDelivery.self, options: options)
                    .content.marks.map { Proposal(kind: $0.kind.kind, text: $0.text, value: $0.cue) }
            case .paragraphs:
                let session = LanguageModelSession(model: SystemLanguageModel.default,
                                                   instructions: paragraphInstructions)
                return try await session.respond(to: prompt, generating: ModelParagraphs.self, options: options)
                    .content.starts.map { Proposal(kind: .lineBreak, text: $0, value: "") }
            }
        }
    }

    /// One thing the model suggested, before it's checked against the script.
    private struct Proposal {
        let kind: ScriptSuggestion.Kind
        /// The words it applies to, as the model copied them.
        let text: String
        /// The corrected words for spelling, the whole line for missing
        /// words, the new words for a rewrite, the cue's words for a cue.
        let value: String
    }

    private static func about(isDeck: Bool) -> String {
        isDeck
            ? "a deck of cue cards someone will read aloud, one short card at a time. "
                + "A line with [separator] ends one card and starts the next"
            : "a script someone will read aloud from a teleprompter"
    }

    private static let markup = """
        The script has its own markup:
        - Words in square brackets, like [pause] or [smile], are a delivery cue for the speaker. \
        They aren't read aloud.
        - [anchor] marks the start of a section the speaker can jump to.
        - *words* are bold and _words_ are italic.
        """

    /// A line that starts or stops partway through a sentence, pointed out
    /// to the model with the passage around it.
    private static func completionInstructions(isDeck: Bool) -> String {
        """
        You repair a line from \(about(isDeck: isDeck)). Words were deleted from it by accident, so it \
        starts partway through a sentence, like "r script at your pace", or stops before its sentence \
        ends, like "it keeps going in a floating".

        \(markup)

        Write the whole line again as a complete sentence that fits the passage around it, putting back \
        the words that are missing. A word cut short at the start or the end is finished, so "r script" \
        becomes something like "It scrolls your script". Keep the rest of the line as it is.

        Rules:
        - Always put words back: the line is broken.
        - Never change anything inside square brackets.
        - Keep to the script's language.
        """
    }

    private static func rewriteInstructions(isDeck: Bool) -> String {
        """
        You're a speechwriter improving \(about(isDeck: isDeck)). Rewrite any phrase or sentence that \
        would sound better said aloud: clearer, shorter, livelier, more natural, more persuasive, or \
        easier to say in one breath. Be bold, and suggest whatever would make it land better with the \
        audience, while keeping what the speaker means.

        \(markup)

        text is the words to replace, copied exactly from the passage: at most one sentence, all on one \
        line. rewrite is what replaces them.

        Rules:
        - Never change or add anything inside square brackets.
        - Keep to the script's language.
        """
    }

    private static func proofreadInstructions(isDeck: Bool) -> String {
        """
        You proofread \(about(isDeck: isDeck)) for typing mistakes, and nothing else.

        \(markup)

        A typing mistake is:
        - a misspelled word, like "teh" for "the" or "recieve" for "receive"
        - a word cut short or run together, like "scrip" for "script"
        - a wrong word that looks or sounds alike, like "there" for "their" or "your" for "you're"

        text is the words with the mistake; correction is the same words with only the mistake fixed. \
        Never reword a sentence or change how it's written.

        Rules:
        - text is copied exactly from the passage: a few words, all on one line.
        - Never change anything inside square brackets.
        - Keep to the script's language.
        """
    }

    /// A deck has no anchors, which are for jumping through the
    /// teleprompter, and only the cues a card has room for.
    private static func deliveryInstructions(isDeck: Bool) -> String {
        let anchor = isDeck
            ? "Never suggest an anchor. Cards are short: suggest a cue only where a card has room for it."
            : """
            - anchor: a sentence that starts a new topic or section, for the speaker to jump to. text is \
            its first few words.
            """
        return """
        You mark up \(about(isDeck: isDeck)), to make it easier to deliver. You never change its words.

        \(markup)

        The kinds of mark:
        - cue: a delivery cue where a speaker would naturally pause, breathe, smile, slow down or look up, \
        such as after a key point, before a big reveal or between two ideas. text is the last few words \
        before the cue; cue is what the speaker should do. One or two in a passage.
        \(anchor)
        - bold: a word or short phrase to stress strongly. text is those words. Rare.
        - italic: a word or short phrase to say with lighter emphasis. text is those words. Rare.

        Rules:
        - text is copied exactly from the passage: a few words, all on one line.
        - Never add a mark where there is one already.
        """
    }

    private static let paragraphInstructions = """
        You split a script someone will read aloud into short paragraphs of one to three sentences, \
        each one thought, so the speaker can take it in at a glance. You never change its words.
        """

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

    /// The script being reviewed, and what in it bears on a suggestion.
    private struct Context {
        let text: NSString
        /// Tags the model mustn't change, or put anything inside.
        let protected: [NSRange]
        /// The cues already in the script.
        let cues: [NSRange]
        let emphases: [Emphasis]
        /// What starts a new paragraph: a blank line where the script already
        /// has them between its paragraphs, otherwise a line break.
        let paragraphBreak: String
    }

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
        .spelling: 6, .missingWords: 3, .rewrite: 4, .cue: 3, .anchor: 1, .lineBreak: 4, .bold: 1, .italic: 1
    ]

    /// What the model proposed that fits the script. `taken` is where
    /// suggestions already are, from this passage's other readings and the
    /// passages before, so no two overlap.
    private static func validated(_ proposals: [Proposal], in passage: NSRange, context: Context,
                                  taken: inout [NSRange], cards: inout CardBudget?) -> [ScriptSuggestion] {
        var kept: [ScriptSuggestion] = []
        var counts: [ScriptSuggestion.Kind: Int] = [:]

        for proposal in proposals {
            let kind = proposal.kind
            // Cards are turned, not jumped through.
            if cards != nil, kind == .anchor { continue }
            guard counts[kind, default: 0] < limits[kind, default: 0],
                  var range = locate(proposal.text, in: passage, of: context.text) else { continue }
            if kind == .bold || kind == .italic { range = context.text.trimmingPunctuation(in: range) }
            // Words put back are checked against the tags where they go:
            // the line they're on can have a cue in it.
            guard range.length > 0,
                  kind == .missingWords || kind == .rewrite
                      || !context.protected.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  let suggestion = suggestion(kind, at: range, value: proposal.value, context: context),
                  !taken.contains(where: { NSIntersectionRange($0, suggestion.range).length > 0 }),
                  kind != .cue || hasRoomForCue(at: NSMaxRange(suggestion.range), context: context, kept: kept),
                  cards?.takes(suggestion) ?? true
            else { continue }
            kept.append(suggestion)
            taken.append(suggestion.range)
            counts[kind, default: 0] += 1
        }
        return kept
    }

    /// No cue already in the script, or kept from this passage, close by.
    private static func hasRoomForCue(at location: Int, context: Context, kept: [ScriptSuggestion]) -> Bool {
        let nearby = context.cues.map(\.location) + kept.filter { $0.kind == .cue }.map { NSMaxRange($0.range) }
        return !nearby.contains { abs($0 - location) < cueSpacing }
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

    private static func suggestion(_ kind: ScriptSuggestion.Kind, at range: NSRange, value: String,
                                   context: Context) -> ScriptSuggestion? {
        let text = context.text
        let original = text.substring(with: range)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let markup = CharacterSet(charactersIn: "[]*_")

        switch kind {
        case .spelling:
            // The model sometimes sets its fix in bold; the fix is the words.
            let fixed = value.filter { $0 != "*" && $0 != "_" }
            // A fix, not a rewrite: a few words, changed by a few letters.
            guard !fixed.isEmpty, fixed != original,
                  fixed.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  original.rangeOfCharacter(from: markup) == nil,
                  original.split(separator: " ").count <= 10,
                  original.editDistance(to: fixed) <= max(2, original.count / 3)
            else { return nil }
            return ScriptSuggestion(kind: kind, range: range, original: original, replacement: fixed)

        case .missingWords, .rewrite:
            // Only the words that differ, so the rest of the line stays as
            // it is. The model sometimes sets what it writes in quotes or
            // bold; what it means is the words. A pause it writes as a cue
            // is taken as a dash, which becomes the cue below.
            let fixed = value.filter { $0 != "*" && $0 != "_" }
                .replacingOccurrences(of: "[pause]", with: " — ", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»").union(.whitespaces))
            guard var change = wordChange(from: original, at: range, to: fixed),
                  change.replacement.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  text.substring(with: change.range).rangeOfCharacter(from: markup) == nil,
                  !context.protected.contains(where: {
                      NSIntersectionRange($0, change.range).length > 0
                          || ($0.location < change.range.location && change.range.location < NSMaxRange($0))
                  })
            else { return nil }
            change.replacement = pausingAtDashes(change.replacement)
            return ScriptSuggestion(kind: kind, range: change.range, original: text.substring(with: change.range),
                                    replacement: change.replacement)

        case .cue:
            // Offered a few, the first is the one.
            let first = value.split(whereSeparator: { ",;/".contains($0) }).first.map(String.init) ?? ""
            let cue = first.trimmingCharacters(in: CharacterSet(charactersIn: "[]. ").union(.whitespaces))
            let end = NSMaxRange(range)
            guard !cue.isEmpty, cue.count <= 30, cue.split(separator: " ").count <= 4,
                  cue.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  !hasTag(near: end, in: text, protected: context.protected)
            else { return nil }
            let tag = text.spacedInsertion(of: TeleprompterParser.cueTag(text: cue), at: end).text
            return ScriptSuggestion(kind: kind, range: NSRange(location: end, length: 0), original: "",
                                    replacement: tag)

        case .anchor:
            let line = text.lineRange(for: NSRange(location: range.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
            if before.trimmingCharacters(in: .whitespaces).isEmpty {
                // At the start of a line, past the first, with none there already.
                guard line.location > 0, !hasTag(near: range.location, in: text, protected: context.protected)
                else { return nil }
                let tag = text.spacedInsertion(of: TeleprompterParser.anchorTag, at: range.location).text
                return ScriptSuggestion(kind: kind, range: range, original: original, replacement: tag + original)
            }
            // A sentence partway along a line: the new section starts a paragraph of its own.
            guard let span = breakable(range, context: context) else { return nil }
            return ScriptSuggestion(kind: kind, range: span, original: text.substring(with: span),
                                    replacement: context.paragraphBreak + TeleprompterParser.anchorTag + " " + original)

        case .lineBreak:
            let line = text.substring(with: text.lineRange(for: NSRange(location: range.location, length: 0)))
            guard (line.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).length >= longLine,
                  let span = breakable(range, context: context)
            else { return nil }
            return ScriptSuggestion(kind: kind, range: span, original: text.substring(with: span),
                                    replacement: context.paragraphBreak + original)

        case .bold, .italic:
            guard original.count <= 40, original.split(separator: " ").count <= 5,
                  original.rangeOfCharacter(from: markup.union(.newlines)) == nil,
                  !context.emphases.contains(where: { NSIntersectionRange($0.range, range).length > 0 })
            else { return nil }
            let marker = (kind == .bold ? EmphasisStyle.bold : .italic).marker
            return ScriptSuggestion(kind: kind, range: range, original: original, replacement: marker + original + marker)
        }
    }

    /// `words` with the space before them, where they start a sentence
    /// partway along a line, for a new paragraph to take the space's place.
    /// The sentence before can end in a cue, which stays with it.
    private static func breakable(_ words: NSRange, context: Context) -> NSRange? {
        let text = context.text
        func isSpace(_ location: Int) -> Bool {
            let character = text.character(at: location)
            return character == 0x20 || character == 0x09
        }

        var start = words.location
        while start > 0, isSpace(start - 1) { start -= 1 }
        guard start < words.location else { return nil }

        var end = start
        while let cue = context.cues.first(where: { NSMaxRange($0) == end }) {
            end = cue.location
            while end > 0, isSpace(end - 1) { end -= 1 }
        }
        let closers = CharacterSet(charactersIn: "\"')»”’")
        while end > 0, let scalar = Unicode.Scalar(text.character(at: end - 1)), closers.contains(scalar) { end -= 1 }
        guard end > 0, let last = Unicode.Scalar(text.character(at: end - 1)),
              CharacterSet(charactersIn: ".!?…。！？").contains(last)
        else { return nil }
        return NSRange(location: start, length: NSMaxRange(words) - start)
    }

    /// A dash the model wrote between words, as a [pause] cue: in a script
    /// read aloud, that's what a dash is for. A dash inside a word, like a
    /// range of years, stays.
    private static func pausingAtDashes(_ text: String) -> String {
        let pause = " \(TeleprompterParser.cueTag(text: "pause")) "
        var result = text.replacingOccurrences(of: #"\s*—\s*|\s+[–-]\s+"#, with: pause, options: .regularExpression)
        guard result != text else { return text }
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        // Spaces at either end only where there were some to begin with:
        // words put in bring their own.
        if !text.hasPrefix(" ") { result = String(result.drop { $0 == " " }) }
        if !text.hasSuffix(" ") { while result.hasSuffix(" ") { result.removeLast() } }
        return result
    }

    /// Lines that look cut short: a paragraph of its own that starts with a
    /// small letter, or stops without anything to end a sentence. Tags
    /// don't count as words, and a line of only tags ends a paragraph.
    static func incompleteLines(in passage: String) -> [(line: String, startsPartway: Bool, stopsPartway: Bool)] {
        var lines: [String] = []
        passage.enumerateLines { line, _ in lines.append(line) }
        let words = lines.map { line -> String in
            let text = NSMutableString(string: line)
            for tag in protectedRanges(in: line).sorted(by: { $0.location > $1.location })
            where NSMaxRange(tag) <= text.length {
                text.replaceCharacters(in: tag, with: " ")
            }
            return (text as String).trimmingCharacters(in: .whitespaces)
        }
        let enders = CharacterSet(charactersIn: ".!?…:;\"”’')»。！？")

        var suspects: [(line: String, startsPartway: Bool, stopsPartway: Bool)] = []
        for (index, line) in words.enumerated() {
            guard let first = line.unicodeScalars.first, let last = line.unicodeScalars.last else { continue }
            let startsParagraph = index == 0 || words[index - 1].isEmpty
            let endsParagraph = index == words.count - 1 || words[index + 1].isEmpty
            let startsPartway = startsParagraph && CharacterSet.lowercaseLetters.contains(first)
            let stopsPartway = endsParagraph && !enders.contains(last) && line.split(separator: " ").count >= 3
            if startsPartway || stopsPartway {
                suspects.append((lines[index].trimmingCharacters(in: .whitespaces), startsPartway, stopsPartway))
            }
        }
        return suspects
    }

    /// What differs between `original`, at `range` in the script, and
    /// `fixed`, word by word: the stretch to replace and what goes there,
    /// where words go in, or which come out. Nil for no change.
    private static func wordChange(from original: String, at range: NSRange,
                                   to fixed: String) -> (range: NSRange, replacement: String)? {
        let a = original as NSString
        let b = fixed as NSString
        let aWords = a.wordRanges
        let bWords = b.wordRanges
        let aText = aWords.map(a.substring(with:))
        let bText = bWords.map(b.substring(with:))
        guard !aWords.isEmpty, !bWords.isEmpty else { return nil }

        var prefix = 0
        while prefix < aText.count, prefix < bText.count, aText[prefix] == bText[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < aText.count - prefix, suffix < bText.count - prefix,
              aText[aText.count - 1 - suffix] == bText[bText.count - 1 - suffix] { suffix += 1 }
        let removed = aText.count - prefix - suffix
        let added = bText.count - prefix - suffix
        guard added + removed > 0 else { return nil }

        if added == 0 {
            // Only taken out, with the space beside them, but never every word.
            guard removed < aText.count else { return nil }
            let last = aWords[aText.count - 1 - suffix]
            let start = prefix > 0 ? NSMaxRange(aWords[prefix - 1]) : aWords[0].location
            let end = prefix > 0 ? NSMaxRange(last) : aWords[prefix + removed].location
            return (NSRange(location: range.location + start, length: end - start), "")
        }

        let words = b.substring(with: NSRange(location: bWords[prefix].location,
                                              length: NSMaxRange(bWords[bText.count - 1 - suffix]) - bWords[prefix].location))
        if removed > 0 {
            let start = aWords[prefix].location
            let end = NSMaxRange(aWords[aText.count - 1 - suffix])
            return (NSRange(location: range.location + start, length: end - start), words)
        }
        // Only put in: ahead of the first word, or after the one before.
        if prefix == 0 {
            return (NSRange(location: range.location + aWords[0].location, length: 0), words + " ")
        }
        return (NSRange(location: range.location + NSMaxRange(aWords[prefix - 1]), length: 0), " " + words)
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
private struct ModelRepair {
    @Guide(description: "The whole line again as a complete sentence, with the missing words put back.")
    var line: String
}

@available(iOS 26.0, *)
@Generable
private struct ModelRewrites {
    @Guide(description: "The rewrites worth making, in the order they appear.", .maximumCount(6))
    var changes: [ModelRewrite]
}

@available(iOS 26.0, *)
@Generable
private struct ModelRewrite {
    @Guide(description: "The words to replace, copied exactly from the passage: at most one sentence, all on one line.")
    var text: String
    @Guide(description: "What replaces them, said better.")
    var rewrite: String
}

@available(iOS 26.0, *)
@Generable
private struct ModelProofread {
    @Guide(description: "The typing mistakes, in the order they appear. Empty when there are none.",
           .maximumCount(8))
    var changes: [ModelFix]
}

@available(iOS 26.0, *)
@Generable
private struct ModelFix {
    @Guide(description: "A few words with a typing mistake, copied exactly from the passage, all on one line.")
    var text: String
    @Guide(description: "text with only the mistake corrected.")
    var correction: String
}

@available(iOS 26.0, *)
@Generable
private struct ModelDelivery {
    @Guide(description: "The marks worth adding, in the order they appear.", .maximumCount(8))
    var marks: [ModelMark]
}

@available(iOS 26.0, *)
@Generable
private struct ModelMark {
    @Guide(description: "The kind of mark.")
    var kind: ModelMarkKind
    @Guide(description: "A few words copied exactly from the passage, all on one line.")
    var text: String
    @Guide(description: "Only for cue: what the speaker should do there, one to four words, such as pause, breathe, smile, slow down or look up. Otherwise empty.")
    var cue: String
}

@available(iOS 26.0, *)
@Generable
private enum ModelMarkKind {
    case cue, anchor, bold, italic

    var kind: ScriptSuggestion.Kind {
        switch self {
        case .cue: .cue
        case .anchor: .anchor
        case .bold: .bold
        case .italic: .italic
        }
    }
}

@available(iOS 26.0, *)
@Generable
private struct ModelParagraphs {
    @Guide(description: "The first few words of each sentence that should start a new paragraph, copied exactly, in order.",
           .maximumCount(6))
    var starts: [String]
}

// MARK: - Helpers

private extension NSString {
    /// Where each run of characters between spaces is.
    var wordRanges: [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        for index in 0..<length {
            let isSpace = Unicode.Scalar(character(at: index)).map(CharacterSet.whitespaces.contains) ?? false
            if isSpace {
                if let open = start { ranges.append(NSRange(location: open, length: index - open)) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let open = start { ranges.append(NSRange(location: open, length: length - open)) }
        return ranges
    }

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
