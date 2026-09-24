import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button control for the session
/// open in the teleprompter. Its intent runs in the app, so it works while
/// the floating window is up.
@available(iOS 18.0, *)
struct TeleprompterPlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.thisisnsh.cuecard.ios.control.playPause") {
            ControlWidgetButton(action: ToggleTeleprompterPlaybackIntent()) {
                Label("Play or Pause", systemImage: "playpause.fill")
            }
        }
        .displayName("Play or Pause")
        .description("Plays or pauses the script open in the teleprompter.")
    }
}
