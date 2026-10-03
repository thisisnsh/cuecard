import Foundation
import Testing
@testable import CueCard

@Suite("Timer")
struct TimerTests {
    private let style = TimerStyle.default

    // MARK: - Colors

    @Test func defaultColorsStayTheSame() {
        #expect(style.warningSeconds == 10)
        #expect(style.normalColor == .green)
        #expect(style.warningColor == .yellow)
        #expect(style.overtimeColor == .red)
        #expect(style.countdownColor == .pink)
    }

    @Test(arguments: [
        (60, TeleprompterTimerState.Tint.green),
        (11, .green),
        (10, .yellow),
        (1, .yellow),
        (0, .red),
        (-30, .red),
    ])
    func tintFollowsTimeLeft(_ remaining: Int, _ expected: TeleprompterTimerState.Tint) {
        #expect(style.tint(remaining: remaining, duration: 60) == expected)
    }

    @Test func untimedCountsUpInTheNormalColor() {
        #expect(style.tint(remaining: -100, duration: 0) == .green)
    }

    @Test func colorChangesAtTheWarningAndAtZero() {
        #expect(style.colorChanges(duration: 60) == [50, 60])
        #expect(style.colorChanges(duration: 0) == [])
    }

    @Test func noWarningChangeWhenItIsOffOrLongerThanTheTimer() {
        var noWarning = style
        noWarning.warningSeconds = 0
        #expect(noWarning.colorChanges(duration: 60) == [60])
        #expect(style.colorChanges(duration: 5) == [5])
        #expect(style.colorChanges(duration: 10) == [10])
    }

    @Test func everyCueColorHasATint() {
        let tints = CueColor.allCases.map { TeleprompterTimerState.Tint($0).rawValue }
        #expect(tints == CueColor.allCases.map(\.rawValue))
    }

    // MARK: - Running state

    @Test func runningTimerBeforeTheWarning() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TeleprompterTimerState.running(since: start, duration: 60, style: style,
                                                   at: start.addingTimeInterval(20))
        #expect(state.phase == .playing)
        #expect(state.tint == .green)
        #expect(state.zeroDate == start.addingTimeInterval(60))
        #expect(!state.isOvertime)
    }

    @Test func runningTimerInTheWarning() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TeleprompterTimerState.running(since: start, duration: 60, style: style,
                                                   at: start.addingTimeInterval(55))
        #expect(state.tint == .yellow)
        #expect(!state.isOvertime)
    }

    @Test func runningTimerInOvertime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TeleprompterTimerState.running(since: start, duration: 60, style: style,
                                                   at: start.addingTimeInterval(70))
        #expect(state.tint == .red)
        #expect(state.isOvertime)
    }

    @Test func untimedRunningTimerIsNeverOvertime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = TeleprompterTimerState.running(since: start, duration: 0, style: style,
                                                   at: start.addingTimeInterval(500))
        #expect(state.tint == .green)
        #expect(state.zeroDate == start)
        #expect(!state.isOvertime)
    }

    // MARK: - Paused display

    @Test(arguments: [
        (0, false, "0:00"),
        (65, false, "1:05"),
        (3_725, false, "1:02:05"),
        (5, true, "-0:05"),
        (-5, true, "-0:05"),
    ])
    func pausedDisplay(_ seconds: Int, _ isOvertime: Bool, _ expected: String) {
        let state = TeleprompterTimerState(phase: .paused, tint: .primary, zeroDate: Date(),
                                           pausedSeconds: seconds, isOvertime: isOvertime)
        #expect(state.pausedDisplay == expected)
    }

    // MARK: - Matching

    @Test func smallDriftInTheZeroDateStillMatches() {
        let date = Date()
        let a = TeleprompterTimerState(phase: .playing, tint: .green, zeroDate: date, pausedSeconds: 0, isOvertime: false)
        var b = a
        b.zeroDate = date.addingTimeInterval(0.3)
        #expect(a.matches(b))

        b.zeroDate = date.addingTimeInterval(0.6)
        #expect(!a.matches(b))
    }

    @Test func differentPhaseOrTintDoesNotMatch() {
        let a = TeleprompterTimerState(phase: .playing, tint: .green, zeroDate: Date(), pausedSeconds: 0, isOvertime: false)
        var b = a
        b.phase = .paused
        #expect(!a.matches(b))

        b = a
        b.tint = .red
        #expect(!a.matches(b))
    }

    @Test func timerStateSurvivesEncoding() throws {
        let state = TeleprompterTimerState(phase: .countingDown, tint: .pink,
                                           zeroDate: Date(timeIntervalSince1970: 12_345),
                                           pausedSeconds: 3, isOvertime: false)
        let decoded = try JSONDecoder().decode(TeleprompterTimerState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
