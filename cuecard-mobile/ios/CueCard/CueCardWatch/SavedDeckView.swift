import SwiftUI

/// A deck kept on the watch. With the iPhone in reach it opens there too, and
/// the two move together, Lock Screen and all. Out of reach, it is read here
/// alone, and picks up where it was left next time.
struct SavedDeckView: View {
    let deckID: UUID

    @EnvironmentObject var connector: WatchConnector
    @EnvironmentObject var store: DeckStore
    @State private var index = 0
    /// When this deck was opened here, for its timer while it's read alone.
    @State private var openedAt = Date()

    /// The iPhone's deck, while it is this one.
    private var linked: WatchCardsState? {
        guard let cards = connector.phone?.cards, cards.deckID == deckID else { return nil }
        return cards
    }

    var body: some View {
        if let deck = store.deck(id: deckID) {
            let cards = linked?.cards ?? deck.cards
            CardPager(cards: cards, index: $index, cueColor: connector.phone?.cueColor ?? .default,
                      timerStart: linked?.startedAt ?? openedAt,
                      timerDuration: linked?.timerDuration ?? connector.phone?.cardsTimerDuration ?? 0)
                .navigationTitle(cardProgress(index: index, count: cards.count))
                .onAppear {
                    if let linked {
                        index = linked.index
                    } else {
                        index = min(store.position(of: deckID), cards.count)
                        connector.send(.openDeck(id: deckID, title: deck.title, cards: cards, index: index))
                    }
                }
                .onChange(of: linked) { _, linked in
                    if let linked { index = linked.index }
                }
                .onChange(of: index) { _, index in
                    store.setPosition(index, of: deckID)
                    if let linked, index != linked.index {
                        connector.showCard(index, session: linked.session)
                    }
                }
        } else {
            ContentUnavailableView("Deck Removed", systemImage: "rectangle.stack",
                                   description: Text("It was taken off this watch on your iPhone."))
        }
    }
}
