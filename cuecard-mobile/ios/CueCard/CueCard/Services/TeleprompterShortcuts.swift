import AppIntents

/// The playback intents as ready-made shortcuts: in the Shortcuts app, in
/// Spotlight and Siri, and for the Action button, with nothing to set up.
@available(iOS 17.0, *)
struct TeleprompterShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .grayBlue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleTeleprompterPlaybackIntent(),
            phrases: [
                "Play or pause \(.applicationName)",
                "Pause \(.applicationName)",
                "Resume \(.applicationName)"
            ],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: SkipBackTeleprompterIntent(),
            phrases: [
                "Skip back in \(.applicationName)",
                "Go back in \(.applicationName)"
            ],
            shortTitle: "Back 10 Seconds",
            systemImageName: "gobackward.10"
        )
    }
}
