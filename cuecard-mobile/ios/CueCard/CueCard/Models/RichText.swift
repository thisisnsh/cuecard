import Foundation

/// How a stretch of script is set: bold, italic, or both.
struct EmphasisStyle: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let bold = EmphasisStyle(rawValue: 1 << 0)
    static let italic = EmphasisStyle(rawValue: 1 << 1)

    /// The marker that writes this style: `*bold*` or `_italic_`.
    var marker: String {
        self == .bold ? "*" : "_"
    }
}

/// A run of emphasis written in Markdown.
struct Emphasis {
    let style: EmphasisStyle
    /// The marker that opens it, `*` or `_`.
    let open: NSRange
    /// The marker that closes it. Nil while it is still being typed, in which
    /// case it runs to the end of the line, or to a cue.
    let close: NSRange?
    /// What it styles, between the markers.
    let content: NSRange

    var isClosed: Bool { close != nil }

    /// Markers and content together.
    var range: NSRange { NSUnionRange(open, close ?? content) }
}

/// The plain text of some script with its emphasis markers taken out, and the
/// styles that were written with them.
struct StyledText {
    struct Run {
        var text: String
        var style: EmphasisStyle
    }

    let runs: [Run]

    var plain: String { runs.map(\.text).joined() }
}

/// Emphasis in a script, written the way chat apps write it:
///
/// - `*bold*`
/// - `_italic_`
///
/// Doubled markers — Markdown's `**bold**` and `__italic__` — read the same,
/// so a script brought in from elsewhere keeps its emphasis.
///
/// Like cues, emphasis doesn't run across lines, and none is read inside a cue.
/// A marker only opens against a word and only closes after one, so `5 * 3`
/// and a `* ` bullet stay as they are; an `_` inside a word, as in
/// `snake_case`, is left alone too.
enum RichText {
    private static let star: unichar = 0x2A // *
    private static let underscore: unichar = 0x5F // _

    private struct Opener {
        let marker: unichar
        let location: Int
        let length: Int
    }

    /// Every emphasis in the text, closed ones and — at the end of a line — the
    /// ones still waiting to be closed. `skipping` are ranges nothing is read
    /// inside, such as the cue tags.
    static func emphases(in text: String, skipping: [NSRange] = []) -> [Emphasis] {
        let nsText = text as NSString
        var result: [Emphasis] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines, .substringNotRequired]
        ) { _, line, _, _ in
            result += emphases(inLine: line, of: nsText, skipping: skipping)
        }
        return result
    }

    private static func emphases(inLine line: NSRange, of text: NSString, skipping: [NSRange]) -> [Emphasis] {
        var found: [Emphasis] = []
        var stack: [Opener] = []
        var index = line.location
        let end = NSMaxRange(line)

        func isSkipped(_ location: Int) -> Bool {
            skipping.contains { NSLocationInRange(location, $0) }
        }

        func character(at location: Int) -> unichar? {
            guard location >= line.location, location < end, !isSkipped(location) else { return nil }
            return text.character(at: location)
        }

        // What's still open where a cue or the line ends never closed; the
        // editor shows it styled so far, as it's being typed.
        func endOpeners(at location: Int) {
            for opener in stack {
                let open = NSRange(location: opener.location, length: opener.length)
                found.append(Emphasis(
                    style: style(for: opener.marker, length: opener.length),
                    open: open,
                    close: nil,
                    content: NSRange(location: NSMaxRange(open), length: location - NSMaxRange(open))
                ))
            }
            stack.removeAll()
        }

        while index < end {
            // Emphasis doesn't run into a cue, which is drawn apart from the script.
            if isSkipped(index) {
                endOpeners(at: index)
                index += 1
                continue
            }

            let marker = text.character(at: index)
            guard marker == star || marker == underscore else {
                index += 1
                continue
            }

            var runEnd = index
            while runEnd < end, text.character(at: runEnd) == marker, !isSkipped(runEnd) { runEnd += 1 }
            let runLength = runEnd - index

            let previous = character(at: index - 1)
            let next = character(at: runEnd)
            var canOpen = next.map { !isBlank($0) } ?? false
            var canClose = previous.map { !isBlank($0) } ?? false
            if marker == underscore {
                canOpen = canOpen && !(previous.map(isWordCharacter) ?? false)
                canClose = canClose && !(next.map(isWordCharacter) ?? false)
            }

            var used = 0
            if canClose {
                // Inner markers close first, so `**_both_**` closes its `_`
                // and then its `**`.
                while used < runLength,
                      let openerIndex = stack.lastIndex(where: { $0.marker == marker }),
                      stack[openerIndex].length <= runLength - used {
                    let opener = stack[openerIndex]
                    let open = NSRange(location: opener.location, length: opener.length)
                    let close = NSRange(location: index + used, length: opener.length)
                    found.append(Emphasis(
                        style: style(for: marker, length: opener.length),
                        open: open,
                        close: close,
                        content: NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
                    ))
                    // Anything opened inside it and never closed was never emphasis.
                    stack.removeSubrange(openerIndex...)
                    used += opener.length
                }
            }

            if canOpen {
                // `***` opens as `**` then `*`, each closed in turn.
                var location = index + used
                while location < runEnd {
                    let length = min(2, runEnd - location)
                    stack.append(Opener(marker: marker, location: location, length: length))
                    location += length
                }
            }

            index = runEnd
        }

        endOpeners(at: end)
        return found
    }

    private static func style(for marker: unichar, length: Int) -> EmphasisStyle {
        marker == star ? .bold : .italic
    }

    private static func isBlank(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isWordCharacter(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    /// The text as it reads, closed markers taken out and each stretch carrying
    /// its style. A marker never closed is left in as written.
    static func styled(_ text: String) -> StyledText {
        let nsText = text as NSString
        let closed = emphases(in: text).filter(\.isClosed)
        guard !closed.isEmpty else { return StyledText(runs: text.isEmpty ? [] : [.init(text: text, style: [])]) }

        var markers = IndexSet()
        for emphasis in closed {
            markers.insert(integersIn: Range(emphasis.open)!)
            if let close = emphasis.close { markers.insert(integersIn: Range(close)!) }
        }

        var runs: [StyledText.Run] = []
        var start = 0
        var current = EmphasisStyle()
        func flush(to location: Int) {
            guard location > start else { return }
            var piece = ""
            for range in IndexSet(integersIn: start..<location).subtracting(markers).rangeView {
                piece += nsText.substring(with: NSRange(range))
            }
            if !piece.isEmpty {
                if let last = runs.last, last.style == current {
                    runs[runs.count - 1].text += piece
                } else {
                    runs.append(.init(text: piece, style: current))
                }
            }
            start = location
        }

        // Styles only change where a marker starts or ends.
        var boundaries = Set<Int>()
        for emphasis in closed {
            boundaries.insert(emphasis.content.location)
            boundaries.insert(NSMaxRange(emphasis.content))
        }
        for boundary in boundaries.sorted() {
            flush(to: boundary)
            current = closed
                .filter { NSLocationInRange(boundary, $0.content) }
                .reduce(EmphasisStyle()) { $0.union($1.style) }
        }
        flush(to: nsText.length)
        return StyledText(runs: runs)
    }

    /// Where the markers of closed emphasis are, which don't show once read.
    static func markerRanges(in text: String, skipping: [NSRange] = []) -> [NSRange] {
        emphases(in: text, skipping: skipping).flatMap { emphasis in
            emphasis.close.map { [emphasis.open, $0] } ?? []
        }
    }

    /// The text with its emphasis markers taken out.
    static func plain(_ text: String) -> String {
        styled(text).plain
    }
}
