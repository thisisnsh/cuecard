import Combine
import Foundation

/// The open deck shared by the app, Watch and Live Activity.
/// Persisted so an intent can resume the session after the app exits.
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
    /// Live Activities are disabled or the activity could not be started.
    @Published private(set) var lockScreenUnavailable = false

    var isFinished: Bool { index >= cards.count }

    private var pendingUpdate: Task<Void, Never>?

    private static let storageKey = "cuecard_cards_session"

    /// Enough to pick the deck back up after the app has been quit.
    private struct Stored: Codable {
        var cards: [String]
        var index: Int
        var sessionID: UUID?
        var title: String?
        var deckID: UUID?
        var isOnLockScreen: Bool?
    }

    private var cueColorSubscription: AnyCancellable?

    private init() {
        // Redraw the Live Activity in a newly picked cue color.
        cueColorSubscription = SettingsService.shared.$settings
            .map(\.cueColor)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // $settings fires before the change is stored.
                Task { @MainActor in self?.updateLockScreen() }
            }
    }

    /// Open a deck, on its first card unless told otherwise, and put it on
    /// the Lock Screen if asked.
    func start(cards: [String], title: String, deckID: UUID?, index: Int = 0,
               showOnLockScreen: Bool) {
        self.cards = cards
        self.title = title
        self.deckID = deckID
        self.index = min(max(index, 0), cards.count)
        sessionID = UUID()
        isOnLockScreen = false
        lockScreenUnavailable = false
        save()
        WatchSessionService.shared.stateChanged()
        if showOnLockScreen {
            self.showOnLockScreen()
        } else {
            // Any left over from a deck the app was quit during.
            enqueue { await CueCardsLockScreen.clear() }
        }
    }

    /// Start a Live Activity for the current deck, without notification permission.
    func showOnLockScreen() {
        guard !cards.isEmpty else { return }
        let sessionID = sessionID
        enqueue { [self] in
            guard self.sessionID == sessionID, !cards.isEmpty else { return }
            let shown = await CueCardsLockScreen.show(widgetState)
            guard self.sessionID == sessionID, !cards.isEmpty else { return }
            isOnLockScreen = shown
            if shown { await CueCardsLockScreen.sync(widgetState) }
            lockScreenUnavailable = !shown
            save()
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
        lockScreenUnavailable = false
        enqueue { await CueCardsLockScreen.clear() }
        WatchSessionService.shared.stateChanged()
    }

    /// Restore a session for a Live Activity or Watch command.
    func restoreIfNeeded() -> Bool {
        if !cards.isEmpty { return true }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              !stored.cards.isEmpty else { return false }

        cards = stored.cards
        index = min(max(stored.index, 0), stored.cards.count)
        sessionID = stored.sessionID ?? UUID()
        title = stored.title ?? ""
        deckID = stored.deckID
        isOnLockScreen = CueCardsLockScreen.isActive(session: sessionID)
        return true
    }

    /// Reconcile a Live Activity dismissed or expired while the app was away.
    func refreshLockScreen() {
        guard restoreIfNeeded() else { return }
        isOnLockScreen = CueCardsLockScreen.isActive(session: sessionID)
        updateLockScreen()
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
        let state = widgetState
        enqueue {
            await CueCardsLockScreen.sync(state)
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

    private var widgetState: CueCardsWidgetState {
        // Keep ActivityKit's payload well below 4 KB, including unusual Unicode.
        func bounded(_ text: String, bytes: Int) -> String {
            var result = ""
            for character in text {
                guard result.utf8.count + String(character).utf8.count <= bytes else { break }
                result.append(character)
            }
            return result
        }
        let allRuns = isFinished
            ? [CueCardRun(text: "All cards done", isCue: false)]
            : CueCards.runs(for: cards[index])
        var runs: [CueCardRun] = []
        var budget = 1600
        for run in allRuns where budget > 0 {
            let text = bounded(run.text, bytes: budget)
            guard !text.isEmpty else { break }
            budget -= text.utf8.count
            runs.append(CueCardRun(text: text, isCue: run.isCue))
        }
        var state = CueCardsWidgetState(sessionID: sessionID, title: bounded(title, bytes: 160), runs: runs,
                                        cueColor: SettingsService.shared.settings.cueColor,
                                        index: index, count: cards.count)
        // JSON escaping can expand control characters beyond their UTF-8 size.
        while !state.runs.isEmpty, let data = try? JSONEncoder().encode(state), data.count > 3000 {
            state.runs[state.runs.count - 1].text.removeLast()
            if state.runs[state.runs.count - 1].text.isEmpty { state.runs.removeLast() }
        }
        return state
    }

    private func save() {
        let stored = Stored(cards: cards, index: index,
                            sessionID: sessionID, title: title, deckID: deckID,
                            isOnLockScreen: isOnLockScreen)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
