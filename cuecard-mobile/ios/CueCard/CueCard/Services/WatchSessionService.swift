import Combine
import FirebaseAnalytics
import Foundation
import WatchConnectivity

/// The iPhone's end of the link to the watch app.
///
/// The watch sends commands, and a message from it launches the app in the
/// background if it has to, the way clearing a Lock Screen card does. Each reply,
/// and each change made here, carries the state the watch shows.
@MainActor
final class WatchSessionService: NSObject, ObservableObject {
    static let shared = WatchSessionService()

    /// A watch is paired with this iPhone, whether or not CueCard is on it.
    @Published private(set) var isPaired = false
    /// A watch is paired and has CueCard on it.
    @Published private(set) var isWatchAppInstalled = false

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var notesSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    /// The decks last sent, so an unchanged set isn't sent again.
    private var sentDecks: Data?

    private override init() { super.init() }

    /// Start listening. Called at launch, so a command that launched the app
    /// in the background is heard.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()

        // A note edited, renamed, deleted, or put on or off the watch.
        let settings = SettingsService.shared
        notesSubscription = settings.$savedNotes.map { _ in () }
            .merge(with: settings.$watchNoteIDs.map { _ in () })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.sendDecks() }

        // The cue color or a watch setting changed.
        settingsSubscription = settings.$settings
            .map { WatchSettingsKey(cueColor: $0.cards.cueColor, watch: $0.watch,
                                    cardsTimerDuration: $0.cards.timerDurationSeconds,
                                    cardsTimerStyle: $0.cards.timerStyle) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // $settings fires before the change is stored.
                Task { @MainActor in self?.stateChanged() }
            }
    }

    /// What the watch shows of the iPhone right now.
    var state: WatchPhoneState {
        let deck = CueCardsSession.shared
        return WatchPhoneState(
            teleprompter: TeleprompterPiPManager.shared.timerState,
            cards: deck.cards.isEmpty ? nil : WatchCardsState(
                session: deck.sessionID,
                deckID: deck.deckID,
                title: deck.title,
                cards: deck.cards,
                index: deck.index,
                startedAt: deck.startedAt,
                timerDuration: deck.timerDuration,
                timerStyle: deck.timerStyle
            ),
            // The watch shows cards, so it draws cues in the cards' color.
            cueColor: SettingsService.shared.settings.cards.cueColor,
            settings: SettingsService.shared.settings.watch,
            cardsTimerDuration: SettingsService.shared.settings.cards.timerDurationSeconds,
            cardsTimerStyle: SettingsService.shared.settings.cards.timerStyle,
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

    /// The saved notes chosen for the watch, split into cards. A note with
    /// no separators is one card.
    var decks: [WatchDeck] {
        let settings = SettingsService.shared
        return settings.savedNotes
            .filter { settings.watchNoteIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { WatchDeck(id: $0.id, title: $0.title, cards: CueCards.cards(in: $0.content)) }
    }

    /// Send the watch its decks, if they changed. They go as a file, which
    /// has no size limit and waits for the watch if it is out of reach. A
    /// newer set replaces one still on its way.
    func sendDecks() {
        guard let session, isWatchAppInstalled,
              let data = try? JSONEncoder().encode(decks), data != sentDecks else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-decks-\(UUID().uuidString).json")
        guard (try? data.write(to: url)) != nil else { return }

        for transfer in session.outstandingFileTransfers
        where transfer.file.metadata?[WatchLink.fileKindKey] as? String == WatchLink.decksFileKind {
            transfer.cancel()
        }
        session.transferFile(url, metadata: [WatchLink.fileKindKey: WatchLink.decksFileKind])
        sentDecks = data
    }

    // MARK: - Private

    private func handle(_ command: WatchCommand) async {
        switch command {
        case .refresh:
            // Launched in the background to answer, the deck is still on disk.
            _ = CueCardsSession.shared.restoreIfNeeded()
        case .togglePlayPause:
            _ = TeleprompterRemoteCommand.togglePlayPause.run(source: "watch")
        case .skipBack:
            _ = TeleprompterRemoteCommand.skipBack.run(source: "watch")
        case .showCard(let session, let index):
            let deck = CueCardsSession.shared
            guard deck.restoreIfNeeded(), deck.sessionID == session else { return }
            deck.show(cardAt: index)
            await deck.waitForLockScreen()
            Analytics.logEvent("cards_show", parameters: ["source": "watch"])
        case .openDeck(let id, let title, let cards, let index):
            let onLockScreen = SettingsService.shared.settings.cards.showOnLockScreen
            CueCardsSession.shared.start(cards: cards, title: title, deckID: id, index: index,
                                         showOnLockScreen: onLockScreen)
            await CueCardsSession.shared.waitForLockScreen()
            Analytics.logEvent("cards_open", parameters: [
                "count": cards.count,
                "on_lock_screen": onLockScreen ? 1 : 0,
                "source": "watch"
            ])
        }
    }

    private func sessionStateChanged() {
        guard let session else { return }
        isPaired = session.activationState == .activated && session.isPaired
        isWatchAppInstalled = session.activationState == .activated
            && session.isPaired && session.isWatchAppInstalled
        // A watch app installed again, or another watch, has none of them.
        if !isWatchAppInstalled { sentDecks = nil }
        stateChanged()
        sendDecks()
    }
}

/// The settings the watch shows, to tell when one of them changed.
private struct WatchSettingsKey: Equatable {
    var cueColor: CueColor
    var watch: WatchSettings
    var cardsTimerDuration: Int
    var cardsTimerStyle: TimerStyle
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

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard error != nil else { return }
        // Failed, not replaced by a newer set: send it again next time.
        let isReplaced = session.outstandingFileTransfers.contains {
            $0.file.metadata?[WatchLink.fileKindKey] as? String == WatchLink.decksFileKind
        }
        guard !isReplaced else { return }
        Task { @MainActor in self.sentDecks = nil }
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
