import Foundation

/// What the editor writes and the Play button opens: a script read as it
/// scrolls, or a deck of cards moved through one at a time.
///
/// The raw value is persisted with the settings, so it has to stay stable.
enum ScriptMode: String, Codable, CaseIterable, Identifiable {
    case teleprompter
    case cards

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teleprompter: return "Teleprompter"
        case .cards: return "Cards"
        }
    }
}

/// Where a deck of cards is read. It sets how long a card can be: a
/// notification on the Lock Screen has room for a few lines, the app a whole
/// screen.
///
/// The raw value is persisted with the settings, so it has to stay stable.
enum CardDisplay: String, Codable, CaseIterable, Identifiable {
    case lockScreen
    case inApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockScreen: return "Lock Screen"
        case .inApp: return "In App"
        }
    }

    var systemImage: String {
        switch self {
        case .lockScreen: return "lock.fill"
        case .inApp: return "iphone"
        }
    }

    /// Characters a card holds before the editor marks the rest as too long.
    /// The Lock Screen's is about what a notification shows there uncut.
    var characterLimit: Int {
        switch self {
        case .lockScreen: return 120
        case .inApp: return 280
        }
    }
}

/// How much of a card shows, and where it runs past its limit.
struct CardMeasure {
    /// Characters the card shows: its text and cues, without the tag syntax or
    /// the blank space around it.
    let length: Int
    /// From the first character past the limit to the end of the card.
    let overflow: NSRange?
}

/// Cards mode's `[separator]` tag, which ends one card and starts the next.
///
/// Like `[cue …]`, it is plain text in the script, so it survives import and
/// export as it is. The teleprompter reads a separator as a line break.
enum CueCards {
    static let separatorTag = "[separator]"

    private static let separatorRegex = try! NSRegularExpression(
        pattern: #"\[separator\]"#,
        options: [.caseInsensitive]
    )

    /// Every separator in the text, in order.
    static func separatorRanges(in text: String) -> [NSRange] {
        let length = (text as NSString).length
        return separatorRegex
            .matches(in: text, options: [], range: NSRange(location: 0, length: length))
            .map(\.range)
    }

    /// The separator the caret is inside, if it is inside one. Against either
    /// bracket counts as outside, like a cue.
    static func separator(containing location: Int, in text: String) -> NSRange? {
        separatorRanges(in: text).first {
            $0.location < location && location < NSMaxRange($0)
        }
    }

    /// The stretches of text between separators, blank ones included.
    static func cardRanges(in text: String) -> [NSRange] {
        let length = (text as NSString).length
        var ranges: [NSRange] = []
        var start = 0
        for separator in separatorRanges(in: text) {
            ranges.append(NSRange(location: start, length: separator.location - start))
            start = NSMaxRange(separator)
        }
        ranges.append(NSRange(location: start, length: length - start))
        return ranges
    }

    /// The cards of a script, trimmed, with blank ones left out.
    static func cards(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let nsText = normalized as NSString
        return cardRanges(in: normalized)
            .map { nsText.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Separators swapped for line breaks, for the teleprompter.
    static func removingSeparators(from text: String) -> String {
        let length = (text as NSString).length
        return separatorRegex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(location: 0, length: length), withTemplate: "\n"
        )
    }

    /// Every separator written in the canonical lowercase spelling.
    static func normalizingSeparators(in text: String) -> String {
        let length = (text as NSString).length
        return separatorRegex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(location: 0, length: length), withTemplate: separatorTag
        )
    }

    /// Count what a card shows against `limit`. Cue text counts, the `[cue`
    /// and `]` around it don't, and neither does blank space at either end.
    static func measure(_ card: NSRange, in text: NSString, cues: [CueMatch], limit: Int) -> CardMeasure {
        var count = 0
        var solidCount = 0
        var overflowStart: Int?

        text.enumerateSubstrings(in: card, options: .byComposedCharacterSequences) { character, range, _, _ in
            guard let character else { return }
            let isTagSyntax = cues.contains {
                NSLocationInRange(range.location, $0.range) && !NSLocationInRange(range.location, $0.contentRange)
            }
            if isTagSyntax { return }

            let isBlank = character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isBlank && count == 0 { return }
            count += 1
            guard !isBlank else { return }
            solidCount = count
            if count > limit && overflowStart == nil {
                overflowStart = range.location
            }
        }

        let overflow = overflowStart.map { NSRange(location: $0, length: NSMaxRange(card) - $0) }
        return CardMeasure(length: solidCount, overflow: overflow)
    }

