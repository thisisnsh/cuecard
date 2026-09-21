import ActivityKit
import Foundation

/// The session timer as the Dynamic Island and Lock Screen show it. Shared by
/// the app, which starts and updates the activity, and the widget extension,
/// which draws it. The timer itself lives apart, for the watch to share.
struct TeleprompterActivityAttributes: ActivityAttributes {
    typealias ContentState = TeleprompterTimerState
}
