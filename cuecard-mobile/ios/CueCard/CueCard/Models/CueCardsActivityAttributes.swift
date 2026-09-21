import ActivityKit
import SwiftUI

/// A stretch of a card: spoken text, or a cue drawn in the cue color.
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

/// The card on top of the deck as the Lock Screen and Dynamic Island show it.
/// Shared by the app, which starts and updates the activity, and the widget
/// extension, which draws it.
///
/// Only the card showing travels, not the deck: an activity's data is held to
/// 4 KB, and the Back and Next buttons run in the app, which has the rest.
struct CueCardsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The card on top. Empty once the whole deck has been gone through.
        var runs: [CueCardRun]
        /// Zero-based. Equal to `count` once the deck has been gone through.
        var index: Int
        var count: Int

        var isFinished: Bool { index >= count }

        /// "2 of 5", or "Done" once there's nothing left.
        var progress: String {
            isFinished ? "Done" : "\(index + 1) of \(count)"
        }
    }

    /// The color cues are drawn in, from Settings when the deck opened.
    var cueColor: CueColor
}
