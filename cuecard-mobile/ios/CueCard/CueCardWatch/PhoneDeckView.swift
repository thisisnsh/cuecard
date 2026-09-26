import SwiftUI

/// The deck open on the iPhone. A move here moves it there, Lock Screen and
/// all, and a move there comes back here.
struct PhoneDeckView: View {
    @EnvironmentObject var connector: WatchConnector
    @State private var index = 0

    var body: some View {
        if let phone = connector.phone, let deck = phone.cards {
            CardPager(cards: deck.cards, index: $index, cueColor: phone.cueColor,
                      timerStart: deck.startedAt, timerDuration: deck.timerDuration ?? 0,
                      timerStyle: deck.timerStyle ?? .default)
                .navigationTitle(cardProgress(index: index, count: deck.cards.count))
                .onAppear { index = deck.index }
                .onChange(of: deck) { _, deck in
                    index = deck.index
                }
                .onChange(of: index) { _, index in
                    guard index != deck.index else { return }
                    connector.showCard(index, session: deck.session)
                }
        } else {
            ContentUnavailableView("Cards Closed", systemImage: "rectangle.stack",
                                   description: Text("Open cards in CueCard on your iPhone."))
        }
    }
}
