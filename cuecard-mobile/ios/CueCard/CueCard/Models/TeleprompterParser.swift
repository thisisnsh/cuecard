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
    /// Whether the text places any images
    let hasImages: Bool
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
    let content: String
}

/// An `[image …]` tag located in a piece of text
struct ImageMatch {
    /// The whole tag, brackets included
    let range: NSRange
    /// The image's file name in the app's image store
    let name: String
}

/// A run of a single line: spoken text, a delivery cue, or an image
enum CueSegment {
    case text(String)
    case cue(String)
    /// The image's file name
    case image(String)
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
///
/// `[image 3fa9….jpg]` places an image, named for its file in the app's image
/// store. The editor shows it as the image itself, and so does everything
/// that reads the script; where an image can't be drawn, it's left out.
enum TeleprompterParser {

    /// `[cue]` / `[note]`, an optional legacy `:color`, then the cue text
    private static let cuePattern = #"\[(?:cue|note)(?::[A-Za-z]+)?(?:[ \t]+([^\]\n]*))?\]"#

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern, options: [])

    /// `[image name.ext]`. The name is kept to letters, digits and dashes, so
    /// it's always a plain file name and never a path.
    private static let imagePattern = #"\[image[ \t]+([A-Za-z0-9-]+\.[A-Za-z0-9]+)\]"#

    private static let imageRegex = try! NSRegularExpression(pattern: imagePattern, options: [])

    /// The tag for an image in the store.
    static func imageTag(name: String) -> String {
        "[image \(name)]"
    }

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
        // A script written as cards reads straight through, a card to a line.
        let cleanedNotes = cleanText(CueCards.removingSeparators(from: notes))

        return TeleprompterContent(
            fullText: cleanedNotes,
            words: extractWords(from: cleanedNotes),
            cues: cueMatches(in: cleanedNotes),
            hasImages: !imageMatches(in: cleanedNotes).isEmpty
        )
    }

    /// Clean text for display
    private static func cleanText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrite every cue tag into the canonical `[cue …]` spelling, and every
    /// card separator into `[separator]`.
    ///
    /// Used at the file boundary, so a script that leaves the app carries the
    /// current syntax and one that arrives is brought up to it.
    static func normalizingTags(in text: String) -> String {
        let result = NSMutableString(string: CueCards.normalizingSeparators(in: text))

        // Back to front, so replacing a tag doesn't shift the ones still to come.
        for match in cueMatches(in: result as String).reversed() {
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

            return CueMatch(
                range: match.range,
                contentRange: contentRange,
                content: nsText.substring(with: contentRange)
            )
        }
    }

    /// Find every image tag in the text, in order. One written inside a cue
    /// belongs to the cue's text.
    static func imageMatches(in text: String) -> [ImageMatch] {
        let nsText = text as NSString
        let cues = cueMatches(in: text).map(\.range)
        return imageRegex
            .matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            .filter { match in !cues.contains { NSIntersectionRange($0, match.range).length > 0 } }
            .map { ImageMatch(range: $0.range, name: nsText.substring(with: $0.range(at: 1))) }
    }

    /// The names of the images the text places, each once.
    static func imageNames(in text: String) -> Set<String> {
        Set(imageMatches(in: text).map(\.name))
    }

    /// The text with its image tags taken out, for a preview or a search.
    static func removingImages(from text: String) -> String {
        let result = NSMutableString(string: text)
        for match in imageMatches(in: text).reversed() {
            result.replaceCharacters(in: match.range, with: "")
        }
        return result as String
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

    /// Split a single line into spoken text, cue and image runs.
    ///
    /// Shared by the teleprompter and the PiP overlay so both render cues identically.
    static func segments(in line: String) -> [CueSegment] {
        let nsLine = line as NSString
        let tags = (cueMatches(in: line).map { ($0.range, CueSegment.cue($0.content)) }
            + imageMatches(in: line).map { ($0.range, CueSegment.image($0.name)) })
            .sorted { $0.0.location < $1.0.location }

        if tags.isEmpty {
            return [.text(line)]
        }

        var segments: [CueSegment] = []
        var lastEnd = 0

        for (range, tag) in tags {
            // Text before the tag
            if range.location > lastEnd {
                let before = nsLine
                    .substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
                    .trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            segments.append(tag)
            lastEnd = NSMaxRange(range)
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
                case .cue(let cueText):
                    for word in cueText.split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), isCue: true))
                    }
                case .text(let textContent):
                    for word in RichText.plain(textContent).split(whereSeparator: \.isWhitespace) {
                        words.append(WordInfo(text: String(word), isCue: false))
                    }
                case .image:
                    break
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
        return max(0, min(wordIndex, totalWords - 1))
    }

    /// Calculate line index based on elapsed time and lines per minute
    static func calculateCurrentLineIndex(
        elapsedTime: Double,
        totalLines: Int,
        linesPerMinute: Double
    ) -> Int {
        let linesPerSecond = linesPerMinute / 60.0
        let lineIndex = Int(elapsedTime * linesPerSecond)
        return max(0, min(lineIndex, totalLines - 1))
    }
}
