import SwiftUI
import WatchKit

/// Play, pause and back 10 seconds for the script open in the iPhone's
/// teleprompter, with its timer.
struct TeleprompterRemoteView: View {
    @EnvironmentObject var connector: WatchConnector

    var body: some View {
        Group {
            if let timer = connector.phone?.teleprompter {
                controls(timer)
            } else {
                ContentUnavailableView("Script Closed", systemImage: "play.slash",
                                       description: Text("Open a script in CueCard on your iPhone."))
            }
        }
        .navigationTitle("Teleprompter")
    }

    private func controls(_ timer: TeleprompterTimerState) -> some View {
        let tint = timer.tint.color

        return VStack(spacing: 10) {
            Label(timer.statusTitle, systemImage: timer.symbolName)
                .font(.footnote)
                .foregroundStyle(.secondary)

            TimerText(state: timer)
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 12) {
                // The iPhone's TeleprompterRemoteCommand.skipBackSeconds.
                Button {
                    send(.skipBack)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Back 10 Seconds")

                Button {
                    send(.togglePlayPause)
                } label: {
                    Image(systemName: timer.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(tint)
                .primaryHandGesture()
                .accessibilityLabel(timer.phase == .paused ? "Play" : "Pause")
            }
        }
        .padding(.horizontal, 4)
    }

    private func send(_ command: WatchCommand) {
        WKInterfaceDevice.current().play(.click)
        connector.send(command) {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

/// Running, the system ticks the time from the zero date, the same way the
/// Dynamic Island does.
struct TimerText: View {
    let state: TeleprompterTimerState

    var body: some View {
        switch state.phase {
        case .paused:
            Text(state.pausedDisplay)
        case .countingDown, .playing:
            Text(state.isOvertime ? "-" : "") + Text(state.zeroDate, style: .timer)
        }
    }
}

extension TeleprompterTimerState {
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

extension TeleprompterTimerState.Tint {
    /// The watch is always dark.
    var color: Color {
        switch self {
        case .primary: return AppColors.Dark.textPrimary
        case .pink: return AppColors.Dark.pink
        case .green: return AppColors.Dark.green
        case .yellow: return AppColors.Dark.yellow
        case .red: return AppColors.Dark.red
        }
    }
}

extension View {
    /// A double tap of the fingers presses this, where the watch supports it.
    @ViewBuilder
    func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
