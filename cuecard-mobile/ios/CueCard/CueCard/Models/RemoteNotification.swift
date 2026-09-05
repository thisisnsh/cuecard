import Foundation

/// The payload behind `GET /v2/config` on the mobile worker.
///
/// Decoding is deliberately forgiving. Every flag defaults to its permissive
/// value, so a build that can't reach the worker behaves exactly as shipped, and
/// anything a newer worker adds that this build doesn't understand is skipped
/// rather than taking the whole payload down with it. The failure mode we want is
/// always "nothing to show", never "app is broken".
struct RemoteConfig: Equatable {
    var flags: Flags
    var messages: [RemoteMessage]

    static let empty = RemoteConfig(flags: Flags(), messages: [])
}

// MARK: - Flags

/// Behaviour the app reads silently. Only `minSupportedVersion` draws any UI.
struct Flags: Equatable {
    var minSupportedVersion = "0.0.0"
    var updateURL: URL?
    var features = Features()
}

/// Kill switches. All on by default — turning one off is the only thing that has
/// any effect, which keeps an unreachable worker from costing anyone a feature.
struct Features: Equatable {
    var pip = true
    var appleSignIn = true
    var googleSignIn = true
}

// MARK: - Messages

/// One thing to show, on one surface.
struct RemoteMessage: Identifiable, Equatable {
    /// Where the message is rendered. A surface this build doesn't know about
    /// means the message can't be drawn at all, so it's dropped in decoding.
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

    /// Narrows the audience. The worker filters on this too; the client re-checks
    /// because a cached payload can outlive the app version it was fetched for.
    struct Match: Equatable {
        var platforms: [String]?
        var minVersion: String?
        var maxVersion: String?
        var minBuild: Int?
        var locales: [String]?
    }

    var id: String
    var surface: Surface
    var severity: Severity = .info
    var priority = 0
    var title: String
    var body: String?
    var actions: [Action] = []
    var dismissible = true
    var expiresAt: Date?
    var rolloutPercent = 100
    var match: Match?

    /// Hosts a message is allowed to link to, mirrored from the worker. A link
    /// anywhere else means someone got at the response, so the message is dropped
    /// rather than shown without its action.
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

    func hasExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

// MARK: - Targeting

extension RemoteMessage.Match {
    func admits(platform: String, version: String, build: Int, locale: String) -> Bool {
        if let platforms, !platforms.contains(platform) { return false }
        if let minVersion, AppVersion.compare(version, minVersion) == .orderedAscending { return false }
        if let maxVersion, AppVersion.compare(version, maxVersion) == .orderedDescending { return false }
        if let minBuild, build < minBuild { return false }

        // Language alone: "en" covers en-US, en-GB and the rest.
        if let locales {
            let language = locale.split(separator: "-").first.map { $0.lowercased() } ?? locale.lowercased()
            let admitted = locales.contains { $0.split(separator: "-").first?.lowercased() == language }
            if !admitted { return false }
        }

        return true
    }
}

// MARK: - Version numbers

enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Compare two dotted versions numerically. Missing components count as zero,
    /// so "1.2" and "1.2.0" are the same version.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }

        return .orderedSame
    }
}

// MARK: - Decoding

/// Decodes an element, or nothing at all. Lets one malformed or not-yet-understood
/// message drop out without discarding the messages around it.
private struct Skipping<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// The worker writes plain ISO 8601; accept fractional seconds too in case that
/// ever changes underneath us.
private func parseISO8601(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return ISO8601DateFormatter().date(from: string) ?? withFraction.date(from: string)
}

extension RemoteConfig: Decodable {
    private enum CodingKeys: String, CodingKey {
        case flags, messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flags = (try? container.decode(Flags.self, forKey: .flags)) ?? Flags()

        let decoded = (try? container.decode([Skipping<RemoteMessage>].self, forKey: .messages)) ?? []
        messages = decoded.compactMap(\.value)
    }
}

extension Flags: Decodable {
    private enum CodingKeys: String, CodingKey {
        case minSupportedVersion, updateURL, features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minSupportedVersion = (try? container.decode(String.self, forKey: .minSupportedVersion)) ?? "0.0.0"
        updateURL = try? container.decode(URL.self, forKey: .updateURL)
        features = (try? container.decode(Features.self, forKey: .features)) ?? Features()
    }
}

extension Features: Decodable {
    private enum CodingKeys: String, CodingKey {
        case pip, appleSignIn, googleSignIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pip = (try? container.decode(Bool.self, forKey: .pip)) ?? true
        appleSignIn = (try? container.decode(Bool.self, forKey: .appleSignIn)) ?? true
        googleSignIn = (try? container.decode(Bool.self, forKey: .googleSignIn)) ?? true
    }
}

extension RemoteMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, surface, severity, priority, title, body
        case actions, dismissible, expiresAt, rolloutPercent, match
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // An id, a surface and a title are the message. Without all three there's
        // nothing to draw or remember, so let the decode fail and skip it.
        id = try container.decode(String.self, forKey: .id)
        surface = try container.decode(Surface.self, forKey: .surface)
        title = try container.decode(String.self, forKey: .title)

        severity = (try? container.decode(Severity.self, forKey: .severity)) ?? .info
        priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
        body = try? container.decode(String.self, forKey: .body)
        dismissible = (try? container.decode(Bool.self, forKey: .dismissible)) ?? true
        rolloutPercent = (try? container.decode(Int.self, forKey: .rolloutPercent)) ?? 100
        match = try? container.decode(Match.self, forKey: .match)

        if let expiry = try? container.decode(String.self, forKey: .expiresAt) {
            expiresAt = parseISO8601(expiry)
        }

        // An action kind we don't recognise is one we can't carry out, and the
        // action is usually the point of the message — so drop the message rather
        // than show a card whose button does nothing.
        actions = try container.decodeIfPresent([Action].self, forKey: .actions) ?? []
    }
}

extension RemoteMessage.Action: Decodable {
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

extension RemoteMessage.Match: Decodable {
    private enum CodingKeys: String, CodingKey {
        case platforms, minVersion, maxVersion, minBuild, locales
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platforms = try? container.decode([String].self, forKey: .platforms)
        minVersion = try? container.decode(String.self, forKey: .minVersion)
        maxVersion = try? container.decode(String.self, forKey: .maxVersion)
        minBuild = try? container.decode(Int.self, forKey: .minBuild)
        locales = try? container.decode([String].self, forKey: .locales)
    }
}
