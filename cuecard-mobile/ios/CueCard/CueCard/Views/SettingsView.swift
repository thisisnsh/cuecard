import SwiftUI
import UIKit
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - Editor Settings

/// Settings opened from the editor: how the script is set while writing it,
/// plus everything the two Settings screens share.
struct EditorSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var notifications: RemoteNotificationService

    private var isCrashlyticsTestEnabled: Bool {
        ProcessInfo.processInfo.environment["CRASHLYTICS_TEST_CRASH"] == "1"
    }

    var body: some View {
        SettingsScreen(screen: "settings") {
            remoteMessageSection

            Section("Editor") {
                PresetNumberRow(
                    title: "Text Size",
                    value: $settingsService.settings.editorFontSize,
                    presets: TeleprompterSettings.editorFontSizePresets,
                    range: TeleprompterSettings.editorFontSizeRange,
                    unit: "pt"
                )
            }

            AppearanceSection()
            AboutSection(screen: "settings")
            diagnosticsSection
        }
    }

    /// A notice from the worker, if there's one meant for Settings. Quieter than
    /// the home banner — cross-promotion, deprecation notices, that sort of thing.
    @ViewBuilder
    private var remoteMessageSection: some View {
        if let notification = notifications.notification(for: .settingsRow) {
            Section {
                NotificationRow(notification: notification)
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if isCrashlyticsTestEnabled {
            Section {
                Button(role: .destructive) {
                    AnalyticsEvents.logButtonClick("test_crash", screen: "settings")
                    Crashlytics.crashlytics().log("Manually triggered test crash")
                    fatalError("Crashlytics test crash")
                } label: {
                    Text("Trigger Test Crash")
                }
            } footer: {
                Text("This intentionally crashes the app to verify Crashlytics reporting.")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Teleprompter Settings

/// The sizes that are picked over the running script rather than in the list,
/// so the change can be seen as it's made.
enum TeleprompterSizePanel: Identifiable {
    case teleprompter
    case floatingWindow

    var id: Self { self }
}

/// Settings opened from the teleprompter: everything that shapes a run, plus
/// everything the two Settings screens share.
struct TeleprompterSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme

    /// Asks the teleprompter to close Settings and open a size panel over the script.
    let onAdjust: (TeleprompterSizePanel) -> Void

    private static let screen = "teleprompter_settings"

    var body: some View {
        SettingsScreen(screen: Self.screen) {
            Section("Teleprompter") {
                HStack {
                    Text("Start Delay")
                    Spacer()
                    SettingNumberField(
                        value: $settingsService.settings.countdownSeconds,
                        range: TeleprompterSettings.countdownRange,
                        unit: "seconds"
                    )
                }
                .padding(.vertical, 4)

                PresetNumberRow(
                    title: "Scroll Speed",
                    value: $settingsService.settings.linesPerMinute,
                    presets: TeleprompterSettings.speedPresets(fontSize: settingsService.settings.fontSize),
                    range: TeleprompterSettings.lpmRange,
                    unit: "lines/min"
                )

                adjustRow(title: "Text Size", value: "\(settingsService.settings.fontSize) pt", panel: .teleprompter)
            }

            Section {
                adjustRow(title: "Text Size", value: "\(settingsService.settings.pipFontSize) pt", panel: .floatingWindow)
                adjustRow(title: "Dimensions", value: settingsService.settings.overlayAspectRatio.rawValue, panel: .floatingWindow)
            } header: {
                Text("Floating Window")
            } footer: {
                Text("Sizes are picked over your script, so you can see them change.")
            }

            AppearanceSection()
            AboutSection(screen: Self.screen)
        }
    }

    private func adjustRow(title: String, value: String, panel: TeleprompterSizePanel) -> some View {
        Button {
            AnalyticsEvents.logButtonClick(
                panel == .teleprompter ? "adjust_text_size" : "adjust_floating_window",
                screen: Self.screen
            )
            onAdjust(panel)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme).opacity(0.6))
            }
            .contentShape(Rectangle())
        }
    }
}

/// The small panel over the teleprompter for one size. Every change lands in
/// the script behind it — or the floating window preview above it — at once.
struct TeleprompterSizePanelView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme

    let panel: TeleprompterSizePanel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(panel == .teleprompter ? "Text Size" : "Floating Window")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    AnalyticsEvents.logButtonClick("close_size_panel", screen: "teleprompter")
                    onDone()
                }
                .font(.body.weight(.semibold))
            }

            switch panel {
            case .teleprompter:
                PresetNumberRow(
                    title: "Text Size",
                    value: Binding(
                        get: { settingsService.settings.fontSize },
                        set: { settingsService.settings.setFontSize($0) }
                    ),
                    presets: TeleprompterSettings.fontSizePresets,
                    range: TeleprompterSettings.fontSizeRange,
                    unit: "pt"
                )

            case .floatingWindow:
                PresetNumberRow(
                    title: "Text Size",
                    value: $settingsService.settings.pipFontSize,
                    presets: TeleprompterSettings.pipFontSizePresets,
                    range: TeleprompterSettings.pipFontSizeRange,
                    unit: "pt"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Dimensions")
                    Picker("Dimensions", selection: $settingsService.settings.overlayAspectRatio) {
                        ForEach(OverlayAspectRatio.allCases, id: \.self) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.background(for: colorScheme))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// The floating window as it will look, drawn by the same renderer, and
/// redrawn as its size and shape are picked.
struct FloatingWindowPreview: View {
    @ObservedObject var pipManager: TeleprompterPiPManager

    var body: some View {
        // Read so a redraw with new settings refreshes the preview even while
        // playback is still.
        let _ = pipManager.appearanceRevision
        if let image = pipManager.floatingWindowPreview() {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        }
    }
}

// MARK: - Shared Sections

/// The list both Settings screens are built on, with a Done button and a way
/// off the number pad, which has no return key.
private struct SettingsScreen<Content: View>: View {
    @Environment(\.dismiss) var dismiss

    let screen: String
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("done", screen: screen)
                        dismiss()
                    }
                }
            }
            .numberPadDoneButton()
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: screen
            ])
        }
    }
}

