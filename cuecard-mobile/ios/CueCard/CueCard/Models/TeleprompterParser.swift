import Foundation

/// Represents the teleprompter content
/// Text is displayed as a continuous flow with word-by-word highlighting
struct TeleprompterContent {
    /// The full text content (with tags for styling)
    let fullText: String
    /// All words for highlighting, in reading order (tag words included)
    let words: [WordInfo]
    /// Every tag found in the text, for styling
    let tags: [ScriptTag]
}

/// Information about a single word for highlighting
struct WordInfo: Identifiable {
    let id = UUID()
    let text: String
    /// Whether the word belongs to a tag rather than the spoken script
    let isCue: Bool
}

/// A `[cue …]` or `[pause …]` located in a piece of text
struct ScriptTag {
    /// What the tag is for
    enum Kind: Equatable {
        /// A delivery reminder: read, not spoken
        case cue
        /// A beat the teleprompter waits out before scrolling on
        case pause(seconds: Double)
    }

    /// The whole tag, brackets included
    let range: NSRange
    /// Just what is written inside the tag; empty for one with nothing in it yet
    let contentRange: NSRange
    let content: String
    let kind: Kind

    var isPause: Bool {
        if case .pause = kind { return true }
        return false
    }
}

/// A run of a single line: spoken text, a delivery cue, or a pause
enum ScriptSegment {
    case text(String)
    case cue(String)
    /// A pause, and how long it holds the script for
    case pause(Double)
}

/// Parser for teleprompter scripts with `[cue …]` delivery cues and `[pause …]`
/// beats
///
/// `[cue smile]` is the form to write. `[note smile]` is the older spelling and
/// means exactly the same thing, so scripts written before the rename keep
/// working; importing or exporting rewrites them to `[cue …]`.
///
/// `[pause 5]` holds the script still for five seconds when it reaches the
/// reading line — a beat written into the script rather than counted in the head.
///
/// A tag only counts once its closing bracket is there — `[cue smi` is still
/// plain text, so nothing changes under the user mid-word. Tags can't span lines
/// for the same reason: a stray `[` shouldn't swallow the paragraphs after it.
///
/// Every cue is drawn in the one color from Settings, and every pause in grey. An
/// older `[cue:green …]` still parses, but the color name is ignored and dropped
/// on the next import or export.
enum TeleprompterParser {

    /// `[cue]` / `[note]`, an optional legacy `:color`, then the cue text
    private static let cuePattern = #"\[(?:cue|note)(?::[A-Za-z]+)?(?:[ \t]+([^\]\n]*))?\]"#

