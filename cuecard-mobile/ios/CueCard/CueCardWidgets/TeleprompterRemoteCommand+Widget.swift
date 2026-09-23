import Foundation

extension TeleprompterRemoteCommand {
    @MainActor
    static func waitForActivity() async {}

    /// Never called here: the system runs Live Activity intents in the app,
    /// which drives the session. The extension only draws the buttons.
    @MainActor
    func run() -> Bool { false }
}
