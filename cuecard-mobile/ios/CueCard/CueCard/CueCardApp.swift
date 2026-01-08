import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

@main
struct CueCardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var settingsService = SettingsService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .preferredColorScheme(settingsService.settings.themePreference.colorScheme)
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
