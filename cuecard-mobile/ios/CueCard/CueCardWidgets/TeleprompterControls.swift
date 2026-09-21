import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button controls for the session
/// open in the teleprompter. Their intents run in the app, like the Live
/// Activity's buttons, so they work while the floating window is up.
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

@available(iOS 18.0, *)
struct TeleprompterSkipBackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.thisisnsh.cuecard.ios.control.skipBack") {
            ControlWidgetButton(action: SkipBackTeleprompterIntent()) {
                Label("Back \(TeleprompterRemoteCommand.skipBackSeconds) Seconds",
                      systemImage: "gobackward.\(TeleprompterRemoteCommand.skipBackSeconds)")
            }
        }
        .displayName("Back 10 Seconds")
        .description("Moves the teleprompter's script back 10 seconds.")
    }
}
