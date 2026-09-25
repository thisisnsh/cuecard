import ActivityKit
import SwiftUI
import WidgetKit

/// The card on the Lock Screen: deck title, progress, text and buttons.
private struct CueCardsSurface: View {
    let state: CueCardsWidgetState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.title.isEmpty ? "Cards" : state.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let timer = state.timer, !state.isFinished {
                    CueCardsTimer(timer: timer)
                    Text("·")
                }
                Text(state.progress)
                    .monospacedDigit()
                    .contentTransition(.identity)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            CueCardsText(state: state)
                .font(.body.weight(.semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if #available(iOS 17.0, *) {
                CueCardsButtons(state: state)
            } else {
                Text("Open CueCard to turn the card")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@available(iOS 17.0, *)
private struct CueCardsButtons: View {
    let state: CueCardsWidgetState

    var body: some View {
        HStack {
            Button(intent: MoveCueCardIntent(state: state, targetIndex: state.index - 1)) {
                Label("Back", systemImage: "chevron.left")
                    .frame(minHeight: 28)
            }
            .tint(.gray)
            .disabled(state.index == 0)
            Spacer(minLength: 8)
            Button(intent: MoveCueCardIntent(state: state, targetIndex: state.isFinished ? 0 : state.index + 1)) {
                // The hidden labels hold the button at its widest, so it keeps
                // its size, and the system has nothing to animate, as the
                // label changes.
                ZStack {
                    Label("Start Over", systemImage: "arrow.counterclockwise").hidden()
                    Label("Finish", systemImage: "chevron.right").hidden()
                    Label(state.isFinished ? "Start Over" : (state.index == state.count - 1 ? "Finish" : "Next"),
                          systemImage: state.isFinished ? "arrow.counterclockwise" : "chevron.right")
                }
                .frame(minHeight: 28)
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.green)
        .contentTransition(.identity)
    }
}

/// The deck's timer. The system ticks it, counting down to the zero date and
/// up again past it; the app redraws it as its color changes.
private struct CueCardsTimer: View {
    @Environment(\.colorScheme) private var colorScheme
    let timer: TeleprompterTimerState

    var body: some View {
        (Text(timer.isOvertime ? "-" : "") + Text(timer.zeroDate, style: .timer))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 60, alignment: .trailing)
            .foregroundStyle(timer.tint.color(for: colorScheme))
    }
}

/// The card's text, cues in the cue color as the app draws them. It changes
/// between cards at once, with no fade, and ends in an ellipsis when cut off.
private struct CueCardsText: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: CueCardsWidgetState

    var body: some View {
        // Text cut off at a paragraph break gets no ellipsis, so break lines
        // within one paragraph instead.
        state.runs
            .map { CueCardRun(text: $0.text.replacingOccurrences(of: "\n", with: "\u{2028}"), isCue: $0.isCue) }
            .text(primary: AppColors.textPrimary(for: colorScheme),
                  cue: state.cueColor.color(for: colorScheme))
            .truncationMode(.tail)
            .contentTransition(.identity)
    }
}

struct CueCardsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CueCardsActivityAttributes.self) { context in
            CueCardsActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Cards", systemImage: "rectangle.stack")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let timer = context.state.timer, !context.state.isFinished {
                            CueCardsTimer(timer: timer)
                        }
                        Text(context.state.progress)
                            .contentTransition(.identity)
                    }
                    .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        CueCardsText(state: context.state).font(.body).lineLimit(3)
                        if #available(iOS 17.0, *) {
                            CueCardsButtons(state: context.state)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "rectangle.stack")
            } compactTrailing: {
                Text(context.state.isFinished ? "✓" : "\(context.state.index + 1)/\(context.state.count)")
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.identity)
            } minimal: {
                Image(systemName: "rectangle.stack")
            }
        }
    }
}

/// The Lock Screen card, on the system's own background, like a notification.
private struct CueCardsActivityView: View {
    let state: CueCardsWidgetState

    var body: some View {
        CueCardsSurface(state: state)
            .padding(12)
            .frame(height: 160)
    }
}
