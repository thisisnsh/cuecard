import Foundation

/// Represents the teleprompter content
/// Text is displayed as a continuous flow with word-by-word highlighting
struct TeleprompterContent {
    /// The full text content (with [cue] tags for styling)
    let fullText: String
    /// All words for highlighting, in reading order (cue words included)
    let words: [WordInfo]
    /// Every cue tag found in the text, for styling
    let cues: [CueMatch]
}

/// Information about a single word for highlighting
struct WordInfo: Identifiable {
    let id = UUID()
    let text: String
    /// The cue this word belongs to, or nil for spoken script text
    let cueColor: CueColor?

    var isCue: Bool { cueColor != nil }
}

/// A `[cue …]` tag located in a piece of text
struct CueMatch {
    /// The whole tag, brackets included
    let range: NSRange
    /// Just the cue text inside the tag
    let contentRange: NSRange
    let content: String
    let color: CueColor

    /// The scaffolding around the cue text: `[cue:green ` and the closing `]`.
    /// Editors hide these; exported files keep them.
    var syntaxRanges: [NSRange] {
        let contentEnd = contentRange.location + contentRange.length
        let rangeEnd = range.location + range.length

        return [
            NSRange(location: range.location, length: contentRange.location - range.location),
            NSRange(location: contentEnd, length: rangeEnd - contentEnd)
        ].filter { $0.length > 0 }
    }

    /// Where a caret sitting inside the hidden scaffolding should go instead, or nil
    /// if this cue doesn't contain it. Escaping forward out of the opening tag and
    /// backward out of the closing one keeps the cue behaving like a single word.
    func caretEscape(from location: Int) -> Int? {
        let contentEnd = contentRange.location + contentRange.length
        let rangeEnd = range.location + range.length

        if location > range.location && location < contentRange.location {
            return contentRange.location
        }
        if location > contentEnd && location < rangeEnd {
            return rangeEnd
        }
        return nil
    }
}

/// A run of a single line: either spoken text or a delivery cue
enum CueSegment {
    case text(String)
    case cue(text: String, color: CueColor)
}

/// Parser for teleprompter scripts with `[cue …]` delivery cues
///
/// `[cue:green smile]` is what the app writes. Two older spellings still parse so
/// that existing and imported scripts keep working: `[cue smile]` without a color,
/// and `[note …]`, the name this tag had before. `migratedToCueTags` rewrites both
/// into the explicit form, which is also what gets exported.
///
/// A cue never spans a line or contains a bracket, and the color name has to be one
/// of `CueColor`'s cases.
/// An unknown name (`[cue:mauve x]`) simply doesn't match, so it stays on screen as
/// literal text instead of silently swallowing the rest of the script.
enum TeleprompterParser {

    /// `[cue]` / `[cue:color]` followed by the cue text, and the `[note …]` spelling
    /// it replaced. The text may be empty — that's a capsule the user hasn't filled in.
    private static let cuePattern: String = {
        let colors = CueColor.allCases.map(\.rawValue).joined(separator: "|")
        return #"\[(?:cue|note)(?::(\#(colors)))?[ \t]+([^\]\[\n]*)\]"#
    }()

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern, options: [])

    /// Build the tag for a cue. The color is always written out, so a script says the
    /// same thing wherever it ends up.
    static func cueTag(text: String, color: CueColor) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "[cue:\(color.rawValue) \(trimmed)]"
    }

    /// Rewrite older tags — `[note …]`, or a cue with no color — into the explicit
    /// `[cue:color …]` form, leaving everything else, including text that only looks
    /// like a tag, untouched.
    static func migratedToCueTags(_ text: String) -> String {
        let matches = cueMatches(in: text)
        guard !matches.isEmpty else { return text }

        var result = text as NSString
        for match in matches.reversed() {
            let tag = cueTag(text: match.content, color: match.color)
            guard result.substring(with: match.range) != tag else { continue }
            result = result.replacingCharacters(in: match.range, with: tag) as NSString
        }
        return result as String
    }

    /// Parse script content for teleprompter display
    static func parseNotes(_ notes: String) -> TeleprompterContent {
        let cleanedNotes = cleanText(notes)

        return TeleprompterContent(
            fullText: cleanedNotes,
            words: extractWords(from: cleanedNotes),
            cues: cueMatches(in: cleanedNotes)
        )
    }

    /// Clean text for display
    private static func cleanText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find every cue tag in the text, in order
    static func cueMatches(in text: String) -> [CueMatch] {
        let nsText = text as NSString
        let matches = cueRegex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        return matches.map { match in
            let colorRange = match.range(at: 1)
            let color = colorRange.location == NSNotFound
                ? CueColor.fallback
                : CueColor(rawValue: nsText.substring(with: colorRange)) ?? .fallback
            let contentRange = match.range(at: 2)

            return CueMatch(
                range: match.range,
                contentRange: contentRange,
                content: nsText.substring(with: contentRange),
                color: color
            )
        }
    }

    /// Split a single line into spoken text and cue runs.
    ///
    /// Shared by the teleprompter and the PiP overlay so both render cues identically.
    static func segments(in line: String) -> [CueSegment] {
        let nsLine = line as NSString
        let matches = cueMatches(in: line)

        if matches.isEmpty {
            return [.text(line)]
        }

        var segments: [CueSegment] = []
        var lastEnd = 0

        for match in matches {
            // Text before the cue
            if match.range.location > lastEnd {
                let before = nsLine
                    .substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                    .trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            segments.append(.cue(text: match.content, color: match.color))
            lastEnd = match.range.location + match.range.length
        }

        // Text after the last cue
        if lastEnd < nsLine.length {
            let after = nsLine
                .substring(from: lastEnd)
                .trimmingCharacters(in: .whitespaces)
            if !after.isEmpty {
                segments.append(.text(after))
            }
        }

        return segments
    }

    /// Extract words in reading order, tagging the ones that belong to a cue.
    ///
    /// Cue words are counted too, matching what the teleprompter lays out, so word
    /// indices line up with the highlighting.
    private static func extractWords(from text: String) -> [WordInfo] {
        var words: [WordInfo] = []

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            for segment in segments(in: line) {
                switch segment {
                case .cue(let cueText, let color):
                    for word in cueText.split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), cueColor: color))
                    }
                case .text(let textContent):
                    for word in textContent.split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), cueColor: nil))
                    }
                }
            }
        }

        return words
    }

    /// Format time as mm:ss string
    static func formatTime(_ seconds: Int) -> String {
        let isNegative = seconds < 0
        let absSeconds = abs(seconds)
        let minutes = absSeconds / 60
        let secs = absSeconds % 60
        let formatted = String(format: "%02d:%02d", minutes, secs)
        return isNegative ? "-\(formatted)" : formatted
    }

    /// Calculate word index based on elapsed time and words per minute
    static func calculateCurrentWordIndex(
        elapsedTime: Double,
        totalWords: Int,
        wordsPerMinute: Double
    ) -> Int {
        let wordsPerSecond = wordsPerMinute / 60.0
        let wordIndex = Int(elapsedTime * wordsPerSecond)
        return min(wordIndex, totalWords - 1)
    }

    /// Calculate line index based on elapsed time and lines per minute
    static func calculateCurrentLineIndex(
        elapsedTime: Double,
        totalLines: Int,
        linesPerMinute: Double
    ) -> Int {
        let linesPerSecond = linesPerMinute / 60.0
        let lineIndex = Int(elapsedTime * linesPerSecond)
        return min(lineIndex, totalLines - 1)
    }
}
