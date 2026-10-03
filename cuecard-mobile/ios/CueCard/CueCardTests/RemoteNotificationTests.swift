import Foundation
import Testing
@testable import CueCard

@Suite("Remote notifications")
struct RemoteNotificationTests {

    private func decode(_ json: String) throws -> RemoteNotifications {
        try JSONDecoder().decode(RemoteNotifications.self, from: Data(json.utf8))
    }

    private func notification(title: String = "Hello", actions: [RemoteNotification.Action] = [],
                              dismissible: Bool = true) -> RemoteNotification {
        RemoteNotification(id: "n", surface: .homeBanner, title: title, actions: actions, dismissible: dismissible)
    }

    // MARK: - Decoding

    @Test func decodesAFullNotification() throws {
        let payload = try decode("""
        {"notifications": [{
            "id": "launch", "surface": "settingsRow", "severity": "warning", "priority": 3,
            "title": "Update", "body": "Something new",
            "actions": [{"kind": "openURL", "label": "Read", "url": "https://cuecard.dev/news"}],
            "dismissible": false,
            "targets": [{"platform": "ios", "minVersion": "1.2", "maxBuild": 40}],
            "expiresAt": "2030-01-01T00:00:00Z"
        }]}
        """)
        let notification = try #require(payload.notifications.first)

        #expect(notification.id == "launch")
        #expect(notification.surface == .settingsRow)
        #expect(notification.severity == .warning)
        #expect(notification.priority == 3)
        #expect(notification.body == "Something new")
        #expect(notification.actions.first?.url == URL(string: "https://cuecard.dev/news"))
        #expect(!notification.dismissible)
        #expect(notification.targets.first?.minVersion == [1, 2])
        #expect(notification.targets.first?.maxBuild == 40)
        #expect(notification.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func fillsInDefaults() throws {
        let notification = try #require(try decode("""
        {"notifications": [{"id": "a", "surface": "homeBanner", "title": "Hi"}]}
        """).notifications.first)

        #expect(notification.severity == .info)
        #expect(notification.priority == 0)
        #expect(notification.body == nil)
        #expect(notification.actions.isEmpty)
        #expect(notification.dismissible)
        #expect(notification.targets.isEmpty)
        #expect(notification.expiresAt == nil)
    }

    @Test func readsExpiryWithFractionalSeconds() throws {
        let notification = try #require(try decode("""
        {"notifications": [{"id": "a", "surface": "homeBanner", "title": "Hi", "expiresAt": "2030-01-01T00:00:00.500Z"}]}
        """).notifications.first)
        #expect(notification.expiresAt == Date(timeIntervalSince1970: 1_893_456_000.5))
    }

    @Test func skipsWhatItCannotUnderstandAndKeepsTheRest() throws {
        let payload = try decode("""
        {"notifications": [
            {"id": "good", "surface": "homeBanner", "title": "Hi"},
            {"id": "no-title", "surface": "homeBanner"},
            {"id": "new-surface", "surface": "watchFace", "title": "Hi"},
            {"id": "new-action", "surface": "homeBanner", "title": "Hi", "actions": [{"kind": "launchRocket", "label": "Go"}]},
            {"id": "bad-version", "surface": "homeBanner", "title": "Hi", "targets": [{"platform": "ios", "minVersion": "1.x"}]},
            {"id": "too-long-version", "surface": "homeBanner", "title": "Hi", "targets": [{"platform": "ios", "minVersion": "1.2.3.4.5"}]},
            {"id": "also-good", "surface": "settingsRow", "title": "Hey", "severity": "apocalyptic"}
        ]}
        """)
        #expect(payload.notifications.map(\.id) == ["good", "also-good"])
        #expect(payload.notifications.last?.severity == .info)
    }

    @Test func malformedPayloadIsEmpty() throws {
        #expect(try decode(#"{"notifications": "nope"}"#) == .empty)
        #expect(try decode("{}") == .empty)
    }

    // MARK: - What can be drawn

    @Test func plainNotificationIsRenderable() {
        #expect(notification().isRenderable)
    }

    @Test func blankTitleIsNotRenderable() {
        #expect(!notification(title: "  \n").isRenderable)
    }

    @Test func moreThanTwoActionsIsNotRenderable() {
        let action = RemoteNotification.Action(kind: .dismiss, label: "OK")
        #expect(notification(actions: [action, action]).isRenderable)
        #expect(!notification(actions: [action, action, action]).isRenderable)
    }

    @Test func notificationWithNoWayOutIsNotRenderable() {
        #expect(!notification(dismissible: false).isRenderable)
        #expect(notification(actions: [.init(kind: .appStore, label: "Update")], dismissible: false).isRenderable)
    }

    @Test(arguments: [
        ("https://cuecard.dev/x", true),
        ("https://WWW.CUECARD.DEV/x", true),
        ("https://apps.apple.com/app/id1", true),
        ("https://github.com/thisisnsh/cuecard", true),
        ("http://cuecard.dev/x", false),
        ("https://evil.com", false),
        ("https://cuecard.dev.evil.com", false),
        ("mailto:support@cuecard.dev", false),
    ])
    func onlyLinksToKnownHostsOverHTTPS(_ link: String, _ allowed: Bool) throws {
        let url = try #require(URL(string: link))
        #expect(RemoteNotification.isAllowedLink(url) == allowed)

        let action = RemoteNotification.Action(kind: .openURL, label: "Open", url: url)
        #expect(notification(actions: [action]).isRenderable == allowed)
    }

    @Test func openURLWithoutAURLIsNotRenderable() {
        #expect(!notification(actions: [.init(kind: .openURL, label: "Open")]).isRenderable)
    }

    // MARK: - Audience

    private let app = AppBuild(platform: "ios", version: [1, 8, 0], build: 22)

    @Test func noTargetsReachesEveryone() {
        #expect(notification().isTargeted(at: app))
    }

    @Test(arguments: [
        (RemoteNotification.Target(platform: "ios"), true),
        (.init(platform: "android"), false),
        (.init(platform: "ios", minVersion: [1, 8]), true),
        (.init(platform: "ios", minVersion: [1, 8, 1]), false),
        (.init(platform: "ios", maxVersion: [1, 8, 0, 0]), true),
        (.init(platform: "ios", maxVersion: [1, 7, 9]), false),
        (.init(platform: "ios", minVersion: [1, 10]), false),
        (.init(platform: "ios", minBuild: 22, maxBuild: 22), true),
        (.init(platform: "ios", minBuild: 23), false),
        (.init(platform: "ios", maxBuild: 21), false),
    ])
    func targetMatchesThisBuild(_ target: RemoteNotification.Target, _ matches: Bool) {
        #expect(target.matches(app) == matches)
    }

    @Test func versionsCompareByNumberNotText() {
        let target = RemoteNotification.Target(platform: "ios", minVersion: [1, 9])
        #expect(target.matches(AppBuild(platform: "ios", version: [1, 10, 0], build: 1)))
    }

    @Test func unreadableBuildMatchesNoBoundedTarget() {
        let unknown = AppBuild(platform: "ios", version: nil, build: nil)
        #expect(RemoteNotification.Target(platform: "ios").matches(unknown))
        #expect(!RemoteNotification.Target(platform: "ios", minVersion: [1]).matches(unknown))
        #expect(!RemoteNotification.Target(platform: "ios", minBuild: 1).matches(unknown))
    }

    @Test func anyMatchingTargetIsEnough() {
        var note = notification()
        note.targets = [.init(platform: "android"), .init(platform: "ios", minVersion: [1])]
        #expect(note.isTargeted(at: app))
    }

    // MARK: - Expiry

    @Test func expiry() {
        let now = Date()
        var note = notification()
        #expect(!note.hasExpired(asOf: now))

        note.expiresAt = now.addingTimeInterval(60)
        #expect(!note.hasExpired(asOf: now))

        note.expiresAt = now
        #expect(note.hasExpired(asOf: now))
    }
}
