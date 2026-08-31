import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

@main
struct CueCardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var remoteConfig = RemoteConfigService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .environmentObject(remoteConfig)
                .preferredColorScheme(settingsService.settings.themePreference.colorScheme)
                .task {
                    await remoteConfig.refresh()
                }
                .onChange(of: scenePhase) { phase in
                    // Coming back to the app is the natural moment to pick up a
                    // new notice. The service throttles itself, so this is cheap.
                    guard phase == .active else { return }
                    Task { await remoteConfig.refresh() }
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Configure Crashlytics
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
        return true
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
    static let appStore = URL(string: "https://apps.apple.com/app/id6757321325")!
}
