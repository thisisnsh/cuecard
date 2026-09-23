import ActivityKit
import XCTest
@testable import CueCard

@MainActor
final class TeleprompterActivityTests: XCTestCase {
    private var manager: TeleprompterPiPManager { .shared }
    private var activities: [Activity<TeleprompterActivityAttributes>] {
        Activity<TeleprompterActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    override func setUp() async throws {
        manager.cleanup()
        await manager.waitForLiveActivity()
        manager.sceneDidChange(to: .active)
    }

    override func tearDown() async throws {
        manager.cleanup()
        await manager.waitForLiveActivity()
    }

    private func configure(countdown: Int = 0) {
        var settings = TeleprompterSettings.default
        settings.countdownSeconds = countdown
        manager.configure(text: "First line\nSecond line\nThird line", settings: settings,
                          timerDuration: settings.timerDurationSeconds, colorScheme: .dark)
    }

    private func waitForPhase(_ phase: TeleprompterTimerState.Phase,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        // update() submits to ActivityKit; its local content snapshot catches
        // up asynchronously through the system's content-update stream.
        for _ in 0..<100 {
            if activities.first?.content.state.phase == phase { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Activity did not reach \(phase)", file: file, line: line)
    }

    func testOpeningReaderDoesNotStartActivity() async {
        configure()
        await manager.waitForLiveActivity()
        XCTAssertTrue(manager.hasSession)
        XCTAssertTrue(activities.isEmpty)
    }

    func testPlayPauseRestartLifecycle() async throws {
        configure()
        manager.play()
        await manager.waitForLiveActivity()
        let activity = try XCTUnwrap(activities.first, "Play must start a Live Activity in the foreground")
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activity.content.state.phase, .playing)

        manager.pause()
        await manager.waitForLiveActivity()
        XCTAssertEqual(activities.first?.id, activity.id)
        try await waitForPhase(.paused)

        manager.play()
        await manager.waitForLiveActivity()
        XCTAssertEqual(activities.first?.id, activity.id)
        try await waitForPhase(.playing)

        manager.restart()
        await manager.waitForLiveActivity()
        XCTAssertTrue(activities.isEmpty)
    }

    func testCountdownStartsActivityAndCancelEndsIt() async throws {
        configure(countdown: 5)
        manager.play()
        await manager.waitForLiveActivity()
        XCTAssertEqual(try XCTUnwrap(activities.first).content.state.phase, .countingDown)
        manager.pause()
        await manager.waitForLiveActivity()
        XCTAssertTrue(activities.isEmpty)
    }

    func testBackgroundWithoutPiPPausesAndEndsActivity() async throws {
        configure()
        manager.play()
        await manager.waitForLiveActivity()
        XCTAssertFalse(activities.isEmpty)
        // No reader host is attached, so there is no possible PiP presentation.
        manager.sceneDidChange(to: .background)
        await manager.waitForLiveActivity()
        XCTAssertFalse(manager.playback.isPlaying)
        XCTAssertTrue(activities.isEmpty)
    }

    func testCloseEndsActivityAndOpeningAnotherReaderDoesNotRestoreIt() async {
        configure()
        manager.play()
        manager.cleanup()
        await manager.waitForLiveActivity()
        XCTAssertFalse(manager.hasSession)
        XCTAssertTrue(activities.isEmpty)
        configure()
        await manager.waitForLiveActivity()
        XCTAssertTrue(activities.isEmpty)
    }

    func testRapidPausePlayUpdatesStayInOrder() async throws {
        configure()
        manager.play()
        for _ in 0..<5 {
            manager.pause()
            manager.play()
        }
        manager.pause()
        await manager.waitForLiveActivity()
        XCTAssertEqual(activities.count, 1)
        try await waitForPhase(.paused)
    }

    func testPiPTimerFallbackAndDismissal() async throws {
        configure()
        XCTAssertTrue(manager.showsTimerInPiP)
        manager.play()
        await manager.waitForLiveActivity()
        let activity = try XCTUnwrap(activities.first)
        if DeviceModel.hasDynamicIsland {
            XCTAssertFalse(manager.showsTimerInPiP)
        } else {
            XCTAssertTrue(manager.showsTimerInPiP, "Non-island phones must retain the PiP timer")
        }

        await activity.end(nil, dismissalPolicy: .immediate)
        manager.pause()
        manager.play()
        await manager.waitForLiveActivity()
        XCTAssertTrue(manager.showsTimerInPiP, "Dismissing the island must restore the PiP timer")
        XCTAssertTrue(activities.isEmpty, "Playback updates must respect dismissal")
    }

    func testSwitchingToCardsEndsTeleprompter() async {
        configure()
        manager.play()
        CueCardsSession.shared.start(cards: ["Card"], title: "Test", deckID: nil,
                                     cueColor: .default, showOnLockScreen: false)
        await manager.waitForLiveActivity()
        XCTAssertFalse(manager.hasSession)
        XCTAssertTrue(activities.isEmpty)
        CueCardsSession.shared.end()
    }

    func testSkipBackDoesNotRewindTimer() async {
        configure()
        manager.updateReferenceLayout([0, 11, 23])
        manager.play()
        try? await Task.sleep(for: .milliseconds(150))
        manager.pause()
        let elapsed = manager.playback.elapsedTime
        manager.skip(bySeconds: -10)
        XCTAssertEqual(manager.playback.elapsedTime, elapsed)
        XCTAssertEqual(manager.playback.scriptTime, 0)
    }

    func testTimerPhasesAndOvertime() {
        let countdown = TeleprompterActivityController.contentState(
            for: .init(isCountingDown: true, countdownValue: 5), countdownRemaining: 3, timerDuration: 60)
        XCTAssertEqual(countdown.phase, .countingDown)
        XCTAssertEqual(countdown.zeroDate.timeIntervalSinceNow, 3, accuracy: 0.1)

        let untimed = TeleprompterActivityController.contentState(
            for: .init(elapsedTime: 75, isPlaying: true), countdownRemaining: nil, timerDuration: 0)
        XCTAssertEqual(untimed.tint, .primary)
        XCTAssertEqual(untimed.zeroDate.timeIntervalSinceNow, -75, accuracy: 0.1)

        let warning = TeleprompterActivityController.contentState(
            for: .init(elapsedTime: 49), countdownRemaining: nil, timerDuration: 60)
        XCTAssertEqual(warning.tint, .yellow)
        XCTAssertEqual(warning.pausedDisplay, "0:11")

        let overtime = TeleprompterActivityController.contentState(
            for: .init(elapsedTime: 65), countdownRemaining: nil, timerDuration: 60)
        XCTAssertTrue(overtime.isOvertime)
        XCTAssertEqual(overtime.tint, .red)
        XCTAssertEqual(overtime.pausedDisplay, "-0:05")

        let longSession = TeleprompterActivityController.contentState(
            for: .init(elapsedTime: 3661), countdownRemaining: nil, timerDuration: 0)
        XCTAssertEqual(longSession.pausedDisplay, "1:01:01")
    }

    func testNonIslandModelsKeepTheirTimer() {
        for identifier in ["iPhone14,7", "iPhone17,5", "iPhone18,5", "iPad14,1"] {
            XCTAssertFalse(DeviceModel.hasDynamicIsland(identifier: identifier), identifier)
        }
        for identifier in ["iPhone15,2", "iPhone15,4", "iPhone16,1"] {
            XCTAssertTrue(DeviceModel.hasDynamicIsland(identifier: identifier), identifier)
        }
    }
}
