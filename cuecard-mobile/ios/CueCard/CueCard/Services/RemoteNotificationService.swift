import Foundation
import FirebaseAnalytics

/// Fetches `/v2/config` from the mobile worker and decides what the app does with
/// it: which features stay switched on, whether this build is too old to run, and
/// which notice — if any — belongs on a given screen.
///
/// The whole thing is built to fail open. The last good response is kept on disk
/// and used immediately at launch, a fetch that times out or comes back malformed
/// changes nothing, and a client that has never once reached the worker behaves
/// exactly as it was shipped. Nothing here blocks the UI: the config arrives when
/// it arrives, and the views update if it changes anything.
@MainActor
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    private static let endpoint = URL(string: "https://cuecard-mobile.thisisnsh.workers.dev/v2/config")!

    /// Long enough that foregrounding the app repeatedly doesn't hammer the edge,
    /// short enough that pulling a bad message takes effect within a session.
    ///
    /// Debug builds get a few seconds instead, because the release interval makes
    /// testing a message impossible: you edit the worker, background and foreground
    /// the app, and nothing happens for a quarter of an hour.
    #if DEBUG
    private static let minimumRefreshInterval: TimeInterval = 5
    #else
    private static let minimumRefreshInterval: TimeInterval = 15 * 60
    #endif

    @Published private(set) var config: RemoteConfig = .empty
    @Published private(set) var dismissedIDs: Set<String> = []

    private let userDefaults = UserDefaults.standard
    private let configKey = "cuecard_remote_config"
    private let dismissedKey = "cuecard_remote_config_dismissed"
    private let bucketKey = "cuecard_remote_config_bucket"

    private var lastRefresh: Date?

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.waitsForConnectivity = false
        // The worker sends `Cache-Control: max-age=300`, which URLSession honours
        // by replaying its stored copy without ever going to the network. We do
        // our own throttling and keep our own copy on disk, so a second layer of
        // caching here buys nothing and hides a freshly deployed message for
        // another five minutes.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private init() {
        if let data = userDefaults.data(forKey: configKey),
           let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data) {
            config = cached
        }

        dismissedIDs = Set(userDefaults.stringArray(forKey: dismissedKey) ?? [])
    }

    // MARK: - Fetching

    /// Pull a fresh config. Safe to call on every launch and every foreground —
    /// it throttles itself, and it never throws.
    func refresh(force: Bool = false) async {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.minimumRefreshInterval {
            return
        }

        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "p", value: "ios"),
            URLQueryItem(name: "v", value: AppVersion.current),
            URLQueryItem(name: "b", value: String(AppVersion.build)),
            URLQueryItem(name: "l", value: Self.languageCode)
        ]

        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let fetched = try JSONDecoder().decode(RemoteConfig.self, from: data)

            lastRefresh = Date()
            config = fetched
            userDefaults.set(data, forKey: configKey)
            pruneDismissals(against: fetched)
        } catch {
            // Offline, slow, or the worker returned something we couldn't read.
            // Whatever was cached stays in force.
        }
    }

    // MARK: - Flags

    /// True when this build is older than the worker's stated floor. The one piece
    /// of remote config allowed to stand in front of the app, so it's only ever
    /// set when a shipped build is genuinely unusable.
    var requiresUpdate: Bool {
        AppVersion.compare(AppVersion.current, config.flags.minSupportedVersion) == .orderedAscending
    }

    /// Where the update screen sends people, falling back to our own listing if
    /// the worker didn't name one.
    var updateURL: URL {
        config.flags.updateURL ?? AppLinks.appStore
    }

    var isPiPEnabled: Bool { config.flags.features.pip }
    var isAppleSignInEnabled: Bool { config.flags.features.appleSignIn }
    var isGoogleSignInEnabled: Bool { config.flags.features.googleSignIn }

    // MARK: - Messages

    /// The one message to show on a surface: highest priority among those this
    /// install is eligible for. One at a time — a stack of banners reads as spam.
    func message(for surface: RemoteMessage.Surface) -> RemoteMessage? {
        config.messages
            .filter { $0.surface == surface && isEligible($0) }
            .max { $0.priority < $1.priority }
    }

    func dismiss(_ message: RemoteMessage) {
        guard message.dismissible else { return }

        dismissedIDs.insert(message.id)
        userDefaults.set(Array(dismissedIDs), forKey: dismissedKey)

        Analytics.logEvent("remote_message_dismissed", parameters: ["message_id": message.id])
    }

    func logImpression(_ message: RemoteMessage) {
        Analytics.logEvent("remote_message_shown", parameters: [
            "message_id": message.id,
            "surface": message.surface.rawValue
        ])
    }

    func logAction(_ action: RemoteMessage.Action, in message: RemoteMessage) {
        Analytics.logEvent("remote_message_action", parameters: [
            "message_id": message.id,
            "action": action.kind.rawValue
        ])
    }

    private func isEligible(_ message: RemoteMessage) -> Bool {
        guard message.isRenderable else { return false }
        guard !message.hasExpired() else { return false }
        guard !dismissedIDs.contains(message.id) else { return false }
        guard rolloutBucket < message.rolloutPercent else { return false }

        // The worker filters on `match` as well, but a cached payload can outlive
        // the app version it was fetched for, so check again here.
        if let match = message.match {
            let admits = match.admits(
                platform: "ios",
                version: AppVersion.current,
                build: AppVersion.build,
                locale: Self.languageCode
            )
            if !admits { return false }
        }

        return true
    }

    /// Forget dismissals for messages the worker has stopped sending, so the list
    /// can't grow forever. Ids are never reused for different copy, so a message
    /// that comes back is the same one the user already waved away.
    private func pruneDismissals(against config: RemoteConfig) {
        let live = Set(config.messages.map(\.id))
        let kept = dismissedIDs.intersection(live)

        guard kept != dismissedIDs else { return }

        dismissedIDs = kept
        userDefaults.set(Array(kept), forKey: dismissedKey)
    }

    /// A number in 0..<100, drawn once and kept, so a partial rollout stays
    /// consistent for this install instead of flickering between launches.
    private var rolloutBucket: Int {
        if let stored = userDefaults.object(forKey: bucketKey) as? Int { return stored }

        let bucket = Int.random(in: 0..<100)
        userDefaults.set(bucket, forKey: bucketKey)
        return bucket
    }

    private static var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
