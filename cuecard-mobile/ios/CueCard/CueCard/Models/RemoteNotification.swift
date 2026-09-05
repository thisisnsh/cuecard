import Foundation

/// The payload behind `GET /v2/notifications` on the mobile worker. Mirrors
/// `src/types.ts` there — change both together.
///
/// Decoding is deliberately forgiving. Anything a newer worker adds that this
/// build doesn't understand is skipped rather than taking the whole payload down
/// with it. The failure mode we want is always "nothing to show", never "app is
/// broken".
struct RemoteNotifications: Equatable {
    var notifications: [RemoteNotification]

    static let empty = RemoteNotifications(notifications: [])
}

/// The build asking for notifications, for the `targets` check below. Fixed for
/// the life of the process.
struct AppBuild: Equatable {
    /// Matched against `Target.platform` as a plain string rather than an enum:
    /// a platform this build doesn't recognise simply never matches, so the
    /// worker can start targeting a new one without breaking anything shipped.
    var platform: String
    /// Marketing version, split into its numeric components. Nil if the bundle
    /// gave us something we couldn't read, in which case no version range
    /// matches and a targeted notification passes this build by.
    var version: [Int]?
    var build: Int?

    static let current = AppBuild(
        platform: "ios",
        version: parseVersionComponents(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
        build: Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
    )
}

/// One thing to show, on one surface.
struct RemoteNotification: Identifiable, Equatable {
    /// Where it's rendered. A surface this build doesn't know about is one it
    /// can't draw, so the notification is dropped in decoding.
    enum Surface: String, Decodable {
        case homeBanner
        case settingsRow
    }

    enum Severity: String, Decodable {
        case info
        case warning
        case critical
    }

    struct Action: Equatable {
        enum Kind: String, Decodable {
            case openURL
            case appStore
            case dismiss
        }

        var kind: Kind
        var label: String
        var url: URL?
    }

    /// One audience a notification is for: a platform, optionally narrowed to a
    /// range of versions or builds. Every bound is inclusive.
    struct Target: Equatable {
        var platform: String
        var minVersion: [Int]?
        var maxVersion: [Int]?
        var minBuild: Int?
        var maxBuild: Int?

        func matches(_ app: AppBuild) -> Bool {
            guard platform == app.platform else { return false }

            // A bound this build can't be measured against doesn't match. A
            // target we can't evaluate should reach nobody rather than everybody
            // — the wrong audience is the whole thing targeting exists to avoid.
            if minVersion != nil || maxVersion != nil {
                guard let version = app.version else { return false }

                if let minVersion, compareVersions(version, minVersion) == .orderedAscending { return false }
                if let maxVersion, compareVersions(version, maxVersion) == .orderedDescending { return false }
            }

            if minBuild != nil || maxBuild != nil {
                guard let build = app.build else { return false }

                if let minBuild, build < minBuild { return false }
                if let maxBuild, build > maxBuild { return false }
            }

            return true
        }
    }

    var id: String
    var surface: Surface
    var severity: Severity = .info
    var priority = 0
    var title: String
    var body: String?
    var actions: [Action] = []
    var dismissible = true
    var targets: [Target] = []
    var expiresAt: Date?

    /// Hosts a notification is allowed to link to, mirrored from the worker. The
    /// worker no longer checks these itself, so this is the only enforcement:
    /// a link anywhere else means the notification is dropped rather than shown.
    static let allowedHosts: Set<String> = [
        "cuecard.dev", "www.cuecard.dev", "apps.apple.com", "github.com"
    ]

    /// Whether this is safe and sensible to draw: a title, no more than two
    /// actions, every link pointing somewhere we recognise, and some way out.
    var isRenderable: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard actions.count <= 2 else { return false }

        for action in actions where action.kind == .openURL {
            guard let host = action.url?.host, Self.allowedHosts.contains(host) else { return false }
        }

        return dismissible || !actions.isEmpty
    }

