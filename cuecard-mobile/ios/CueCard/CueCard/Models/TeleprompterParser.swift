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
    /// Whether the word belongs to a cue rather than the spoken script
    let isCue: Bool
}

/// A `[cue …]` tag located in a piece of text
struct CueMatch {
    /// The whole tag, brackets included
    let range: NSRange
    /// Just the cue text inside the tag; empty for a cue with nothing written in it yet
    let contentRange: NSRange
    /// The cue exactly as it is written, hold and all
    let content: String
    /// The same cue as the teleprompter reads it
    let run: CueRun
}

/// A `[cue …]` as the teleprompter reads it: the words to show, and how long the
/// script should hold still on them.
struct CueRun: Equatable {
    /// The cue's own words, with any hold taken off the front
    let text: String
    /// Seconds the script holds with this cue on the reading line. Zero for a cue
    /// the script just scrolls past.
    let holdSeconds: Double

    /// What the teleprompter draws — the hold first, then the words, which is how
    /// the cue is written. What you type is what you read.
    var displayText: String {
        guard holdSeconds > 0 else { return text }
        let label = TeleprompterParser.holdLabel(holdSeconds)
        return text.isEmpty ? label : "\(label) \(text)"
    }
}

/// A run of a single line: either spoken text or a delivery cue
enum CueSegment {
    case text(String)
    case cue(CueRun)
}

/// Parser for teleprompter scripts with `[cue …]` delivery cues
///
/// `[cue smile]` is the form to write. `[note smile]` is the older spelling and
/// means exactly the same thing, so scripts written before the rename keep
/// working; importing or exporting rewrites them to `[cue …]`.
///
/// A tag only counts once its closing bracket is there — `[cue smi` is still
/// plain text, so nothing changes under the user mid-word. Cues can't span lines
/// for the same reason: a stray `[` shouldn't swallow the paragraphs after it.
///
/// Every cue is drawn in the one color from Settings. An older `[cue:green …]`
/// still parses, but the color name is ignored and dropped on the next import
/// or export.
enum TeleprompterParser {

    /// `[cue]` / `[note]`, an optional legacy `:color`, then the cue text
    private static let cuePattern = #"\[(?:cue|note)(?::[A-Za-z]+)?(?:[ \t]+([^\]\n]*))?\]"#

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern, options: [])

    /// A count of seconds opening a cue: `[cue 3s look up]`. The digits sit
    /// against the `s` and the cue's own words follow, so a cue that merely starts
    /// with a number — `[cue 3 fingers]` — is left as words.
    private static let holdPattern = #"^(\d{1,3}(?:\.\d+)?)s(?:\s+|$)"#

    private static let holdRegex = try! NSRegularExpression(pattern: holdPattern, options: [])

    /// What an empty cue opens with, and closes with. Typing `[` writes both at
    /// once, leaving the caret between them.
    static let cueTagPrefix = "[cue "
    static let cueTagSuffix = "]"

    /// The tag inserted for a cue that hasn't been written yet.
    static let emptyCueTag = cueTagPrefix + cueTagSuffix

    /// Build the tag for a cue.
    static func cueTag(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cueTagPrefix + trimmed + cueTagSuffix
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

    /// Rewrite every cue tag into the canonical `[cue …]` spelling.
    ///
    /// Used at the file boundary, so a script that leaves the app carries the
    /// current syntax and one that arrives is brought up to it.
    static func normalizingTags(in text: String) -> String {
        let result = NSMutableString(string: text)

        // Back to front, so replacing a tag doesn't shift the ones still to come.
        for match in cueMatches(in: text).reversed() {
            result.replaceCharacters(in: match.range, with: cueTag(text: match.content))
        }

        return result as String
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
            // `[cue]` carries no text group at all; treat it as an empty cue
            // sitting just inside the closing bracket.
            let contentRange = match.range(at: 1).location == NSNotFound
                ? NSRange(location: NSMaxRange(match.range) - 1, length: 0)
                : match.range(at: 1)

            let content = nsText.substring(with: contentRange)
            return CueMatch(
                range: match.range,
                contentRange: contentRange,
                content: content,
                run: run(forContent: content)
            )
        }
    }

    /// The cue tag the caret is sitting inside, if it is inside one.
    ///
    /// A caret resting against either bracket counts as outside: that's a spot a
    /// new cue can legitimately go, and cues don't nest.
    static func cueTag(containing location: Int, in text: String) -> CueMatch? {
        cueMatches(in: text).first {
            $0.range.location < location && location < NSMaxRange($0.range)
        }
    }

    /// Read a cue's contents: how long it holds the script, and what it says.
    ///
    /// A hold is written at the front as a count of seconds — `[cue 5s drink]`.
    /// When the cue reaches the reading line the script stops there for that long,
    /// and the clock carries on running through it.
    static func run(forContent content: String) -> CueRun {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        let nsTrimmed = trimmed as NSString

        guard let match = holdRegex.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(location: 0, length: nsTrimmed.length)
        ), let seconds = Double(nsTrimmed.substring(with: match.range(at: 1))), seconds > 0 else {
            return CueRun(text: trimmed, holdSeconds: 0)
        }

        return CueRun(
            text: nsTrimmed.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces),
            holdSeconds: seconds
        )
    }

    /// A hold written back out the way it goes in: `3s`, or `2.5s`.
    static func holdLabel(_ seconds: Double) -> String {
        let whole = seconds.rounded()
        return abs(seconds - whole) < 0.001 ? "\(Int(whole))s" : String(format: "%gs", seconds)
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

            segments.append(.cue(match.run))
            lastEnd = NSMaxRange(match.range)
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
                case .cue(let cue):
                    for word in cue.displayText.split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), isCue: true))
                    }
                case .text(let textContent):
                    for word in textContent.split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), isCue: false))
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
