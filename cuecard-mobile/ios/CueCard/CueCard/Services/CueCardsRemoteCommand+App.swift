import Foundation
import WidgetKit

extension CueCardsRemoteCommand {
    @MainActor
    static func move(session: String, currentIndex: Int, targetIndex: Int) async {
        let deck = CueCardsSession.shared
        // A stale widget must never move a new deck or skip an unseen card.
        guard deck.restoreIfNeeded(), deck.sessionID.uuidString == session,
              deck.index == currentIndex else {
            WidgetCenter.shared.reloadTimelines(ofKind: CueCardsWidgetStore.kind)
            return
        }
        deck.show(cardAt: targetIndex)
        await deck.waitForLockScreen()
    }
}
