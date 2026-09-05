import Foundation
import FirebaseAnalytics

/// Fetches `/v2/notifications` from the mobile worker and decides which notice —
/// if any — belongs on a given screen.
///
/// The whole thing is built to fail open. The last good response is kept on disk
/// and used immediately at launch, a fetch that times out or comes back malformed
/// changes nothing, and a client that has never once reached the worker simply
/// shows nothing. Nothing here blocks the UI.
@MainActor
final class RemoteNotificationService: ObservableObject {
    static let shared = RemoteNotificationService()

    private static let endpoint = URL(string: "https://cuecard-mobile.thisisnsh.workers.dev/v2/notifications")!

    /// Long enough that foregrounding the app repeatedly doesn't hammer the edge,
    /// short enough that pulling a bad notification takes effect within a session.
    ///
    /// Debug builds get a few seconds instead, because the release interval makes
    /// testing one impossible: you edit the worker, background and foreground the
    /// app, and nothing happens for a quarter of an hour.
    #if DEBUG
    private static let minimumRefreshInterval: TimeInterval = 5
    #else
    private static let minimumRefreshInterval: TimeInterval = 15 * 60
    #endif

    @Published private(set) var payload: RemoteNotifications = .empty
    @Published private(set) var dismissedIDs: Set<String> = []

    private let userDefaults = UserDefaults.standard
    /// Deliberately not the old `cuecard_remote_config` key: a cached payload from
    /// a config-era build is a different shape, and this leaves it where it lies.
    private let payloadKey = "cuecard_notifications"
    private let dismissedKey = "cuecard_remote_config_dismissed"

    private var lastRefresh: Date?

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.waitsForConnectivity = false
        // The worker sends `Cache-Control: max-age=300`, which URLSession honours
        // by replaying its stored copy without ever going to the network. We do
        // our own throttling and keep our own copy on disk, so a second layer of
        // caching here buys nothing and hides a freshly deployed notification for
        // another five minutes.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private init() {
        if let data = userDefaults.data(forKey: payloadKey),
           let cached = try? JSONDecoder().decode(RemoteNotifications.self, from: data) {
            payload = cached
        }

        dismissedIDs = Set(userDefaults.stringArray(forKey: dismissedKey) ?? [])
    }

    // MARK: - Fetching

    /// Pull the current list. Safe to call on every launch and every foreground —
    /// it throttles itself, and it never throws.
    func refresh(force: Bool = false) async {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.minimumRefreshInterval {
            return
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let fetched = try JSONDecoder().decode(RemoteNotifications.self, from: data)

            lastRefresh = Date()
            payload = fetched
            userDefaults.set(data, forKey: payloadKey)
            pruneDismissals(against: fetched)
        } catch {
            // Offline, slow, or the worker returned something we couldn't read.
            // Whatever was cached stays in force.
        }
    }

    // MARK: - Notifications

    /// The one notification to show on a surface: highest priority among those
    /// still showable. One at a time — a stack of banners reads as spam.
    func notification(for surface: RemoteNotification.Surface) -> RemoteNotification? {
        payload.notifications
            .filter { $0.surface == surface && isShowable($0) }
            .max { $0.priority < $1.priority }
    }

    func dismiss(_ notification: RemoteNotification) {
        guard notification.dismissible else { return }

        dismissedIDs.insert(notification.id)
        userDefaults.set(Array(dismissedIDs), forKey: dismissedKey)

        Analytics.logEvent("remote_message_dismissed", parameters: ["message_id": notification.id])
    }

    func logImpression(_ notification: RemoteNotification) {
        Analytics.logEvent("remote_message_shown", parameters: [
            "message_id": notification.id,
            "surface": notification.surface.rawValue
        ])
    }

    func logAction(_ action: RemoteNotification.Action, in notification: RemoteNotification) {
        Analytics.logEvent("remote_message_action", parameters: [
            "message_id": notification.id,
            "action": action.kind.rawValue
        ])
    }

    /// Everyone gets the same list from the worker, so all three of these checks
    /// are ours to make: drawable at all, still in date, not already waved away.
    private func isShowable(_ notification: RemoteNotification) -> Bool {
        guard notification.isRenderable else { return false }
        guard !notification.hasExpired() else { return false }
        guard !dismissedIDs.contains(notification.id) else { return false }

        return true
    }

    /// Forget dismissals for notifications the worker has stopped sending, so the
    /// list can't grow forever. Ids are never reused for different copy, so one
    /// that comes back is the same one the user already waved away.
    private func pruneDismissals(against payload: RemoteNotifications) {
        let live = Set(payload.notifications.map(\.id))
        let kept = dismissedIDs.intersection(live)

        guard kept != dismissedIDs else { return }

        dismissedIDs = kept
        userDefaults.set(Array(kept), forKey: dismissedKey)
    }
}
