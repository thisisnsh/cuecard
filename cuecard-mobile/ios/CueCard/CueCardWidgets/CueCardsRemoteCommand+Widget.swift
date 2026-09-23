import Foundation

extension CueCardsRemoteCommand {
    // LiveActivityIntent runs in the app; this definition only links the extension.
    @MainActor
    static func move(session: String, currentIndex: Int, targetIndex: Int) async {}
}
