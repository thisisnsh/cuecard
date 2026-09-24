import ActivityKit
import AppIntents
import Foundation

/// A presentation snapshot. Only the app writes it; commands run in the app
/// process, keeping the app, Watch and Live Activity on one session.
struct CueCardsWidgetState: Codable, Hashable {
    var sessionID: UUID
    var title: String
    /// The card on top, cues kept apart so they draw in the cue color.
    var runs: [CueCardRun]
    var cueColor: CueColor
    var index: Int
    var count: Int
    /// The deck's timer, ticked by the system between updates.
    var timer: TeleprompterTimerState?

    var isFinished: Bool { index >= count }
    var progress: String { isFinished ? "Done" : "\(index + 1) of \(count)" }
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
