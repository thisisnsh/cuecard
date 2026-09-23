import ActivityKit
import SwiftUI
import WidgetKit

private typealias ContentState = TeleprompterActivityAttributes.ContentState

/// The session timer in the Dynamic Island and on the Lock Screen.
struct TeleprompterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeleprompterActivityAttributes.self) { context in
            LockScreenTimerView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            // The island is always black, whatever the system appearance.
            let tint = state.tint.color(for: .dark)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CueCard")
                            .font(.caption)
                            .foregroundStyle(AppColors.Dark.textSecondary)
                        Label(state.statusTitle, systemImage: state.symbolName)
                            .font(.headline)
                            .foregroundStyle(tint)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PlaybackButtons(state: state, tint: tint,
                                    fill: AppColors.Dark.textSecondary.opacity(0.25))
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(tint)
            } compactTrailing: {
                // A running timer's text takes all the width it is offered.
                TimerText(state: state)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.7)
                    .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private struct LockScreenTimerView: View {
    let state: ContentState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CueCard")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    Label(state.statusTitle, systemImage: state.symbolName)
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                }
                Spacer()
                TimerText(state: state)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.tint.color(for: colorScheme))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
            PlaybackButtons(state: state,
                            tint: AppColors.textPrimary(for: colorScheme),
                            fill: AppColors.textSecondary(for: colorScheme).opacity(0.18))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// Back 10 seconds and play/pause, run in the app without opening it. Buttons
/// in a Live Activity need iOS 17; before that the timer shows alone.
private struct PlaybackButtons: View {
    let state: ContentState
    let tint: Color
    let fill: Color

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 12) {
                Button(intent: SkipBackTeleprompterIntent()) {
                    label("gobackward.\(TeleprompterRemoteCommand.skipBackSeconds)")
                }
                .accessibilityLabel("Back \(TeleprompterRemoteCommand.skipBackSeconds) Seconds")

                Button(intent: ToggleTeleprompterPlaybackIntent()) {
                    label(state.phase == .paused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(state.phase == .paused ? "Play" : "Pause")
            }
            .buttonStyle(.plain)
        }
    }

    private func label(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(fill, in: Capsule())
    }
}

/// Running, the system ticks the time from the zero date, so it stays current
/// without the app sending an update each second.
private struct TimerText: View {
    let state: ContentState

    var body: some View {
        switch state.phase {
        case .paused:
            Text(state.pausedDisplay)
        case .countingDown, .playing:
            Text(state.isOvertime ? "-" : "") + Text(state.zeroDate, style: .timer)
        }
    }
}

private extension ContentState {
    var symbolName: String {
        switch phase {
        case .countingDown: return "timer"
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        }
    }

    var statusTitle: String {
        switch phase {
        case .countingDown: return "Starting"
        case .playing: return isOvertime ? "Overtime" : "Reading"
        case .paused: return "Paused"
        }
    }
}

private extension ContentState.Tint {
    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary: return AppColors.textPrimary(for: colorScheme)
        case .pink: return AppColors.pink(for: colorScheme)
        case .green: return AppColors.green(for: colorScheme)
        case .yellow: return AppColors.yellow(for: colorScheme)
        case .red: return AppColors.red(for: colorScheme)
        }
    }
}
