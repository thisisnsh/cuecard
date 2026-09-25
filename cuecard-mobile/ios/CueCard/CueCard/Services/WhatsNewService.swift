import Foundation
import FirebaseAnalytics

/// The new features for this version, read from `WhatsNew.json` in the bundle.
///
/// Entries are keyed by `<version>`, so a release that forgets to add its own
/// entry shows nothing rather than the last release's features. Builds of the
/// same version share an entry, so a rebuild doesn't show it again. Each version
/// is shown once on launch, remembered under `new-features-<version>`.
@MainActor
final class WhatsNewService: ObservableObject {
    static let shared = WhatsNewService()

    struct Release: Decodable {
        var title: String?
        let features: [String]
    }

    /// This version's entry, or nil when the file has none for it.
    let release: Release?

    /// The version as people see it, e.g. "1.5.0".
    let version: String

    private let userDefaults = UserDefaults.standard
    private let seenKey: String

    private init() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"

        self.version = version
        self.seenKey = "new-features-\(version)"
        self.release = Self.loadReleases()[version].flatMap { $0.features.isEmpty ? nil : $0 }
    }

    private static func loadReleases() -> [String: Release] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? JSONDecoder().decode([String: Release].self, from: data)
        else { return [:] }
        return releases
    }

    /// Show this version's features if they haven't been seen. A fresh install has
    /// only just met the app, so it skips them: `hasSeenWelcome` is false there.
    /// Counted as seen once shown, so closing the app on the card doesn't bring
    /// it back.
    func presentIfUnseen(hasSeenWelcome: Bool) {
        guard release != nil, !userDefaults.bool(forKey: seenKey) else { return }
        userDefaults.set(true, forKey: seenKey)
        guard hasSeenWelcome else { return }

        show()
        logShown()
    }

    /// Float this version's features over whatever is on screen.
    func show() {
        guard let release else { return }
        WhatsNewPresenter.show(release: release, version: version)
    }

    /// Counts the people this version's features reached on their own. Opening the
    /// card from Help is a `button_click` instead, so this stays a clean
    /// impression count rather than one mixed with people going looking.
    private func logShown() {
        Analytics.logEvent("whats_new_shown", parameters: [
            "version": version
        ])
    }
}