    /// Whether this build is in the audience. No targets means everyone, which
    /// is what every notification was before targeting existed.
    ///
    /// Enforced here alone: the worker serves one list and leaves the filtering
    /// to us, so a build too old to know about `targets` shows the notification
    /// to everyone regardless.
    func isTargeted(at app: AppBuild = .current) -> Bool {
        guard !targets.isEmpty else { return true }

        return targets.contains { $0.matches(app) }
    }

    /// Expiry is enforced here alone — the worker serves the same list to
    /// everyone and doesn't filter on it.
    func hasExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

// MARK: - Decoding

/// Decodes an element, or nothing at all. Lets one malformed or not-yet-understood
/// notification drop out without discarding the ones around it.
private struct Skipping<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// "1.3.0" -> [1, 3, 0]. Nil for anything that isn't one to four plain numbers
/// separated by dots — a version we can't read is one we won't guess at.
private func parseVersionComponents(_ string: String) -> [Int]? {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(parts.count) else { return nil }

    var components: [Int] = []

    for part in parts {
        guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return nil }
        components.append(value)
    }

    return components
}

/// Component-wise, padding the shorter side with zeroes, so 1.10.0 lands above
/// 1.9.0 — which a plain string comparison gets backwards.
private func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
    for index in 0..<max(lhs.count, rhs.count) {
        let left = index < lhs.count ? lhs[index] : 0
        let right = index < rhs.count ? rhs[index] : 0

        if left != right { return left < right ? .orderedAscending : .orderedDescending }
    }

    return .orderedSame
}

/// The worker writes plain ISO 8601; accept fractional seconds too in case that
/// ever changes underneath us.
private func parseISO8601(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return ISO8601DateFormatter().date(from: string) ?? withFraction.date(from: string)
}

extension RemoteNotifications: Decodable {
    private enum CodingKeys: String, CodingKey {
        case notifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decoded = (try? container.decode([Skipping<RemoteNotification>].self, forKey: .notifications)) ?? []
        notifications = decoded.compactMap(\.value)
    }
}

extension RemoteNotification: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, surface, severity, priority, title, body
        case actions, dismissible, targets, expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // An id, a surface and a title are the notification. Without all three
        // there's nothing to draw or remember, so let the decode fail and skip it.
        id = try container.decode(String.self, forKey: .id)
        surface = try container.decode(Surface.self, forKey: .surface)
        title = try container.decode(String.self, forKey: .title)

        severity = (try? container.decode(Severity.self, forKey: .severity)) ?? .info
        priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
        body = try? container.decode(String.self, forKey: .body)
        dismissible = (try? container.decode(Bool.self, forKey: .dismissible)) ?? true

        if let expiry = try? container.decode(String.self, forKey: .expiresAt) {
            expiresAt = parseISO8601(expiry)
        }

        // An action kind we don't recognise is one we can't carry out, and the
        // action is usually the point — so drop the notification rather than show
        // a card whose button does nothing.
        actions = try container.decodeIfPresent([Action].self, forKey: .actions) ?? []

        // A target we can't read would quietly widen the audience to everyone,
        // so it takes the notification with it for the same reason.
        targets = try container.decodeIfPresent([Target].self, forKey: .targets) ?? []
    }
}

extension RemoteNotification.Action: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, label, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        label = try container.decode(String.self, forKey: .label)
        url = try? container.decode(URL.self, forKey: .url)
    }
}

extension RemoteNotification.Target: Decodable {
    private enum CodingKeys: String, CodingKey {
        case platform, minVersion, maxVersion, minBuild, maxBuild
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        platform = try container.decode(String.self, forKey: .platform)
        minVersion = try Self.version(from: container, forKey: .minVersion)
        maxVersion = try Self.version(from: container, forKey: .maxVersion)
        minBuild = try container.decodeIfPresent(Int.self, forKey: .minBuild)
        maxBuild = try container.decodeIfPresent(Int.self, forKey: .maxBuild)
    }

    /// A version string we can't parse is a bound we can't honour, so this
    /// throws and the notification is skipped — quieter than showing it to the
    /// builds the bound was written to exclude.
    private static func version(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> [Int]? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }

        guard let parsed = parseVersionComponents(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unreadable version: \(raw)"
            )
        }

        return parsed
    }
}
