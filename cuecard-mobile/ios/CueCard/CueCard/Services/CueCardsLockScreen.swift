import ActivityKit
import Foundation
import UserNotifications

/// One Live Activity for the open deck. Updating never recreates an activity
/// the person dismissed; only explicitly showing the deck starts one.
@MainActor
enum CueCardsLockScreen {
    static func isActive(session: UUID) -> Bool {
        Activity<CueCardsActivityAttributes>.activities.contains {
            $0.attributes.sessionID == session && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    static func show(_ state: CueCardsWidgetState) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        if isActive(session: state.sessionID) {
            await sync(state)
            return true
        }
        await clear()
        do {
            _ = try Activity.request(attributes: CueCardsActivityAttributes(sessionID: state.sessionID),
                                     content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            return true
        } catch {
            return false
        }
    }

    static func sync(_ state: CueCardsWidgetState) async {
        for activity in Activity<CueCardsActivityAttributes>.activities
        where activity.attributes.sessionID == state.sessionID {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func clear() async {
        for activity in Activity<CueCardsActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Remove cards left by a previous app version, without requesting permission.
    static func removeLegacyNotifications() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
            .filter { $0.request.content.categoryIdentifier == "cuecard.card" }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier))
        let pending = await center.pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == "cuecard.card" }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        let categories = await center.notificationCategories().filter { $0.identifier != "cuecard.card" }
        center.setNotificationCategories(categories)
    }
}
