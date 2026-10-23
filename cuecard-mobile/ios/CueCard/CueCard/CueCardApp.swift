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
                .onChange(of: scenePhase) { _, phase in
                    // Coming back to the app is the natural moment to pick up a
                    // new notice. The service throttles itself, so this is cheap.
                    guard phase == .active else { return }
                    CueCardsSession.shared.refreshLockScreen()
                    // Notes in the notes folder may have been edited elsewhere.
                    settingsService.syncNotesFolder()
                    Task { await notifications.refresh() }
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

        // The language the app is showing, which can differ from the phone's.
        // One event per language, so the Events report counts each one's users
        // as it is. Event names can't hold a hyphen, so pt-BR becomes pt_br.
        let language = (Bundle.main.preferredLocalizations.first ?? "en").lowercased().replacingOccurrences(of: "-", with: "_")
        Analytics.logEvent("app_language_\(language)", parameters: nil)

        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

        // At launch, so a command from the watch that launched the app in the
        // background is heard.
        WatchSessionService.shared.activate()

        _ = CueCardsSession.shared.restoreIfNeeded()
        SettingsService.shared.removeUnusedImages()
        Task { await CueCardsLockScreen.removeLegacyNotifications() }
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
    static let privacyPolicy = URL(string: "https://cuecard.dev/privacy/")!
    static let appStore = URL(string: "https://apps.apple.com/app/id6757321325")!
    static let supportEmail = URL(string: "mailto:support@cuecard.dev?subject=CueCard%20Feedback")!

    /// An email to support about a translation, with the language's code.
    static func translationReport(language: String) -> URL {
        supportEmail(
            subject: "CueCard Translation Mistake (\(language))",
            body: String(localized: "Where in the app:\n\nWhat it says:\n\nWhat it should say:\n")
        )
    }

    /// An email to support about something that's broken.
    static let bugReport = supportEmail(
        subject: "CueCard Bug Report",
        body: String(localized: "What happened:\n\nWhat you expected:\n\nSteps to reproduce:\n")
    )

    /// An email to support asking for something new.
    static let featureRequest = supportEmail(
        subject: "CueCard Feature Request",
        body: String(localized: "What would you like CueCard to do?\n")
    )

    /// An email to support. The subject stays English so emails sort
    /// together whatever the language.
    private static func supportEmail(subject: String, body: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@cuecard.dev"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? supportEmail
    }

    /// What goes out when someone shares the app.
    static let shareMessage = String(localized: "Check out \(appStore.absoluteString)", comment: "Shared with a link to CueCard on the App Store")
}
