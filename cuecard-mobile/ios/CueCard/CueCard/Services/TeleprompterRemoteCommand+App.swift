import FirebaseAnalytics
import Foundation

extension TeleprompterRemoteCommand {
    @MainActor
    static func waitForActivity() async {
        await TeleprompterPiPManager.shared.waitForLiveActivity()
    }

    /// Drives the open session. False when there is none.
    @MainActor
    func run(source: String = "remote") -> Bool {
        let manager = TeleprompterPiPManager.shared
        guard manager.hasSession else { return false }
        switch self {
        case .togglePlayPause:
            let wasRunning = manager.playback.isPlaying || manager.playback.isCountingDown
            manager.togglePlayPause()
            Analytics.logEvent(wasRunning ? "teleprompter_pause" : "teleprompter_play",
                               parameters: ["source": source])
        case .skipBack:
            manager.skip(bySeconds: -Double(Self.skipBackSeconds))
            Analytics.logEvent("teleprompter_skip_back", parameters: ["source": source])
        }
        return true
    }
}
