import FirebaseAnalytics
import Foundation
import UserNotifications

/// The open deck on the Lock Screen, as one quiet notification per card. The
/// card on top is posted last, so it sits above the rest: clearing it with a
/// swipe shows the next one, the way the in-app deck is swiped through.
///
/// A notification can't be moved once posted, so a card brought back is
/// posted again, on top.
@MainActor
enum CueCardsLockScreen {
    static let categoryID = "cuecard.card"
    static let backActionID = "cuecard.card.back"
    static let restartActionID = "cuecard.card.restart"

    static let sessionKey = "session"
    static let indexKey = "index"

    /// A notification holds a few lines on the Lock Screen; this is well past
    /// what they fit.
    private static let maxLength = 300

    private static var center: UNUserNotificationCenter { .current() }

    /// Back and Start Over, from a long press on a card. Clearing a card is
    /// reported too, so the deck can follow.
    static func registerCategory() {
        let back = UNNotificationAction(identifier: backActionID, title: "Back",
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.backward"))
        let restart = UNNotificationAction(identifier: restartActionID, title: "Start Over",
                                           icon: UNNotificationActionIcon(systemImageName: "arrow.counterclockwise"))
        let category = UNNotificationCategory(identifier: categoryID, actions: [back, restart],
                                              intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    /// Asks the first time. False once notifications are turned off.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    /// Show `cards` from `index` on, the card at `index` on top. Cards already
    /// up stay, cards put away come down, and cards brought back go up again.
    static func sync(cards: [String], title: String, index: Int, session: UUID) async {
        let delivered = await center.deliveredNotifications()
            .filter { $0.request.content.categoryIdentifier == categoryID }

        var stale: [String] = []
        var shown: [Int] = []
        for notification in delivered {
            let info = notification.request.content.userInfo
            if info[sessionKey] as? String == session.uuidString, let cardIndex = info[indexKey] as? Int,
               cardIndex >= index, cardIndex < cards.count {
                shown.append(cardIndex)
            } else {
                stale.append(notification.request.identifier)
            }
        }
        center.removeDeliveredNotifications(withIdentifiers: stale)

        // Everything above the top card still up, bottom first. A card
        // cleared from under it stays cleared.
        let lowestShown = shown.min() ?? cards.count
        guard index < lowestShown else { return }
        for cardIndex in (index..<lowestShown).reversed() {
            let request = UNNotificationRequest(
                identifier: "\(categoryID).\(session.uuidString).\(cardIndex)",
                content: content(for: cards[cardIndex], at: cardIndex, of: cards.count,
                                 title: title, session: session),
                trigger: nil
            )
            // One at a time, so each lands after, and above, the one before.
            try? await center.add(request)
        }
    }

    /// A card cleared, or Back or Start Over pressed on one. Runs in the app,
    /// launched in the background if it was quit.
    static func handle(_ response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard response.notification.request.content.categoryIdentifier == categoryID,
              let session = info[sessionKey] as? String,
              let cardIndex = info[indexKey] as? Int else { return }
        let deck = CueCardsSession.shared
        guard deck.restoreIfNeeded(), deck.sessionID.uuidString == session else { return }

        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            // Only the card on top moves the deck. One cleared from under it
            // is just gone.
            guard cardIndex == deck.index else { return }
            deck.next()
            Analytics.logEvent("cards_next", parameters: ["source": "lock_screen"])
        case backActionID:
            deck.previous()
            Analytics.logEvent("cards_previous", parameters: ["source": "lock_screen"])
        case restartActionID:
            deck.restart()
            Analytics.logEvent("cards_restart", parameters: ["source": "lock_screen"])
        default:
            break
        }
        // An action, or a tap, takes its card down with it. Put it back up if
        // the deck still has it.
        if response.actionIdentifier != UNNotificationDismissActionIdentifier {
            deck.refreshLockScreen()
        }
        await deck.waitForLockScreen()
    }

    /// Take every card down.
    static func clear() async {
        let ids = await center.deliveredNotifications()
            .filter { $0.request.content.categoryIdentifier == categoryID }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func content(for card: String, at index: Int, of count: Int,
                                title: String, session: UUID) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "\(index + 1) of \(count)" : "\(index + 1) of \(count) · \(title)"
        content.body = CueCards.runs(for: card, maxLength: maxLength).map(\.text).joined()
        content.categoryIdentifier = categoryID
        // Its own thread, so iOS doesn't fold the deck into one stack that a
        // single swipe would clear.
        content.threadIdentifier = "\(categoryID).\(session.uuidString).\(index)"
        content.interruptionLevel = .passive
        content.userInfo = [sessionKey: session.uuidString, indexKey: index]
        return content
    }
}
