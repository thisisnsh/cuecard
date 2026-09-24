import Foundation

extension CueCardsRemoteCommand {
    @MainActor
    static func move(session: String, currentIndex: Int, targetIndex: Int) async {
        let deck = CueCardsSession.shared
        // A stale Live Activity must never move a new deck or skip an unseen card.
        guard deck.restoreIfNeeded(), deck.sessionID.uuidString == session,
              deck.index == currentIndex else { return }
        deck.show(cardAt: targetIndex)
        await deck.waitForLockScreen()
    }
}
