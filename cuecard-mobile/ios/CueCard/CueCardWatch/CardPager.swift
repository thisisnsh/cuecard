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

    @EnvironmentObject var connector: WatchConnector
    /// Wrist down with Always On: the card stays up, dimmed.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isFinished: Bool { index >= cards.count }
    private var settings: WatchSettings { connector.phone?.settings ?? .default }

    var body: some View {
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
        .toolbar(isLuminanceReduced ? .hidden : .automatic, for: .bottomBar)
        .toolbar {
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
                    Image(systemName: isFinished ? "arrow.counterclockwise" : "chevron.right")
                }
                .primaryHandGesture()
                .accessibilityLabel(isFinished ? "Start Over" : "Next Card")
            }
        }
        .onChange(of: index) {
            if settings.haptics { WKInterfaceDevice.current().play(.click) }
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
