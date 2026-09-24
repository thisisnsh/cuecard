import AppIntents
import Foundation

/// Playback commands that reach a running session without opening the app:
/// the Control Center and Action button control, and the watch. Shared by the
/// app and the widget extension. A Live Activity intent always runs in the app's process,
/// where `run()` drives the session; the widget extension only needs the
/// types to build its controls.
enum TeleprompterRemoteCommand {
    case togglePlayPause, skipBack

    /// How far Back goes, in seconds of script.
    static let skipBackSeconds = 10
}

/// Nothing to control until a script is open in the teleprompter.
struct TeleprompterNotRunningError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Open a script in CueCard's teleprompter first."
    }
}

@available(iOS 17.0, *)
struct ToggleTeleprompterPlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or Pause Teleprompter"
    static var description = IntentDescription("Plays or pauses the script open in the teleprompter.")

    func perform() async throws -> some IntentResult {
        guard await TeleprompterRemoteCommand.togglePlayPause.run() else { throw TeleprompterNotRunningError() }
        return .result()
    }
}
