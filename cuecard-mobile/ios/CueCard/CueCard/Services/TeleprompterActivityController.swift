import ActivityKit
import Foundation
import UIKit
import os

/// Mirrors a started teleprompter session into the island and Lock Screen.
@MainActor
final class TeleprompterActivityController {
    private typealias ContentState = TeleprompterActivityAttributes.ContentState

    static var hasDynamicIsland: Bool { DeviceModel.hasDynamicIsland }

    private var activity: Activity<TeleprompterActivityAttributes>?
    private var lastState: ContentState?
    private var pendingUpdate: Task<Void, Never>?
    private var stateObservation: Task<Void, Never>?
    private var wasDismissed = false
    private var retryAfter = Date.distantPast
    private var lastUpdate = Date.distantPast
    private var heartbeat: Timer?
    private let logger = Logger(subsystem: "com.thisisnsh.cuecard.ios", category: "LiveActivity")

    var isActive: Bool {
        guard let activity else { return false }
        return activity.activityState == .active || activity.activityState == .stale
    }

    /// Called on every playback change, up to each clock tick. The system
    /// ticks the running time itself, so an update is only sent when what it
    /// shows changes: a play or pause, the end of the start delay, a new color.
    func sync(_ playback: TeleprompterPlaybackState, countdownRemaining: Double?, timerDuration: Int) {
        let state = Self.contentState(for: playback, countdownRemaining: countdownRemaining,
                                      timerDuration: timerDuration)
        if let activity {
            guard isActive else { return }
            if let lastState, lastState.matches(state), Date().timeIntervalSince(lastUpdate) < 30 { return }
            lastState = state
            lastUpdate = Date()
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
            let previous = pendingUpdate
            pendingUpdate = Task {
                await previous?.value
                await activity.update(content)
            }
            return
        }
        guard !wasDismissed, Date() >= retryAfter,
              UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One left over from a session the app was quit during.
        endActivities(Activity<TeleprompterActivityAttributes>.activities)
        // Only an app still on screen may start one.
        do {
            let activity = try Activity.request(
                attributes: TeleprompterActivityAttributes(),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
            )
            self.activity = activity
            lastState = state
            lastUpdate = Date()
            // Paused readers have no playback clock. Renew freshness there too,
            // so an intentionally paused session never looks disconnected.
            heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive, let state = self.lastState,
                          let activity = self.activity else { return }
                    let previous = self.pendingUpdate
                    self.pendingUpdate = Task {
                        await previous?.value
                        await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
                    }
                    self.lastUpdate = Date()
                }
            }
            stateObservation = Task { [weak self] in
                for await state in activity.activityStateUpdates {
                    guard let self, self.activity?.id == activity.id else { return }
                    if state == .dismissed || state == .ended {
                        self.activity = nil
                        self.lastState = nil
                        self.wasDismissed = true
                        self.heartbeat?.invalidate()
                        self.heartbeat = nil
                        return
                    }
                }
            }
        } catch {
            // A request may fail during a foreground transition. Don't cache
            // the state as delivered, or hammer ActivityKit on every frame.
            retryAfter = Date().addingTimeInterval(5)
            logger.error("Could not start teleprompter activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func end() {
        heartbeat?.invalidate()
        heartbeat = nil
        stateObservation?.cancel()
        stateObservation = nil
        activity = nil
        lastState = nil
        wasDismissed = false
        retryAfter = .distantPast
        endActivities(Activity<TeleprompterActivityAttributes>.activities)
    }

    func waitForUpdates() async {
        await pendingUpdate?.value
    }

    private func endActivities(_ activities: [Activity<TeleprompterActivityAttributes>]) {
        guard !activities.isEmpty else { return }
        // Give an end requested during backgrounding time to reach ActivityKit.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "End teleprompter activity")
        let previous = pendingUpdate
        pendingUpdate = Task {
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            await previous?.value
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
