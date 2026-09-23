import Foundation

/// The deck open in cards mode, and its cards on the Lock Screen.
///
/// Clearing a card on the Lock Screen, or its Back and Start Over, launch the
/// app in the background if it was quit, so the deck is kept on disk as well:
/// the move then picks up where the deck was left. The watch follows the same
/// deck and moves it too.
@MainActor
final class CueCardsSession: ObservableObject {
    static let shared = CueCardsSession()

    @Published private(set) var cards: [String] = []
    /// The card on top. Equal to the number of cards once every one has been
    /// put away.
    @Published private(set) var index = 0
    /// This opening of the deck, so a move the watch made for an earlier one
    /// can be told apart.
    @Published private(set) var sessionID = UUID()
    private(set) var title = ""
    /// The saved note the deck came from, when it came from one.
    private(set) var deckID: UUID?
    /// Whether the deck is up on the Lock Screen right now.
    @Published private(set) var isOnLockScreen = false
    /// Notifications are turned off for the app in Settings.
    @Published private(set) var lockScreenUnavailable = false

    var isFinished: Bool { index >= cards.count }

    private var cueColor: CueColor = .default
    private var pendingUpdate: Task<Void, Never>?

    private static let storageKey = "cuecard_cards_session"

    /// Enough to pick the deck back up after the app has been quit.
    private struct Stored: Codable {
        var cards: [String]
        var index: Int
        var cueColor: CueColor
        var sessionID: UUID?
        var title: String?
        var deckID: UUID?
        var isOnLockScreen: Bool?
    }

    private init() {}

    /// Open a deck, on its first card unless told otherwise, and put it on
    /// the Lock Screen if asked.
    func start(cards: [String], title: String, deckID: UUID?, index: Int = 0,
               cueColor: CueColor, showOnLockScreen: Bool) {
        self.cards = cards
        self.title = title
        self.deckID = deckID
        self.cueColor = cueColor
        self.index = min(max(index, 0), cards.count)
        sessionID = UUID()
        save()
        WatchSessionService.shared.stateChanged()

        isOnLockScreen = false
        if showOnLockScreen {
            self.showOnLockScreen()
        } else {
            // Any left over from a deck the app was quit during.
            enqueue { await CueCardsLockScreen.clear() }
        }
    }

    /// Put the open deck's cards on the Lock Screen, asking for notifications
    /// the first time.
    func showOnLockScreen() {
        guard !cards.isEmpty else { return }
        let sessionID = sessionID
        enqueue { [self] in
            guard await CueCardsLockScreen.requestAuthorization() else {
                lockScreenUnavailable = true
                return
            }
            // Closed, or another deck opened, while the prompt was up.
            guard self.sessionID == sessionID, !cards.isEmpty else { return }
            lockScreenUnavailable = false
            isOnLockScreen = true
            save()
            await CueCardsLockScreen.sync(cards: cards, title: title, index: index, session: sessionID)
        }
    }

    func next() {
        guard index < cards.count else { return }
        index += 1
        deckChanged()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        deckChanged()
    }

    func restart() {
        guard index != 0 else { return }
        index = 0
        deckChanged()
    }

    /// Show a card by number, as the watch asks. Equal to the number of cards
    /// puts every one away.
    func show(cardAt newIndex: Int) {
        let newIndex = min(max(newIndex, 0), cards.count)
        guard newIndex != index else { return }
        index = newIndex
        deckChanged()
    }

    /// Close the deck and take it off the Lock Screen.
    func end() {
        cards = []
        index = 0
        title = ""
        deckID = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        isOnLockScreen = false
        enqueue { await CueCardsLockScreen.clear() }
        WatchSessionService.shared.stateChanged()
    }

    /// Pick up the deck a Lock Screen card is cleared or pressed for, when that
    /// has launched the app in the background. False when there is none.
    func restoreIfNeeded() -> Bool {
        if !cards.isEmpty { return true }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              !stored.cards.isEmpty else { return false }

        cards = stored.cards
        index = min(stored.index, stored.cards.count)
        cueColor = stored.cueColor
        sessionID = stored.sessionID ?? UUID()
        title = stored.title ?? ""
        deckID = stored.deckID
        isOnLockScreen = stored.isOnLockScreen ?? false
        return true
    }

    /// Wait for the Lock Screen to catch up with the last move, so the app
    /// isn't suspended before it has.
    func waitForLockScreen() async {
        await pendingUpdate?.value
    }

    // MARK: - Private

    private func deckChanged() {
        save()
        WatchSessionService.shared.stateChanged()
        updateLockScreen()
    }

    private func updateLockScreen() {
        guard isOnLockScreen else { return }
        let cards = cards, title = title, index = index, sessionID = sessionID
        enqueue {
            await CueCardsLockScreen.sync(cards: cards, title: title, index: index, session: sessionID)
        }
    }

    /// Lock Screen work runs in order, so a quick run of moves can't land out
    /// of turn, and a closed deck can't be put back up by a late one.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingUpdate
        pendingUpdate = Task {
            await previous?.value
            await work()
        }
    }

    private func save() {
        let stored = Stored(cards: cards, index: index, cueColor: cueColor,
                            sessionID: sessionID, title: title, deckID: deckID,
                            isOnLockScreen: isOnLockScreen)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
