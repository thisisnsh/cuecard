import AppIntents
import Foundation

/// Moves through the deck open in cards mode without opening the app: the
/// Live Activity's buttons, and anything else that runs these intents. Shared
/// by the app and the widget extension. A Live Activity intent always runs in
/// the app's process, launching it in the background if it has to, where
/// `run()` moves the deck; the extension only needs the types for its buttons.
enum CueCardsRemoteCommand {
    case next, previous, restart
}

/// Nothing to move through until cards are open.
struct CueCardsNotRunningError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Open your cards in CueCard first."
    }
}

@available(iOS 17.0, *)
struct NextCueCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Cue Card"
    static var description = IntentDescription("Puts the card on top away and shows the next one.")

    func perform() async throws -> some IntentResult {
        guard await CueCardsRemoteCommand.next.run() else { throw CueCardsNotRunningError() }
        return .result()
    }
}

@available(iOS 17.0, *)
struct PreviousCueCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Cue Card"
    static var description = IntentDescription("Brings back the card put away last.")

    func perform() async throws -> some IntentResult {
        guard await CueCardsRemoteCommand.previous.run() else { throw CueCardsNotRunningError() }
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestartCueCardsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Cue Cards Over"
    static var description = IntentDescription("Goes back to the first card.")

    func perform() async throws -> some IntentResult {
        guard await CueCardsRemoteCommand.restart.run() else { throw CueCardsNotRunningError() }
        return .result()
    }
}
