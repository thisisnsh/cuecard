import ActivityKit
import AppIntents
import Foundation

/// A presentation snapshot. Only the app writes it; commands run in the app
/// process, keeping the app, Watch and widgets on one session.
struct CueCardsWidgetState: Codable, Hashable {
    var sessionID: UUID
    var title: String
    /// The card on top, cues kept apart so they draw in the cue color.
    var runs: [CueCardRun]
    var cueColor: CueColor
    var index: Int
    var count: Int

    var isFinished: Bool { index >= count }
    var progress: String { isFinished ? "Done" : "\(index + 1) of \(count)" }
    var text: String { runs.map(\.text).joined() }

    static let preview = Self(sessionID: UUID(), title: "My cards",
                              runs: [CueCardRun(text: "Take a breath. ", isCue: false),
                                     CueCardRun(text: "Look up.", isCue: true),
                                     CueCardRun(text: " Start with your main idea.", isCue: false)],
                              cueColor: .default, index: 0, count: 5)
}

enum CueCardsWidgetStore {
    static let kind = "com.thisisnsh.cuecard.ios.cards"
    static let groupID = "group.com.thisisnsh.cuecard.ios"
    private static let key = "cards_widget_state"

    static func read() -> CueCardsWidgetState? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CueCardsWidgetState.self, from: data)
    }

    static func write(_ state: CueCardsWidgetState?) {
        let defaults = UserDefaults(suiteName: groupID)
        if let state, let data = try? JSONEncoder().encode(state) {
            defaults?.set(data, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }
}

struct CueCardsActivityAttributes: ActivityAttributes {
    typealias ContentState = CueCardsWidgetState
    var sessionID: UUID
}

enum CueCardsRemoteCommand {}

@available(iOS 17.0, *)
struct MoveCueCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Cue Card"
    static var description = IntentDescription("Moves through the open deck of cue cards.")
    static var isDiscoverable = false

    @Parameter(title: "Session") var session: String
    @Parameter(title: "Current card") var currentIndex: Int
    @Parameter(title: "Destination card") var targetIndex: Int

    init() {}

    init(state: CueCardsWidgetState, targetIndex: Int) {
        session = state.sessionID.uuidString
        currentIndex = state.index
        self.targetIndex = targetIndex
    }

    func perform() async throws -> some IntentResult {
        await CueCardsRemoteCommand.move(session: session, currentIndex: currentIndex, targetIndex: targetIndex)
        return .result()
    }
}
