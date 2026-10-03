import Foundation
import Testing
@testable import CueCard

/// What the iPhone, the watch and the Lock Screen send each other. Both ends
/// ship separately, so these shapes have to keep decoding.
@Suite("Watch and widget messages")
struct WatchAndWidgetTests {

    @Test(arguments: [
        WatchCommand.togglePlayPause,
        .skipBack,
        .refresh,
        .showCard(session: UUID(), index: 3),
        .openDeck(id: UUID(), title: "Deck", cards: ["One", "Two [cue smile]"], index: 1),
    ])
    func commandsSurviveThePayload(_ command: WatchCommand) {
        let payload = WatchLink.payload(command, key: WatchLink.commandKey)
        #expect(WatchLink.value(WatchCommand.self, key: WatchLink.commandKey, in: payload) == command)
    }

    @Test func phoneStateSurvivesThePayload() {
        let state = WatchPhoneState(
            teleprompter: .running(since: Date(timeIntervalSince1970: 100), duration: 60, style: .default,
                                   at: Date(timeIntervalSince1970: 110)),
            cards: WatchCardsState(session: UUID(), deckID: UUID(), title: "Talk", cards: ["A", "B"], index: 1,
                                   startedAt: Date(timeIntervalSince1970: 100), timerDuration: 90,
                                   timerStyle: .default),
            cueColor: .green,
            settings: .default,
            cardsTimerDuration: 120,
            cardsTimerStyle: .default,
            sentAt: Date(timeIntervalSince1970: 200)
        )
        let payload = WatchLink.payload(state, key: WatchLink.stateKey)
        #expect(WatchLink.value(WatchPhoneState.self, key: WatchLink.stateKey, in: payload) == state)
    }

    @Test func missingOrWrongPayloadIsNil() {
        let payload = WatchLink.payload(WatchCommand.refresh, key: WatchLink.commandKey)
        #expect(WatchLink.value(WatchCommand.self, key: WatchLink.stateKey, in: payload) == nil)
        #expect(WatchLink.value(WatchCommand.self, key: WatchLink.commandKey, in: [WatchLink.commandKey: "text"]) == nil)
        #expect(WatchLink.value(WatchPhoneState.self, key: WatchLink.commandKey, in: payload) == nil)
    }

    @Test func messageKeysStayTheSame() {
        #expect(WatchLink.commandKey == "command")
        #expect(WatchLink.stateKey == "state")
        #expect(WatchLink.fileKindKey == "kind")
        #expect(WatchLink.decksFileKind == "decks")
    }

    @Test func watchTextSizes() {
        #expect(WatchSettings.default == WatchSettings(cardTextSize: .medium, haptics: true))
        #expect(WatchCardTextSize.allCases.map(\.pointSize) == [16, 19, 23])
    }

    // MARK: - Lock Screen

    private func widgetState(index: Int, count: Int) -> CueCardsWidgetState {
        CueCardsWidgetState(sessionID: UUID(), title: "Talk", runs: CueCards.runs(for: "Hi [cue smile]"),
                            cueColor: .pink, index: index, count: count, timer: nil)
    }

    @Test func widgetShowsWhereTheDeckIs() {
        #expect(widgetState(index: 0, count: 3).progress == "1 of 3")
        #expect(widgetState(index: 2, count: 3).progress == "3 of 3")
        #expect(!widgetState(index: 2, count: 3).isFinished)
    }

    @Test func widgetShowsDoneAfterTheLastCard() {
        let state = widgetState(index: 3, count: 3)
        #expect(state.isFinished)
        #expect(state.progress == "Done")
    }

    @Test func widgetStateSurvivesEncoding() throws {
        let state = widgetState(index: 1, count: 4)
        let decoded = try JSONDecoder().decode(CueCardsWidgetState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
