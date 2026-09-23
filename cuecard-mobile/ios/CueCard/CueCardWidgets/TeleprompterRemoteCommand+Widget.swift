import Foundation

extension TeleprompterRemoteCommand {
    /// Never called here: the system runs Live Activity intents in the app,
    /// which drives the session. The extension only draws the controls.
    @MainActor
    func run() -> Bool { false }
}
