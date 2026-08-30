import Foundation

/// Represents the teleprompter content
/// Text is displayed as a continuous flow with word-by-word highlighting
struct TeleprompterContent {
    /// The full text content (with [note] tags for styling)
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

    var isNote: Bool { cueColor != nil }
}

/// A `[note …]` tag located in a piece of text
struct CueMatch {
    /// The whole tag, brackets included
    let range: NSRange
    /// Just the cue text inside the tag
    let contentRange: NSRange
    let content: String
    let color: CueColor
}

/// A run of a single line: either spoken text or a delivery cue
enum CueSegment {
    case text(String)
    case cue(text: String, color: CueColor)
}

/// Parser for teleprompter scripts with `[note …]` delivery cues
///
/// Two forms are supported, and both mean the same thing apart from color:
/// - `[note smile]` — the original form, rendered in the fallback color
/// - `[note:green smile]` — an explicitly colored cue
///
/// The color name has to be one of `CueColor`'s cases. An unknown name (`[note:mauve x]`)
/// simply doesn't match, so it stays on screen as literal text instead of silently
/// swallowing a word.
enum TeleprompterParser {

    /// `[note]` / `[note:color]` followed by the cue text
    private static let cuePattern: String = {
        let colors = CueColor.allCases.map(\.rawValue).joined(separator: "|")
        return #"\[note(?::(\#(colors)))?\s+([^\]]+)\]"#
    }()

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern, options: [])

    /// Build the tag for a cue. The bare `[note text]` form is used for the fallback
    /// color so scripts stay readable and compatible with what users already typed.
    static func cueTag(text: String, color: CueColor) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return color == .fallback ? "[note \(trimmed)]" : "[note:\(color.rawValue) \(trimmed)]"
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
