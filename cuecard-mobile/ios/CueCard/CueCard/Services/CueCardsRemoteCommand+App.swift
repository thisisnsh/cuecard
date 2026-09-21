import FirebaseAnalytics
import Foundation

extension CueCardsRemoteCommand {
    /// Moves the open deck. False when there is none.
    @MainActor
    func run() async -> Bool {
        let session = CueCardsSession.shared
        guard session.restoreIfNeeded() else { return false }
        switch self {
        case .next:
            session.next()
            Analytics.logEvent("cards_next", parameters: ["source": "remote"])
        case .previous:
            session.previous()
            Analytics.logEvent("cards_previous", parameters: ["source": "remote"])
        case .restart:
            session.restart()
            Analytics.logEvent("cards_restart", parameters: ["source": "remote"])
        }
        await session.waitForLockScreen()
        return true
    }
}
