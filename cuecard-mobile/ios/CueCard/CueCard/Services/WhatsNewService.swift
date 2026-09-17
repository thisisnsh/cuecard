import Foundation
import FirebaseAnalytics

/// The new features for this build, read from `WhatsNew.json` in the bundle.
///
/// Entries are keyed by `<version>-<build>`, so a release that forgets to add its
/// own entry shows nothing rather than the last release's features. Each build is
/// shown once on launch, remembered under `new-features-<version>-<build>`.
@MainActor
final class WhatsNewService: ObservableObject {
    static let shared = WhatsNewService()

    struct Release: Decodable {
        var title: String?
        let features: [String]
    }

    /// This build's entry, or nil when the file has none for it.
    let release: Release?

    /// The version as people see it, e.g. "1.5.0".
    let version: String

    /// Whether the launch presentation is up. Settings shows its own copy.
    @Published var isPresented = false

    private let userDefaults = UserDefaults.standard
    private let seenKey: String

    private init() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        let key = "\(version)-\(build)"

        self.version = version
        self.seenKey = "new-features-\(key)"
        self.release = Self.loadReleases()[key].flatMap { $0.features.isEmpty ? nil : $0 }
    }

    private static func loadReleases() -> [String: Release] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? JSONDecoder().decode([String: Release].self, from: data)
        else { return [:] }
        return releases
    }

    /// Show this build's features if they haven't been seen. A fresh install has
    /// only just met the app, so it skips them: `hasSeenWelcome` is false there.
    /// Counted as seen once shown, so closing the app on the card doesn't bring
    /// it back.
    func presentIfUnseen(hasSeenWelcome: Bool) {
        guard release != nil, !userDefaults.bool(forKey: seenKey) else { return }
        userDefaults.set(true, forKey: seenKey)
        guard hasSeenWelcome else { return }

        withoutPresentationAnimation { isPresented = true }
        logShown(source: "launch")
    }

    func logShown(source: String) {
        Analytics.logEvent("whats_new_shown", parameters: [
            "version": version,
            "source": source
        ])
    }
}