    /// Where the caret is in the deck, for the editor's card count.
    struct Position {
        /// One-based, among the cards with something in them. Nil while the
        /// caret sits in a card that is still blank.
        let number: Int?
        let total: Int
        let measure: CardMeasure
    }

    static func position(of location: Int, in text: String, limit: Int) -> Position {
        let nsText = text as NSString
        let cues = TeleprompterParser.cueMatches(in: text)
        let ranges = cardRanges(in: text)
        let measures = ranges.map { measure($0, in: nsText, cues: cues, limit: limit) }

        // A caret inside a separator belongs to the card before it.
        let separatorsBefore = separatorRanges(in: text).filter { NSMaxRange($0) <= location }.count
        let current = min(separatorsBefore, ranges.count - 1)

        let filled = measures.map { $0.length > 0 }
        let number = filled[current] ? filled[...current].filter { $0 }.count : nil
        return Position(number: number, total: filled.filter { $0 }.count, measure: measures[current])
    }

    /// How many cards run past `limit`.
    static func overflowingCount(in text: String, limit: Int) -> Int {
        let nsText = text as NSString
        let cues = TeleprompterParser.cueMatches(in: text)
        return cardRanges(in: text).filter { measure($0, in: nsText, cues: cues, limit: limit).overflow != nil }.count
    }

    /// A card as runs of text and cue, the way the app and the watch draw it,
    /// and the Lock Screen as plain text. Past `maxLength` characters the rest is cut, which only
    /// a card far over its limit ever reaches.
    static func runs(for card: String, maxLength: Int = .max) -> [CueCardRun] {
        var runs: [CueCardRun] = []
        var remaining = maxLength

        func append(_ text: String, isCue: Bool) {
            guard remaining > 0, !text.isEmpty else { return }
            let piece = String(text.prefix(remaining))
            remaining -= piece.count
            if let last = runs.last, last.isCue == isCue {
                runs[runs.count - 1].text += piece
            } else {
                runs.append(CueCardRun(text: piece, isCue: isCue))
            }
        }

        for (lineIndex, line) in card.components(separatedBy: "\n").enumerated() {
            if lineIndex > 0 { append("\n", isCue: false) }

            var isFirst = true
            for segment in TeleprompterParser.segments(in: line) {
                switch segment {
                case .text(let text):
                    guard !text.isEmpty else { continue }
                    if !isFirst { append(" ", isCue: false) }
                    append(text, isCue: false)
                case .cue(let cue):
                    let cue = cue.trimmingCharacters(in: .whitespaces)
                    guard !cue.isEmpty else { continue }
                    if !isFirst { append(" ", isCue: false) }
                    append(cue, isCue: true)
                }
                isFirst = false
            }
        }
        return runs
    }
}

// MARK: - Separator insertion

extension NSString {
    /// The text to splice in for a separator at `location`, on a line of its
    /// own, and how far into it the caret belongs: the start of the new card.
    func separatorInsertion(at location: Int) -> (text: String, caretOffset: Int) {
        let previous = location > 0 ? substring(with: NSRange(location: location - 1, length: 1)) : ""
        let next = location < length ? substring(with: NSRange(location: location, length: 1)) : ""

        let leading = previous.isEmpty || previous == "\n" ? "" : "\n"
        // A line break already waiting after the caret serves as the tag's own.
        let trailing = next == "\n" ? "" : "\n"
        let text = leading + CueCards.separatorTag + trailing
        let caretOffset = (leading as NSString).length + (CueCards.separatorTag as NSString).length + 1
        return (text, caretOffset)
    }
}
