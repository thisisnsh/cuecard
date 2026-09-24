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

    var systemImage: String {
        switch self {
        case .teleprompter: return "text.alignleft"
        case .cards: return "rectangle.stack"
        }
    }
}

/// Where a deck of cards is read. It sets how long a card can be: a
/// Live Activity on the Lock Screen has room for a few lines, the app a whole
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
    /// The Lock Screen limit keeps the Live Activity readable.
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
/// The editor shows each card on its own, and the tag is only written where
/// the deck is stored, imported and exported. The teleprompter reads a
/// separator as a line break.
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

    /// How much of a single card shows against `limit`.
    static func measure(card: String, limit: Int) -> CardMeasure {
        let nsText = card as NSString
        return measure(NSRange(location: 0, length: nsText.length), in: nsText,
                       cues: TeleprompterParser.cueMatches(in: card), limit: limit)
    }

    /// The cards as the editor shows them: blank ones kept, so a card just
    /// added stays put, and the line breaks around each separator left out.
    static func editableCards(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let nsText = normalized as NSString
        return cardRanges(in: normalized)
            .map { nsText.substring(with: $0).trimmingCharacters(in: .newlines) }
    }

    /// The script for a deck, a separator on its own line between each card.
    /// A single blank card is no script at all.
    static func script(for cards: [String]) -> String {
        if cards.count == 1, cards[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        return cards.joined(separator: "\n\(separatorTag)\n")
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
