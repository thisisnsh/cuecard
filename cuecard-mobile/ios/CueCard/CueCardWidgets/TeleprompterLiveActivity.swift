import ActivityKit
import SwiftUI
import WidgetKit

private typealias ContentState = TeleprompterActivityAttributes.ContentState

/// One glanceable timer and the same two controls on both system surfaces.
struct TeleprompterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeleprompterActivityAttributes.self) { context in
            LockScreenTimerView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(white: 0.06))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = context.isStale ? AppColors.Dark.textSecondary : state.tint.color
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Teleprompter", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("CueCard")
                        .font(.caption)
                        .foregroundStyle(AppColors.Dark.textSecondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerAndControls(state: state, isStale: context.isStale)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "stop.fill" : state.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityLabel(context.isStale ? "Teleprompter unavailable" : state.timerTitle)
            } compactTrailing: {
                TimerText(state: state, isStale: context.isStale)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: state.needsHours ? 66 : 52, alignment: .trailing)
            } minimal: {
                Image(systemName: context.isStale ? "stop.fill" : state.symbolName)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private struct LockScreenTimerView: View {
    let state: ContentState
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Teleprompter", systemImage: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("CueCard")
                    .font(.caption)
                    .foregroundStyle(AppColors.Dark.textSecondary)
            }
            TimerAndControls(state: state, isStale: isStale)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .environment(\.colorScheme, .dark)
    }
}

private struct TimerAndControls: View {
    let state: ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                TimerText(state: state, isStale: isStale)
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isStale ? AppColors.Dark.textSecondary : state.tint.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isStale ? "Open CueCard to continue" : state.timerTitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.Dark.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !isStale {
                PlaybackButtons(state: state)
            }
        }
    }
}

/// The primary control is distinct from the smaller script rewind. Both have
/// at least a 44-point hit target; rewinding never changes the session timer.
private struct PlaybackButtons: View {
    let state: ContentState

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 10) {
                Button(intent: SkipBackTeleprompterIntent()) {
                    Image(systemName: "gobackward.\(TeleprompterRemoteCommand.skipBackSeconds)")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Move script back \(TeleprompterRemoteCommand.skipBackSeconds) seconds")
                .disabled(state.phase == .countingDown)
                .opacity(state.phase == .countingDown ? 0.4 : 1)

                Button(intent: ToggleTeleprompterPlaybackIntent()) {
                    Image(systemName: state.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(state.phase == .paused ? "Resume teleprompter" : "Pause teleprompter")
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}

/// ActivityKit advances the clock. A stale activity must not keep claiming
/// playback is running after the app process has gone away.
private struct TimerText: View {
    let state: ContentState
    var isStale = false

    var body: some View {
        if isStale {
            Text("—:—")
        } else {
            switch state.phase {
            case .paused:
                Text(state.pausedDisplay)
            case .countingDown, .playing:
                Text(state.isOvertime ? "−" : "") + Text(state.zeroDate, style: .timer)
            }
        }
    }
}

private extension ContentState {
    var symbolName: String {
        switch phase {
        case .countingDown: return "timer"
        case .playing: return "text.alignleft"
        case .paused: return "pause.fill"
        }
    }

    var timerTitle: String {
        if phase == .countingDown { return "Starting in" }
        let title = isOvertime ? "Overtime" : tint == .primary ? "Elapsed time" : "Time remaining"
        return phase == .paused ? "Paused · \(title.lowercased())" : title
    }

    var needsHours: Bool {
        phase == .paused ? abs(pausedSeconds) >= 3600 : abs(zeroDate.timeIntervalSinceNow) >= 3600
    }
}

private extension ContentState.Tint {
    var color: Color {
        switch self {
        case .primary: return .white
        case .pink: return AppColors.Dark.pink
        case .green: return AppColors.Dark.green
        case .yellow: return AppColors.Dark.yellow
        case .red: return AppColors.Dark.red
        }
    }
}

#if DEBUG
struct TeleprompterActivityLayoutPreviews: PreviewProvider {
    static var previews: some View {
        ForEach([ContentState.Phase.playing, .paused, .countingDown], id: \.self) { phase in
            LockScreenTimerView(state: ContentState(
                phase: phase, tint: phase == .countingDown ? .pink : .green,
                zeroDate: Date().addingTimeInterval(142), pausedSeconds: 142, isOvertime: false
            ))
            .background(Color(white: 0.06))
            .previewLayout(.fixed(width: 350, height: 136))
            .previewDisplayName(phase.rawValue)
        }
    }
}
#endif
