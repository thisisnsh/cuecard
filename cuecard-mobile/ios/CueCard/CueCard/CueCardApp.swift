import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

@main
struct CueCardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var notifications = RemoteNotificationService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsService)
                .environmentObject(notifications)
                .preferredColorScheme(settingsService.settings.themePreference.colorScheme)
                .task {
                    await notifications.refresh()
                }
                .onChange(of: scenePhase) { phase in
                    TeleprompterPiPManager.shared.sceneDidChange(to: phase)
                    // Coming back to the app is the natural moment to pick up a
                    // new notice. The service throttles itself, so this is cheap.
                    guard phase == .active else { return }
                    Task { await notifications.refresh() }
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // A previous process cannot still be running this in-memory reader.
        TeleprompterPiPManager.shared.cleanup()

        // Configure Crashlytics
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

        // At launch, so a command from the watch that launched the app in the
        // background is heard.
        WatchSessionService.shared.activate()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TeleprompterPiPManager.shared.cleanup()
    }
}

// MARK: - Analytics Helper
struct AnalyticsEvents {
    static func logButtonClick(_ buttonName: String, screen: String, parameters: [String: Any]? = nil) {
        var params: [String: Any] = [
            "button_name": buttonName,
            "screen_name": screen
        ]
        if let additionalParams = parameters {
            params.merge(additionalParams) { _, new in new }
        }
        Analytics.logEvent("button_click", parameters: params)
        Crashlytics.crashlytics().log("Button clicked: \(buttonName) on \(screen)")
    }
}

// MARK: - External Links
enum AppLinks {
    static let sourceCode = URL(string: "https://github.com/thisisnsh/cuecard")!
    static let privacyPolicy = URL(string: "https://cuecard.dev/privacy/")!
    static let appStore = URL(string: "https://apps.apple.com/app/id6757321325")!

    /// What goes out when someone shares the app.
    static let shareMessage = "Check out \(appStore.absoluteString)"
}
