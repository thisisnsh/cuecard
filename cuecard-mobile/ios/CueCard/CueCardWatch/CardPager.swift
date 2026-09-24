import SwiftUI
import WatchKit

/// A deck, one card to a page: swipe left for the next card and right to go
/// back, like the iPhone. The Crown scrolls a card too long for the screen,
/// and Next answers a double tap.
struct CardPager: View {
    let cards: [String]
    /// The card showing. Equal to the number of cards on the page after the
    /// last, once every one has been gone through.
    @Binding var index: Int
    let cueColor: CueColor
    /// When the deck's timer started, if it has one showing.
    var timerStart: Date?
    /// The timer's length in seconds. Zero counts up.
    var timerDuration = 0

    @EnvironmentObject var connector: WatchConnector
    /// Wrist down with Always On: the card stays up, dimmed.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isFinished: Bool { index >= cards.count }
    private var settings: WatchSettings { connector.phone?.settings ?? .default }
    private var nextLabel: String {
        if isFinished { return "Again" }
        return index == cards.count - 1 ? "Finish" : "Next"
    }

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(min(index + 1, cards.count)),
                         total: Double(max(cards.count, 1)))
                .tint(isLuminanceReduced ? .secondary : AppColors.Dark.green)
                .padding(.horizontal, 6)
                .accessibilityHidden(true)

            TabView(selection: $index) {
                ForEach(cards.indices, id: \.self) { cardIndex in
                    CardPage(runs: CueCards.runs(for: cards[cardIndex]), cueColor: cueColor,
                             textSize: settings.cardTextSize.pointSize)
                        .tag(cardIndex)
                }
                DonePage()
                    .tag(cards.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .toolbar(isLuminanceReduced ? .hidden : .automatic, for: .bottomBar)
        .toolbar {
            if let timerStart, !isFinished {
                ToolbarItem(placement: .topBarTrailing) {
                    CardsTimerText(start: timerStart, duration: timerDuration)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    index = max(index - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous Card")

                Spacer()

                Button {
                    index = isFinished ? 0 : index + 1
                } label: {
                    Label(nextLabel, systemImage: isFinished ? "arrow.counterclockwise" :
                            (index == cards.count - 1 ? "checkmark" : "chevron.right"))
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold))
                }
                .tint(AppColors.Dark.green)
                .primaryHandGesture()
                .accessibilityLabel(isFinished ? "Start Over" : (index == cards.count - 1 ? "Finish Deck" : "Next Card"))
            }
        }
        .onChange(of: index) {
            if settings.haptics { WKInterfaceDevice.current().play(.click) }
        }
    }
}

/// A deck's timer, recolored each second as it nears and runs past the end.
struct CardsTimerText: View {
    let start: Date
    let duration: Int

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let state = TeleprompterTimerState.running(since: start, duration: duration, at: context.date)
            TimerText(state: state)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(state.tint.color)
        }
    }
}

/// "2 of 5", or "Done" once there's nothing left.
func cardProgress(index: Int, count: Int) -> String {
    index >= count ? "Done" : "\(index + 1) of \(count)"
}

/// One card, cues in their color.
private struct CardPage: View {
    let runs: [CueCardRun]
    let cueColor: CueColor
    let textSize: Double

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ScrollView {
            runs.text(primary: AppColors.Dark.textPrimary, cue: cueColor.color(for: .dark))
                .opacity(isLuminanceReduced ? 0.6 : 1)
                .font(.system(size: textSize, weight: .semibold))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                // Clear of the Back and Next buttons at the bottom.
                .padding(.bottom, 36)
        }
    }
}

private struct DonePage: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.Dark.green)
            Text("All cards done")
                .font(.headline)
            Text("Go back or read them again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
