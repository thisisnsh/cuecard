import SwiftUI

/// A stretch of a card: spoken text, or a cue drawn in the cue color.
///
/// Kept in its own file so the watch app can draw cards the same way.
struct CueCardRun: Codable, Hashable {
    var text: String
    var isCue: Bool
    /// Bold or italic, as written in the script.
    var style: EmphasisStyle = []

    init(text: String, isCue: Bool, style: EmphasisStyle = []) {
        self.text = text
        self.isCue = isCue
        self.style = style
    }

    // A Live Activity started before styles existed carries runs without one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        isCue = try container.decode(Bool.self, forKey: .isCue)
        style = try container.decodeIfPresent(EmphasisStyle.self, forKey: .style) ?? []
    }
}

/// Chinese, Japanese and Korean. Their glyphs fill the whole em box, so lines
/// set as close as Latin ones crowd together.
enum WideScript {
    /// Room between lines in a wide script, where they're set by spacing.
    static func lineSpacing(ofSize size: CGFloat) -> CGFloat {
        size * 0.35
    }

    /// The least a line in a wide script takes up, where it's set by height.
    static func lineHeight(ofSize size: CGFloat) -> CGFloat {
        ceil(size * 1.5)
    }
}

extension String {
    /// Whether any of it is in a wide script.
    var hasWideScript: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic
                || (0x3040...0x30FF).contains(scalar.value) // Hiragana, Katakana
                || (0xAC00...0xD7AF).contains(scalar.value) // Hangul
        }
    }
}

extension Array where Element == CueCardRun {
    var hasWideScript: Bool {
        contains { $0.text.hasWideScript }
    }

    /// The card as one text, cues in their color and set narrower than the
    /// script so they never read as part of it. `cueFont`, if given, sets them
    /// smaller as well.
    func text(primary: Color, cue: Color, cueFont: Font? = nil) -> Text {
        reduce(Text("")) { result, run in
            result + run.styledText(primary: primary, cue: cue, cueFont: cueFont)
        }
    }
}

private extension CueCardRun {
    func styledText(primary: Color, cue: Color, cueFont: Font?) -> Text {
        var text = Text(self.text)
        if isCue {
            if let cueFont { text = text.font(cueFont) }
            return text.fontWidth(.condensed).foregroundColor(cue)
        }
        // Italic first: set after the weight, SwiftUI drops it.
        if style.contains(.italic) { text = text.italic() }
        if style.contains(.bold) { text = text.fontWeight(.heavy) }
        return text.foregroundColor(primary)
    }
}
