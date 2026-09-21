import Foundation

/// The session timer as the Dynamic Island, the Lock Screen and the watch
/// show it. The Live Activity carries it as its content, and the watch gets
/// the same, so all of them read the time the same way.
struct TeleprompterTimerState: Codable, Hashable {
    enum Phase: String, Codable {
        case countingDown, playing, paused
    }

    /// Which color the time is drawn in, matching the in-app timer.
    enum Tint: String, Codable {
        case primary, pink, green, yellow, red
    }

    var phase: Phase
    var tint: Tint
    /// Running, the moment the display reads zero: the end of the start
    /// delay, the end of the timer, or when an untimed session began. The
    /// system ticks the time from it, counting up again once it has passed.
    var zeroDate: Date
    /// Paused, the time to show instead.
    var pausedSeconds: Int
    /// Past the end of a set timer, shown with a minus like the app.
    var isOvertime: Bool

    /// Close enough to skip an update. A running zero date is recomputed
    /// from the clock each tick and drifts by fractions of a millisecond.
    func matches(_ other: TeleprompterTimerState) -> Bool {
        phase == other.phase && tint == other.tint
            && pausedSeconds == other.pausedSeconds && isOvertime == other.isOvertime
            && abs(zeroDate.timeIntervalSince(other.zeroDate)) < 0.5
    }
}

extension TeleprompterTimerState {
    /// Paused time in the same m:ss form the system's running timer uses.
    var pausedDisplay: String {
        let seconds = abs(pausedSeconds)
        let formatted = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        return isOvertime ? "-\(formatted)" : formatted
    }
}
