import ActivityKit
import Foundation

/// Mirrors the session timer into a Live Activity for the Dynamic Island while
/// the floating window is up, which then leaves the timer out of its own page.
/// iPhones without the island keep the timer in the window and get no activity.
@MainActor
final class TeleprompterActivityController {
    private typealias ContentState = TeleprompterActivityAttributes.ContentState

    static var hasDynamicIsland: Bool { DeviceModel.hasDynamicIsland }

    private var activity: Activity<TeleprompterActivityAttributes>?
    private var lastState: ContentState?

    /// Called on every playback change, up to each clock tick. The system
    /// ticks the running time itself, so an update is only sent when what it
    /// shows changes: a play or pause, the end of the start delay, a new color.
    func sync(_ playback: TeleprompterPlaybackState, countdownRemaining: Double?, timerDuration: Int) {
        let state = Self.contentState(for: playback, countdownRemaining: countdownRemaining,
                                      timerDuration: timerDuration)
        if let lastState, lastState.matches(state) { return }
        lastState = state

        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One left over from a session the app was quit during.
        endActivities(Activity<TeleprompterActivityAttributes>.activities)
        // Only an app still on screen may start one.
        activity = try? Activity.request(
            attributes: TeleprompterActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func end() {
        guard activity != nil || lastState != nil else { return }
        activity = nil
        lastState = nil
        endActivities(Activity<TeleprompterActivityAttributes>.activities)
    }

    private func endActivities(_ activities: [Activity<TeleprompterActivityAttributes>]) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// The same time and color as the in-app timer. The watch shows it too.
    static func contentState(for playback: TeleprompterPlaybackState,
                             countdownRemaining: Double?,
                             timerDuration: Int) -> TeleprompterTimerState {
        let now = Date()
        if playback.isCountingDown {
            return ContentState(phase: .countingDown, tint: .pink,
                                zeroDate: now.addingTimeInterval(countdownRemaining ?? Double(playback.countdownValue)),
                                pausedSeconds: 0, isOvertime: false)
        }

        let elapsed = playback.elapsedTime
        let remaining = timerDuration - Int(elapsed)
        let isOvertime = timerDuration > 0 && remaining < 0
        let tint: ContentState.Tint
        if timerDuration == 0 {
            tint = .primary
        } else if remaining < 0 {
            tint = .red
        } else if Double(remaining) / Double(timerDuration) <= 0.2 {
            tint = .yellow
        } else {
            tint = .green
        }

        if playback.isPlaying {
            return ContentState(phase: .playing, tint: tint,
                                zeroDate: now.addingTimeInterval(Double(timerDuration) - elapsed),
                                pausedSeconds: 0, isOvertime: isOvertime)
        }
        return ContentState(phase: .paused, tint: tint,
                            zeroDate: Date(timeIntervalSince1970: 0),
                            pausedSeconds: timerDuration > 0 ? remaining : Int(elapsed),
                            isOvertime: isOvertime)
    }
}
