import Foundation
import WatchConnectivity

/// The watch's end of the link to the iPhone app: what is open there, and a
/// way to send it commands.
@MainActor
final class WatchConnector: NSObject, ObservableObject {
    static let shared = WatchConnector()

    /// The latest the iPhone has said. Nil until it has said anything.
    @Published private(set) var phone: WatchPhoneState?
    /// The iPhone app can be messaged right now.
    @Published private(set) var isReachable = false

    private let session = WCSession.default
    /// When the watch last moved the iPhone's deck itself.
    private var movedAt: Date?

    /// How long a move made here outranks the iPhone's word on where the deck
    /// is: long enough for the replies to a quick run of swipes to come back.
    private static let moveGrace: TimeInterval = 1.5

    private override init() { super.init() }

    func activate() {
        session.delegate = self
        session.activate()
    }

    /// Ask the iPhone to do something. Its reply carries the state after it.
    /// `onFailure` runs when the iPhone can't be reached.
    func send(_ command: WatchCommand, onFailure: (() -> Void)? = nil) {
        guard session.activationState == .activated, session.isReachable else {
            onFailure?()
            return
        }
        session.sendMessage(
            WatchLink.payload(command, key: WatchLink.commandKey),
            replyHandler: { [weak self] reply in
                guard let state = WatchLink.value(WatchPhoneState.self, key: WatchLink.stateKey, in: reply) else { return }
                Task { @MainActor in self?.apply(state) }
            },
            errorHandler: { _ in
                Task { @MainActor in onFailure?() }
            }
        )
    }

    /// Move the iPhone's deck to a card. Shown here at once; out of reach,
    /// the move waits to be delivered, and only the latest one is kept.
    func showCard(_ index: Int, session deckSession: UUID) {
        if phone?.cards?.session == deckSession {
            phone?.cards?.index = index
        }
        movedAt = Date()

        let command = WatchCommand.showCard(session: deckSession, index: index)
        cancelQueuedCommands()
        send(command) { [weak self] in
            guard let self else { return }
            self.cancelQueuedCommands()
            self.session.transferUserInfo(WatchLink.payload(command, key: WatchLink.commandKey))
        }
    }

    // MARK: - Private

    private func apply(_ state: WatchPhoneState) {
        if let phone, phone.sentAt > state.sentAt { return }
        var state = state
        // The reply to an earlier swipe would put the deck back a card.
        if let movedAt, Date().timeIntervalSince(movedAt) < Self.moveGrace,
           let local = phone?.cards, local.session == state.cards?.session {
            state.cards?.index = local.index
        }
        phone = state
    }

    private func cancelQueuedCommands() {
        session.outstandingUserInfoTransfers.forEach { $0.cancel() }
    }

    private func reachabilityChanged() {
        isReachable = session.isReachable
        // What the application context says may be stale: the iPhone app may
        // have quit since. Ask for how things are now.
        if isReachable { send(.refresh) }
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            if let state = WatchLink.value(WatchPhoneState.self, key: WatchLink.stateKey, in: context) {
                self.apply(state)
            }
            self.reachabilityChanged()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachabilityChanged() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let state = WatchLink.value(WatchPhoneState.self, key: WatchLink.stateKey, in: applicationContext) else { return }
        Task { @MainActor in self.apply(state) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let state = WatchLink.value(WatchPhoneState.self, key: WatchLink.stateKey, in: message) else { return }
        Task { @MainActor in self.apply(state) }
    }
}
