import SwiftUI
import FirebaseAnalytics

/// The timer for the mode being written in: how long it runs, when it warns,
/// and the countdown before it. Its colors are in Settings.
struct TimerSheet: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private static let screen = "timer"

    private var settings: TeleprompterSettings { settingsService.settings }
    private var duration: Int { settings.activeTimerMinutes * 60 + settings.activeTimerSeconds }
    private var style: Binding<TimerStyle> { $settingsService.settings.activeTimerStyle }
    /// Only the teleprompter has a countdown.
    private var isTeleprompter: Bool { settings.scriptMode == .teleprompter }

    private var timeFooter: String {
        var lines = [duration == 0
            ? "With no time set, the timer counts up from 0:00."
            : "Warn At is the time left when the timer turns the warning color. 0:00 turns it off."]
        if isTeleprompter {
            lines.append("Countdown is the time before the script starts scrolling.")
        }
        return lines.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preview
                        .listRowInsets(EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12))
                } footer: {
                    Text("Change the timer's colors in Settings.")
                }

                Section {
                    durationRow
                    if duration > 1 {
                        warningRow
                    }
                    if isTeleprompter {
                        countdownRow
                    }
                } footer: {
                    Text(timeFooter)
                }

            }
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: Self.screen)
                        dismiss()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: duration == 0)
            .onChange(of: duration) { _, _ in clampWarning() }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: Self.screen,
                AnalyticsParameterScreenClass: "TimerSheet"
            ])
        }
    }

    /// The timer at each of its colors: at the start, at the warning, and at
    /// zero. Untimed, just the count up from zero.
    private var preview: some View {
        HStack(spacing: 0) {
            if duration == 0 {
                stage("Counts Up", seconds: 0, tint: style.wrappedValue.tint(remaining: 0, duration: 0))
            } else {
                let style = style.wrappedValue
                stage("Start", seconds: duration, tint: .init(style.normalColor))
                if style.warningSeconds > 0 {
                    stage("Warning", seconds: style.warningSeconds, tint: .init(style.warningColor))
                }
                stage("Time's Up", seconds: 0, tint: .init(style.overtimeColor))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stage(_ title: String, seconds: Int, tint: TeleprompterTimerState.Tint) -> some View {
        VStack(spacing: 4) {
            Text(Self.format(seconds))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.color(for: colorScheme))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var durationRow: some View {
        timeRow("Duration",
                minutes: $settingsService.settings.activeTimerMinutes, minuteRange: 0...59,
                seconds: $settingsService.settings.activeTimerSeconds, secondRange: 0...59)
    }

    /// The time left to warn at, always short of the duration. 0:00 is off.
    private var warningRow: some View {
        let latest = max(duration - 1, 0)
        let warning = style.wrappedValue.warningSeconds
        let minutes = Binding(
            get: { warning / 60 },
            set: { style.wrappedValue.warningSeconds = min($0 * 60 + warning % 60, latest) }
        )
        let seconds = Binding(
            get: { warning % 60 },
            set: { style.wrappedValue.warningSeconds = min(warning / 60 * 60 + $0, latest) }
        )
        let secondsRange = warning / 60 == latest / 60 ? 0...(latest % 60) : 0...59
        return timeRow("Warn At", minutes: minutes, minuteRange: 0...(latest / 60),
                       seconds: seconds, secondRange: secondsRange)
    }

    /// Seconds of countdown before the script scrolls. Zero starts at once.
    private var countdownRow: some View {
        HStack(spacing: 4) {
            Text("Countdown")
            Spacer()
            wheel("Countdown seconds", selection: $settingsService.settings.countdownSeconds,
                  range: TeleprompterSettings.countdownRange) { "\($0)" }
            unit("sec")
        }
        .frame(height: 88)
    }

    /// Keep the warning short of a duration that was shortened under it.
    private func clampWarning() {
        let latest = max(duration - 1, 0)
        if style.wrappedValue.warningSeconds > latest {
            style.wrappedValue.warningSeconds = latest
        }
    }

    /// A title, and small minute and second wheels beside it.
    private func timeRow(_ title: String,
                         minutes: Binding<Int>, minuteRange: ClosedRange<Int>,
                         seconds: Binding<Int>, secondRange: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            wheel(title + " minutes", selection: minutes, range: minuteRange) { "\($0)" }
            unit("min")
            wheel(title + " seconds", selection: seconds, range: secondRange) { String(format: "%02d", $0) }
            unit("sec")
        }
        .frame(height: 88)
    }

    /// What a wheel beside it counts, lined up across the rows.
    private func unit(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            .frame(width: 28, alignment: .leading)
    }

    private func wheel(_ label: String, selection: Binding<Int>, range: ClosedRange<Int>,
                       text: @escaping (Int) -> String) -> some View {
        Picker(label, selection: selection) {
            ForEach(Array(range), id: \.self) { value in
                Text(text(value)).tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 56, height: 88)
        .clipped()
    }

    /// Time the way the timer button shows it: 1:00, 0:10.
    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
