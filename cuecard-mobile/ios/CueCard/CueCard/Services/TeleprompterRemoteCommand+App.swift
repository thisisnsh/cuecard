import FirebaseAnalytics
import Foundation

extension TeleprompterRemoteCommand {
    /// Drives the open session. False when there is none.
    @MainActor
    func run() -> Bool {
        let manager = TeleprompterPiPManager.shared
        guard manager.hasSession else { return false }
        switch self {
        case .togglePlayPause:
            let wasRunning = manager.playback.isPlaying || manager.playback.isCountingDown
            manager.togglePlayPause()
            Analytics.logEvent(wasRunning ? "teleprompter_pause" : "teleprompter_play",
                               parameters: ["source": "remote"])
        case .skipBack:
            manager.skip(bySeconds: -Double(Self.skipBackSeconds))
            Analytics.logEvent("teleprompter_skip_back", parameters: ["source": "remote"])
        }
        return true
    }
}
