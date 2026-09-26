import Foundation

/// The session timer as the watch shows it, sent over from the iPhone.
struct TeleprompterTimerState: Codable, Hashable {
    enum Phase: String, Codable {
        case countingDown, playing, paused
    }

    /// Which color the time is drawn in, matching the in-app timer.
    enum Tint: String, Codable {
        case primary, pink, green, yellow, red, blue, purple

        init(_ color: CueColor) {
            switch color {
            case .pink: self = .pink
            case .yellow: self = .yellow
            case .green: self = .green
            case .blue: self = .blue
            case .purple: self = .purple
            case .red: self = .red
            }
        }
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
    /// A timer that has been running since `start` without a pause, as a deck
    /// of cards has: counting down from `duration`, or up when it is zero.
    /// Colored by `style`, like the teleprompter's.
    static func running(since start: Date, duration: Int, style: TimerStyle,
                        at now: Date = Date()) -> TeleprompterTimerState {
        let remaining = duration - Int(now.timeIntervalSince(start))
        return TeleprompterTimerState(phase: .playing, tint: style.tint(remaining: remaining, duration: duration),
                                      zeroDate: start.addingTimeInterval(Double(duration)),
                                      pausedSeconds: 0, isOvertime: duration > 0 && remaining < 0)
    }

    /// Paused time in the same m:ss form the system's running timer uses.
    var pausedDisplay: String {
        let seconds = abs(pausedSeconds)
        let formatted = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        return isOvertime ? "-\(formatted)" : formatted
    }
}

/// How a set timer is colored: one color while there's time, another from
/// `warningSeconds` left, and a third from zero on into overtime. With no
/// timer set it counts up in a color of its own, and the teleprompter's start
/// delay counts down in another.
struct TimerStyle: Codable, Hashable {
    /// Time left when the warning color starts. Zero skips the warning.
    var warningSeconds: Int
    var normalColor: CueColor
    var warningColor: CueColor
    var overtimeColor: CueColor
    var countdownColor: CueColor
    /// With no timer set.
    var countUpColor: CueColor

    static let `default` = TimerStyle(warningSeconds: 10, normalColor: .green,
                                      warningColor: .yellow, overtimeColor: .red,
                                      countdownColor: .pink, countUpColor: .green)

    /// The color for `remaining` seconds left of `duration`. With no timer
    /// set, the time counts up instead.
    func tint(remaining: Int, duration: Int) -> TeleprompterTimerState.Tint {
        guard duration > 0 else { return .init(countUpColor) }
        if remaining <= 0 { return .init(overtimeColor) }
        if remaining <= warningSeconds { return .init(warningColor) }
        return .init(normalColor)
    }

    /// Seconds into a `duration` timer at which its color changes.
    func colorChanges(duration: Int) -> [Int] {
        guard duration > 0 else { return [] }
        let warning = duration - warningSeconds
        return (warningSeconds > 0 && warning > 0 ? [warning] : []) + [duration]
    }
}

#if os(iOS)
import SwiftUI
import UIKit

extension TeleprompterTimerState.Tint {
    /// The app's color for this tint.
    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary: return AppColors.textPrimary(for: colorScheme)
        case .pink: return AppColors.pink(for: colorScheme)
        case .green: return AppColors.green(for: colorScheme)
        case .yellow: return AppColors.yellow(for: colorScheme)
        case .red: return AppColors.red(for: colorScheme)
        case .blue: return AppColors.blue(for: colorScheme)
        case .purple: return AppColors.purple(for: colorScheme)
        }
    }

    func uiColor(isDarkMode: Bool) -> UIColor {
        switch self {
        case .primary: return isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        case .pink: return CueColor.pink.uiColor(isDarkMode: isDarkMode)
        case .green: return CueColor.green.uiColor(isDarkMode: isDarkMode)
        case .yellow: return CueColor.yellow.uiColor(isDarkMode: isDarkMode)
        case .red: return CueColor.red.uiColor(isDarkMode: isDarkMode)
        case .blue: return CueColor.blue.uiColor(isDarkMode: isDarkMode)
        case .purple: return CueColor.purple.uiColor(isDarkMode: isDarkMode)
        }
    }
}
#endif
