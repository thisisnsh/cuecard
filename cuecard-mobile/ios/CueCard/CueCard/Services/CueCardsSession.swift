import ActivityKit
import Foundation

/// The deck open in cards mode, and its Live Activity on the Lock Screen.
///
/// The Lock Screen's buttons run in the app, launching it in the background
/// if it was quit, so the deck is kept on disk as well: a button pressed then
/// picks up where the deck was left. The watch follows the same deck and
/// moves it too.
@MainActor
final class CueCardsSession: ObservableObject {
    static let shared = CueCardsSession()

    private typealias ContentState = CueCardsActivityAttributes.ContentState

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
    /// Live Activities are turned off for the app in Settings.
    @Published private(set) var lockScreenUnavailable = false

    var isFinished: Bool { index >= cards.count }

    private var cueColor: CueColor = .default
    private var activity: Activity<CueCardsActivityAttributes>?
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
    }

    /// A Lock Screen card holds four lines; this is well past what they fit,
    /// and well inside the 4 KB an activity may carry.
    private static let lockScreenMaxLength = 300

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

        // One left over from a deck the app was quit during.
        endActivities()
        if showOnLockScreen {
            self.showOnLockScreen()
        }
    }

    /// Start the Live Activity for the open deck. Only an app on screen may.
    func showOnLockScreen() {
        guard !cards.isEmpty, activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lockScreenUnavailable = true
            return
        }
        lockScreenUnavailable = false

        guard let activity = try? Activity.request(
            attributes: CueCardsActivityAttributes(cueColor: cueColor),
            content: ActivityContent(state: contentState, staleDate: nil)
        ) else { return }
        self.activity = activity
        isOnLockScreen = true
        watch(activity)
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
        endActivities()
        WatchSessionService.shared.stateChanged()
    }

    /// Pick up the deck a Lock Screen button is pressed for, when the button
    /// has launched the app in the background to run. False when there is none.
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
        if let activity = Activity<CueCardsActivityAttributes>.activities.first {
            self.activity = activity
            isOnLockScreen = true
            watch(activity)
        }
        return true
    }

    /// Wait for the Lock Screen to catch up with the last move, so an intent
    /// doesn't return, and let the app be suspended, before it has.
    func waitForLockScreen() async {
        await pendingUpdate?.value
    }

    // MARK: - Private

    private var contentState: ContentState {
        let runs = isFinished ? [] : CueCards.runs(for: cards[index], maxLength: Self.lockScreenMaxLength)
        return ContentState(runs: runs, index: index, count: cards.count)
    }

    private func deckChanged() {
        save()
        WatchSessionService.shared.stateChanged()
        guard let activity else { return }
        let content = ActivityContent(state: contentState, staleDate: nil)
        let previous = pendingUpdate
        pendingUpdate = Task {
            // In order, so a quick run of taps can't land out of turn.
            await previous?.value
            await activity.update(content)
        }
    }

    private func save() {
        let stored = Stored(cards: cards, index: index, cueColor: cueColor,
                            sessionID: sessionID, title: title, deckID: deckID)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Notice the activity being swiped away on the Lock Screen, so the app
    /// can offer to put it back.
    private func watch(_ activity: Activity<CueCardsActivityAttributes>) {
        Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                guard let self, self.activity?.id == activity.id else { return }
                self.activity = nil
                self.isOnLockScreen = false
                return
            }
        }
    }

    private func endActivities() {
        activity = nil
        isOnLockScreen = false
        pendingUpdate = nil
        let activities = Activity<CueCardsActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
