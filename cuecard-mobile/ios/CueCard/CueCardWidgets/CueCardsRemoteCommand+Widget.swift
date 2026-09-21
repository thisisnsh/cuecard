import Foundation

extension CueCardsRemoteCommand {
    /// Never called here: the system runs Live Activity intents in the app,
    /// which holds the deck. The extension only draws the buttons.
    @MainActor
    func run() async -> Bool { false }
}
