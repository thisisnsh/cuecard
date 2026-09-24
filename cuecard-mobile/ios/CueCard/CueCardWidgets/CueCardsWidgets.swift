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
                Text(state.progress).monospacedDigit()
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
                Label(state.isFinished ? "Start Over" : (state.index == state.count - 1 ? "Finish" : "Next"),
                      systemImage: state.isFinished ? "arrow.counterclockwise" : "chevron.right")
                    .frame(minHeight: 28)
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.green)
    }
}

/// The card's text, cues in the cue color as the app draws them.
private struct CueCardsText: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: CueCardsWidgetState

    var body: some View {
        state.runs.text(primary: AppColors.textPrimary(for: colorScheme),
                        cue: state.cueColor.color(for: colorScheme))
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
                    Text(context.state.progress).font(.caption.monospacedDigit())
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
            } minimal: {
                Image(systemName: "rectangle.stack")
            }
        }
    }
}

/// The Lock Screen card, in the app's background color. It's see-through, so
/// the system's blur shows through as glass over the wallpaper.
private struct CueCardsActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: CueCardsWidgetState

    var body: some View {
        CueCardsSurface(state: state)
            .padding(12)
            .frame(height: 160)
            .activityBackgroundTint(AppColors.background(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.6))
            .activitySystemActionForegroundColor(AppColors.textPrimary(for: colorScheme))
    }
}
