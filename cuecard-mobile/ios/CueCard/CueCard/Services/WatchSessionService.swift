import Foundation
import WatchConnectivity

/// The iPhone's end of the link to the watch app.
///
/// The watch sends commands, and a message from it launches the app in the
/// background if it has to, the way a Live Activity button does. Each reply,
/// and each change made here, carries the state the watch shows.
@MainActor
final class WatchSessionService: NSObject, ObservableObject {
    static let shared = WatchSessionService()

    /// A watch is paired and has CueCard on it.
    @Published private(set) var isWatchAppInstalled = false

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    private override init() { super.init() }

    /// Start listening. Called at launch, so a command that launched the app
    /// in the background is heard.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// What the watch shows of the iPhone right now.
    var state: WatchPhoneState {
        WatchPhoneState(
            teleprompter: TeleprompterPiPManager.shared.timerState,
            cards: nil,
            cueColor: SettingsService.shared.settings.cueColor,
            sentAt: Date()
        )
    }

    /// Tell the watch something changed: a push if its app is open, and the
    /// application context for when it next opens.
    func stateChanged() {
        guard let session, isWatchAppInstalled else { return }
        let payload = WatchLink.payload(state, key: WatchLink.stateKey)
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - Private

    private func handle(_ command: WatchCommand) async {
        switch command {
        case .refresh:
            break
        case .togglePlayPause:
            _ = TeleprompterRemoteCommand.togglePlayPause.run(source: "watch")
        case .skipBack:
            _ = TeleprompterRemoteCommand.skipBack.run(source: "watch")
        case .showCard, .openDeck:
            break
        }
    }

    private func sessionStateChanged() {
        guard let session else { return }
        isWatchAppInstalled = session.activationState == .activated
            && session.isPaired && session.isWatchAppInstalled
        stateChanged()
    }
}

extension WatchSessionService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.sessionStateChanged() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch. Start again, for that one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sessionStateChanged() }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let command = WatchLink.value(WatchCommand.self, key: WatchLink.commandKey, in: message)
        Task { @MainActor in
            if let command { await self.handle(command) }
            replyHandler(WatchLink.payload(self.state, key: WatchLink.stateKey))
        }
    }

    /// A command queued while the iPhone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = WatchLink.value(WatchCommand.self, key: WatchLink.commandKey, in: userInfo) else { return }
        Task { @MainActor in
            await self.handle(command)
            self.stateChanged()
        }
    }
}
