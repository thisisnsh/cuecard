import ActivityKit
import SwiftUI
import WidgetKit

private typealias ContentState = CueCardsActivityAttributes.ContentState

/// Cards mode's deck on the Lock Screen and in the Dynamic Island: the card on
/// top, with Back and Next. iOS keeps a sideways swipe on a Live Activity for
/// itself, to clear it, so the swipe the app uses becomes a pair of buttons.
struct CueCardsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CueCardsActivityAttributes.self) { context in
            LockScreenCardView(state: context.state, cueColor: context.attributes.cueColor)
        } dynamicIsland: { context in
            let state = context.state
            // The island is always black, whatever the system appearance.
            let cue = context.attributes.cueColor.color(for: .dark)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Cards", systemImage: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.Dark.textSecondary)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.progress)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.Dark.textSecondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        CardContent(state: state, primary: AppColors.Dark.textPrimary,
                                    secondary: AppColors.Dark.textSecondary, cue: cue, lineLimit: 3)
                        CardButtons(state: state, tint: AppColors.Dark.textPrimary,
                                    fill: AppColors.Dark.textSecondary.opacity(0.25))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(cue)
            } compactTrailing: {
                if state.isFinished {
                    Image(systemName: "checkmark")
                        .foregroundStyle(cue)
                } else {
                    Text("\(state.index + 1)/\(state.count)")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(cue)
                }
            } minimal: {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(cue)
            }
            .keylineTint(cue)
        }
    }
}

/// Held under the Lock Screen's 160-point height for a Live Activity: four
/// lines of card over one row of buttons. The app caps a Lock Screen card at
/// what those four lines fit.
private struct LockScreenCardView: View {
    let state: ContentState
    let cueColor: CueColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardContent(state: state,
                        primary: AppColors.textPrimary(for: colorScheme),
                        secondary: AppColors.textSecondary(for: colorScheme),
                        cue: cueColor.color(for: colorScheme),
                        lineLimit: 4)
            CardButtons(state: state,
                        tint: AppColors.textPrimary(for: colorScheme),
                        fill: AppColors.textSecondary(for: colorScheme).opacity(0.18))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// The card's text, or a word that the deck is done.
private struct CardContent: View {
    let state: ContentState
    let primary: Color
    let secondary: Color
    let cue: Color
    let lineLimit: Int

    var body: some View {
        Group {
            if state.isFinished {
                VStack(alignment: .leading, spacing: 2) {
                    Label("All cards done", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(primary)
                    Text("Go back a card, or start the deck over.")
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                }
            } else {
                state.runs.text(primary: primary, cue: cue)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Back and Next, run in the app without opening it. Once the deck is done,
/// Next becomes Start Over. Buttons in a Live Activity need iOS 17; before
/// that the card shows with just its count.
private struct CardButtons: View {
    let state: ContentState
    let tint: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 12) {
            if #available(iOS 17.0, *) {
                Button(intent: PreviousCueCardIntent()) {
                    label("chevron.left")
                }
                .accessibilityLabel("Previous Card")
                .opacity(state.index > 0 ? 1 : 0.35)

                progress

                if state.isFinished {
                    Button(intent: RestartCueCardsIntent()) {
                        label("arrow.counterclockwise")
                    }
                    .accessibilityLabel("Start Over")
                } else {
                    Button(intent: NextCueCardIntent()) {
                        label("chevron.right")
                    }
                    .accessibilityLabel("Next Card")
                }
            } else {
                progress
            }
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        Text(state.progress)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .frame(minWidth: 64)
    }

    private func label(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(fill, in: Capsule())
    }
}