    /// `[pause 5]`, the seconds it waits
    private static let pausePattern = #"\[pause(?:[ \t]+([^\]\n]*))?\]"#

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern, options: [])
    private static let pauseRegex = try! NSRegularExpression(pattern: pausePattern, options: [])

    /// What each tag opens with, and what they all close with. Typing `[` writes a
    /// cue's pair at once, leaving the caret between them.
    static let cueTagPrefix = "[cue "
    static let pauseTagPrefix = "[pause "
    static let tagSuffix = "]"

    /// The tag inserted for a cue that hasn't been written yet.
    static let emptyCueTag = cueTagPrefix + tagSuffix

    /// What a pause is worth when one is dropped in and not yet changed.
    static let defaultPauseSeconds: Double = 5

    /// The longest a pause can be. Kept under an hour so its countdown stays five
    /// characters wide, which is what lets it tick down without re-wrapping the
    /// script around it.
    static let maximumPauseSeconds: Double = 3599

    /// Build the tag for a cue.
    static func cueTag(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cueTagPrefix + trimmed + tagSuffix
    }

    /// Build the tag for a pause of `seconds`.
    static func pauseTag(seconds: Double) -> String {
        pauseTagPrefix + secondsLabel(seconds) + tagSuffix
    }

    /// Seconds written the way they go in: `5`, or `2.5`.
    static func secondsLabel(_ seconds: Double) -> String {
        let whole = seconds.rounded()
        return abs(seconds - whole) < 0.001 ? "\(Int(whole))" : String(format: "%g", seconds)
    }

    /// Parse script content for teleprompter display
    static func parseNotes(_ notes: String) -> TeleprompterContent {
        let cleanedNotes = cleanText(notes)

        return TeleprompterContent(
            fullText: cleanedNotes,
            words: extractWords(from: cleanedNotes),
            tags: tags(in: cleanedNotes)
        )
    }

    /// Clean text for display
    private static func cleanText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrite every tag into its canonical spelling.
    ///
    /// Used at the file boundary, so a script that leaves the app carries the
    /// current syntax and one that arrives is brought up to it.
    static func normalizingTags(in text: String) -> String {
        let result = NSMutableString(string: text)

        // Back to front, so replacing a tag doesn't shift the ones still to come.
        for tag in tags(in: text).reversed() {
            switch tag.kind {
            case .cue:
                result.replaceCharacters(in: tag.range, with: cueTag(text: tag.content))
            case .pause(let seconds):
                result.replaceCharacters(in: tag.range, with: pauseTag(seconds: seconds))
            }
        }

        return result as String
    }

    /// Find every tag in the text, in the order it is read.
    ///
    /// Cues and pauses are matched separately — they can't overlap, each starting
    /// with a keyword of its own — and merged back into reading order.
    static func tags(in text: String) -> [ScriptTag] {
        let nsText = text as NSString
        let whole = NSRange(location: 0, length: nsText.length)

        func matches(_ regex: NSRegularExpression, kind: (String) -> ScriptTag.Kind) -> [ScriptTag] {
            regex.matches(in: text, options: [], range: whole).map { match in
                // A tag written with no text at all carries no group; treat it as
                // empty, sitting just inside the closing bracket.
                let contentRange = match.range(at: 1).location == NSNotFound
                    ? NSRange(location: NSMaxRange(match.range) - 1, length: 0)
                    : match.range(at: 1)
                let content = nsText.substring(with: contentRange)

                return ScriptTag(
                    range: match.range,
                    contentRange: contentRange,
                    content: content,
                    kind: kind(content)
                )
            }
        }

        let cues = matches(cueRegex) { _ in .cue }
        let pauses = matches(pauseRegex) { .pause(seconds: pauseSeconds(forContent: $0)) }

        return (cues + pauses).sorted { $0.range.location < $1.range.location }
    }

    /// How long a pause holds for, read off what is written inside it. A pause
    /// with nothing usable in it waits no time at all, which the teleprompter
    /// shows as one that has already run out.
    static func pauseSeconds(forContent content: String) -> Double {
        guard let seconds = Double(content.trimmingCharacters(in: .whitespaces)), seconds > 0 else {
            return 0
        }
        return min(seconds, maximumPauseSeconds)
    }

    /// The tag the caret is sitting inside, if it is inside one.
    ///
    /// A caret resting against either bracket counts as outside: that's a spot a
    /// new tag can legitimately go, and tags don't nest.
    static func tag(containing location: Int, in text: String) -> ScriptTag? {
        tags(in: text).first {
            $0.range.location < location && location < NSMaxRange($0.range)
        }
    }

    /// Split a single line into spoken text, cues and pauses.
    ///
    /// Shared by the teleprompter and the PiP overlay so both render tags identically.
    static func segments(in line: String) -> [ScriptSegment] {
        let nsLine = line as NSString
        let lineTags = tags(in: line)

        if lineTags.isEmpty {
            return [.text(line)]
        }

        var segments: [ScriptSegment] = []
        var lastEnd = 0

        for tag in lineTags {
            // Text before the tag
            if tag.range.location > lastEnd {
                let before = nsLine
                    .substring(with: NSRange(location: lastEnd, length: tag.range.location - lastEnd))
                    .trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            switch tag.kind {
            case .cue:
                segments.append(.cue(tag.content))
            case .pause(let seconds):
                segments.append(.pause(seconds))
            }
            lastEnd = NSMaxRange(tag.range)
        }

        // Text after the last tag
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

    /// Extract words in reading order, tagging the ones that belong to a tag
    /// rather than to the script.
    ///
    /// Tag words are counted too, matching what the teleprompter lays out, so word
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
                case .pause(let seconds):
                    words.append(WordInfo(text: secondsLabel(seconds), isCue: true))
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
}
