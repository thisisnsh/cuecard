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

    var id: String
    var surface: Surface
    var severity: Severity = .info
    var priority = 0
    var title: String
    var body: String?
    var actions: [Action] = []
    var dismissible = true
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
        case actions, dismissible, expiresAt
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
