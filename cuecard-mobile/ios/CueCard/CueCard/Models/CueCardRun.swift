import SwiftUI

/// A stretch of a card: spoken text, or a cue drawn in the cue color.
///
/// Kept apart from the Live Activity's types, which need ActivityKit, so the
/// watch app can draw cards the same way.
struct CueCardRun: Codable, Hashable {
    var text: String
    var isCue: Bool
}

extension Array where Element == CueCardRun {
    /// The card as one text, cues in their color.
    func text(primary: Color, cue: Color) -> Text {
        reduce(Text("")) { result, run in
            result + Text(run.text).foregroundColor(run.isCue ? cue : primary)
        }
    }
}