/// Theme and cue color. Both are one setting for the whole app, so either
/// Settings screen changes them everywhere.
private struct AppearanceSection: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settingsService.settings.themePreference) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Cue Color")

                HStack(spacing: 14) {
                    ForEach(CueColor.allCases) { option in
                        Button {
                            settingsService.settings.cueColor = option
                        } label: {
                            Circle()
                                .fill(option.color(for: colorScheme))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if option == settingsService.settings.cueColor {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(AppColors.background(for: colorScheme))
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(
                                            AppColors.textPrimary(for: colorScheme),
                                            lineWidth: option == settingsService.settings.cueColor ? 2 : 0
                                        )
                                        .padding(-4)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                    }
                }
                .padding(.vertical, 4)

                Text("Every cue is shown in this color.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
    }
}

/// Share, review and reset, the same on both Settings screens.
///
/// Each row is a plain button whose action does the work. A Link or ShareLink
/// with a tap gesture laid over it for analytics competes with the row for the
/// tap, which is what used to take several tries to get through.
private struct AboutSection: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    let screen: String

    var body: some View {
        Section {
            Button {
                AnalyticsEvents.logButtonClick("share_app", screen: screen)
                presentShareSheet(items: [AppLinks.shareMessage])
            } label: {
                row("Share CueCard", systemImage: "square.and.arrow.up")
            }

            Button {
                AnalyticsEvents.logButtonClick("rate_app", screen: screen)
                openURL(ReviewPromptService.writeReviewURL)
            } label: {
                row("Review on App Store", systemImage: "arrow.up.right")
            }
        }

        Section {
            Button("Reset to Defaults") {
                AnalyticsEvents.logButtonClick("reset_to_defaults", screen: screen)
                withAnimation { settingsService.resetSettings() }
            }
            // Greyed out once there's nothing left to reset, so a tap that
            // changes nothing never looks like one that didn't register.
            .disabled(!settingsService.canResetSettings)
        }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        }
        .contentShape(Rectangle())
    }

    /// Present the system share sheet over whatever is on screen, which here is
    /// the Settings sheet itself.
    private func presentShareSheet(items: [Any]) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
        )
        top.present(controller, animated: true)
    }
}

// MARK: - Number Controls

/// A number setting picked from a row of presets, or typed as any figure in
/// the field beside its title. A typed figure that matches no preset leaves
/// none of them selected.
struct PresetNumberRow: View {
    @Environment(\.colorScheme) var colorScheme

    let title: String
    @Binding var value: Int
    let presets: [SettingPreset]
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                SettingNumberField(value: $value, range: range, unit: unit)
            }

            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    let isSelected = preset.value == value
                    Button {
                        value = preset.value
                    } label: {
                        Text(preset.label)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .foregroundStyle(isSelected
                                             ? AppColors.background(for: colorScheme)
                                             : AppColors.textPrimary(for: colorScheme))
                            .background(
                                Capsule().fill(isSelected
                                               ? AppColors.textPrimary(for: colorScheme)
                                               : AppColors.textSecondary(for: colorScheme).opacity(0.12))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSelected ? "Selected" : "")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A typed number with its unit, in a filled box. The box is what says the
/// figure can be changed, and the unit sits inside it so what is being typed
/// is never read bare.
///
/// A figure within range takes effect as it's typed, so a size can be watched
/// changing. Leaving the field holds whatever is there to the range, and
/// anything that isn't a number leaves the setting alone.
struct SettingNumberField: View {
    @Environment(\.colorScheme) var colorScheme

    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($isFocused)
                .frame(width: 34, alignment: .trailing)
            Text(unit)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.textSecondary(for: colorScheme).opacity(0.12))
        )
        // The unit is part of the target: tapping anywhere in the box
        // starts editing, not only the digits themselves.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { isFocused = true }
        .onAppear { text = String(value) }
        .onChange(of: value) { newValue in
            if !isFocused || Int(text) != newValue { text = String(newValue) }
        }
        .onChange(of: text) { typed in
            guard isFocused, let number = Int(typed.filter(\.isNumber)), range.contains(number) else { return }
            if number != value { value = number }
        }
        .onChange(of: isFocused) { focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        if let typed = Int(text.filter(\.isNumber)) {
            value = TeleprompterSettings.clamp(typed, to: range)
        }
        text = String(value)
    }
}

extension View {
    /// A Done button above the number pad, which has no return key of its own.
    /// Put on a screen once: every field on it shares the one button.
    func numberPadDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

#Preview("Editor") {
    EditorSettingsView()
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteNotificationService.shared)
}

#Preview("Teleprompter") {
    TeleprompterSettingsView(onAdjust: { _ in })
        .environmentObject(SettingsService.shared)
}
