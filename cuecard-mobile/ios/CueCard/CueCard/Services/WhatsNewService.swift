import Foundation
import FirebaseAnalytics

/// What changed in each version, read from `WhatsNew.json` in the bundle.
///
/// Entries are keyed by `<version>`, and shown as one card each, newest first.
/// A release that forgets to add its own entry isn't shown on launch, rather
/// than showing the last release's features again. Builds of the same version
/// share an entry, so a rebuild doesn't show it again. Each version is shown
/// once on launch, remembered under `new-features-<version>`.
@MainActor
final class WhatsNewService: ObservableObject {
    static let shared = WhatsNewService()

    struct Release: Decodable, Identifiable {
        var title: String?
        let features: [String]
        /// Filled in from the entry's key, not the entry itself.
        var version = ""

        var id: String { version }

        private enum CodingKeys: String, CodingKey {
            case title, features
        }
    }

    /// Every version's entry, newest first.
    let releases: [Release]

    /// Whether this version has an entry of its own.
    var hasCurrentRelease: Bool { releases.contains { $0.version == version } }

    /// The version as people see it, e.g. "1.5.0".
    let version: String

    private let userDefaults = UserDefaults.standard
    private let seenKey: String

    private init() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"

        self.version = version
        self.seenKey = "new-features-\(version)"
        self.releases = Self.loadReleases()
    }

    private static func loadReleases() -> [Release] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? JSONDecoder().decode([String: Release].self, from: data)
        else { return [] }
        return releases
            .filter { !$0.value.features.isEmpty }
            .map { version, release in
                var release = release
                release.version = version
                return release
            }
            // Numeric, so 1.10.0 comes after 1.9.0.
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    /// Show what changed if this version's features haven't been seen. A fresh install has
    /// only just met the app, so it skips them: `hasSeenWelcome` is false there.
    /// Counted as seen once shown, so closing the app on the card doesn't bring
    /// it back.
    func presentIfUnseen(hasSeenWelcome: Bool) {
        guard hasCurrentRelease, !userDefaults.bool(forKey: seenKey) else { return }
        userDefaults.set(true, forKey: seenKey)
        guard hasSeenWelcome else { return }

        show()
        logShown()
    }

    /// Float every version's card over whatever is on screen, newest first.
    func show() {
        guard !releases.isEmpty else { return }
        WhatsNewPresenter.show(releases: releases)
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
