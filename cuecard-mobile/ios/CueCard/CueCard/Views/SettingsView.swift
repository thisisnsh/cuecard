import AppIntents
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
            WhatsNewSection(screen: "settings")
            remoteMessageSection

            Section("Editor") {
                SizePresetPicker(
                    title: "Text Size",
                    value: $settingsService.settings.editorFontSize,
                    presets: TeleprompterSettings.editorFontSizePresets
                )
            }

            PlaybackControlsSection(screen: "settings")

            AppleWatchSection(screen: "settings")

            AppearanceSection()

            AdvancedSection(
                screen: "settings",
                footer: "Text size can be set from \(TeleprompterSettings.editorFontSizeRange.lowerBound) to \(TeleprompterSettings.editorFontSizeRange.upperBound)."
            ) {
                AdvancedNumberRow(
                    title: "Text Size",
                    value: $settingsService.settings.editorFontSize,
                    range: TeleprompterSettings.editorFontSizeRange
                )
            }

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

/// Settings opened from the teleprompter: everything that shapes a run, plus
/// everything the two Settings screens share.
struct TeleprompterSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService

    private static let screen = "teleprompter_settings"

    var body: some View {
        SettingsScreen(screen: Self.screen) {
            WhatsNewSection(screen: Self.screen)

            Section("Teleprompter") {
                AdvancedNumberRow(
                    title: "Start Delay",
                    value: $settingsService.settings.countdownSeconds,
                    range: TeleprompterSettings.countdownRange,
                    unit: "seconds"
                )

                AdvancedNumberRow(
                    title: "Scroll Speed",
                    value: $settingsService.settings.linesPerMinute,
                    range: TeleprompterSettings.lpmRange,
                    unit: "lines/min"
                )

                SizePresetPicker(
                    title: "Text Size",
                    value: $settingsService.settings.fontSize,
                    presets: TeleprompterSettings.fontSizePresets
                )
            }

            Section("Floating Window") {
                SizePresetPicker(
                    title: "Text Size",
                    value: $settingsService.settings.pipFontSize,
                    presets: TeleprompterSettings.pipFontSizePresets
                )

                AspectRatioPicker(selection: $settingsService.settings.overlayAspectRatio)
            }

            PlaybackControlsSection(screen: Self.screen)

            AppearanceSection()

            AdvancedSection(screen: Self.screen, footer: advancedFooter) {
                AdvancedNumberRow(
                    title: "Teleprompter Text Size",
                    value: $settingsService.settings.fontSize,
                    range: TeleprompterSettings.fontSizeRange
                )
                AdvancedNumberRow(
                    title: "Floating Window Text Size",
                    value: $settingsService.settings.pipFontSize,
                    range: TeleprompterSettings.pipFontSizeRange
                )
            }

            AboutSection(screen: Self.screen)
        }
    }

    private var advancedFooter: String {
        let prompter = TeleprompterSettings.fontSizeRange
        let pip = TeleprompterSettings.pipFontSizeRange
        return "Teleprompter text can be set from \(prompter.lowerBound) to \(prompter.upperBound), "
            + "and floating window text from \(pip.lowerBound) to \(pip.upperBound)."
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

/// Opens this version's new features again. Left out when there are none for it.
private struct WhatsNewSection: View {
    @ObservedObject private var whatsNew = WhatsNewService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isPresented = false

    let screen: String

    var body: some View {
        if let release = whatsNew.release {
            Section {
                Button {
                    AnalyticsEvents.logButtonClick("whats_new", screen: screen)
                    withoutPresentationAnimation { isPresented = true }
                } label: {
                    HStack {
                        Text("What's New")
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                    .contentShape(Rectangle())
                }
                .whatsNewCover(isPresented: $isPresented, release: release, version: whatsNew.version)
            }
        }
    }
}

/// Where play/pause and back 10 seconds can be reached without opening the
/// app, and how to set each up. Only what this iPhone has is listed, and none
/// of it before iOS 17, which the intents need.
private struct PlaybackControlsSection: View {
    @Environment(\.colorScheme) var colorScheme

    let screen: String

    var body: some View {
        if #available(iOS 17.0, *) {
            Section {
                if TeleprompterActivityController.hasDynamicIsland {
                    row("Dynamic Island", systemImage: "capsule.fill",
                        detail: "While the floating window is up, touch and hold the timer in the island.")
                }
                if DeviceModel.hasActionButton {
                    row("Action Button", systemImage: "button.vertical.left.press",
                        detail: "In the Settings app, go to Action Button, choose Shortcut, and pick Play or Pause under CueCard.")
                }
                if #available(iOS 18.0, *) {
                    row("Control Center", systemImage: "switch.2",
                        detail: "Open Control Center, tap +, then Add a Control, and search for CueCard.")
                }
                row("Siri", systemImage: "waveform",
                    detail: "Say \u{201C}Play or pause CueCard\u{201D} or \u{201C}Skip back in CueCard.\u{201D}")

                ShortcutsLink {
                    AnalyticsEvents.logButtonClick("shortcuts_link", screen: screen)
                }
                .shortcutsLinkStyle(colorScheme == .dark ? .dark : .light)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: {
                Text("Playback Controls")
            } footer: {
                Text("Play, pause, or go back \(TeleprompterRemoteCommand.skipBackSeconds) seconds without opening CueCard while a script is open in the teleprompter.")
            }
        }
    }

    private func row(_ title: String, systemImage: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
        .padding(.vertical, 2)
    }
}

/// Which saved notes are on the watch, to read there with the iPhone out of
/// reach, or a way to install the watch app while a watch is paired without
/// it. Left out when no watch is paired.
private struct AppleWatchSection: View {
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject private var watch = WatchSessionService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    let screen: String

    /// The Watch app on the iPhone, open on its App Store.
    private static let watchAppURL = URL(string: "itms-watchs://")!

    var body: some View {
        if watch.isWatchAppInstalled {
            Section {
                if settingsService.savedNotes.isEmpty {
                    Text("Save a note to put it on your watch.")
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                } else {
                    ForEach(settingsService.savedNotes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                        Toggle(isOn: Binding(
                            get: { settingsService.watchNoteIDs.contains(note.id) },
                            set: { isOn in
                                AnalyticsEvents.logButtonClick(isOn ? "watch_add_note" : "watch_remove_note",
                                                               screen: screen)
                                settingsService.setOnWatch(isOn, noteID: note.id)
                            }
                        )) {
                            Text(note.title)
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        }
                    }
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Notes you turn on stay on your watch, to swipe through card by card even without your iPhone. A note splits into cards where it has separators.\n\n\(WatchTips.returnToClock)")
            }
        } else if watch.isPaired {
            Section {
                Button {
                    AnalyticsEvents.logButtonClick("watch_install", screen: screen)
                    openURL(Self.watchAppURL)
                } label: {
                    HStack {
                        Text("Install on Apple Watch")
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        Spacer()
                        Image(systemName: "applewatch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                    .contentShape(Rectangle())
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Opens the Watch app. Under Available Apps, tap Install next to CueCard. Then move through cards and control the teleprompter from your wrist.")
            }
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

/// Typed sizes for anyone who wants one the presets don't offer. Hidden until
/// asked for, and the choice to show it is remembered across both screens.
private struct AdvancedSection<Fields: View>: View {
    @AppStorage("settings.showAdvancedSettings") private var showAdvanced = false

    let screen: String
    let footer: String
    @ViewBuilder let fields: Fields

    var body: some View {
        Section {
            if showAdvanced {
                fields
            }

            Button(showAdvanced ? "Hide Advanced Settings" : "Show Advanced Settings") {
                AnalyticsEvents.logButtonClick(showAdvanced ? "hide_advanced" : "show_advanced", screen: screen)
                // Leave the field being typed in first, so its figure is
                // committed before hiding takes the field away.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                DispatchQueue.main.async {
                    withAnimation { showAdvanced.toggle() }
                }
            }
        } footer: {
            if showAdvanced {
                Text(footer)
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

/// A text size picked from a menu of presets, the same kind of row as Theme.
/// A size typed in Advanced that matches no preset shows as its own entry, so
/// the row never reads blank.
struct SizePresetPicker: View {
    let title: String
    @Binding var value: Int
    let presets: [SettingPreset]

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(presets, id: \.value) { preset in
                Text(preset.label).tag(preset.value)
            }
            if !presets.contains(where: { $0.value == value }) {
                Text("Custom (\(value))").tag(value)
            }
        }
    }
}

/// The floating window's layout, picked from a menu like Theme.
struct AspectRatioPicker: View {
    @Binding var selection: OverlayAspectRatio

    var body: some View {
        Picker("Layout", selection: $selection) {
            ForEach(OverlayAspectRatio.allCases, id: \.self) { ratio in
                Text(ratio.displayName).tag(ratio)
            }
        }
    }
}

/// A title with its typed number field at the trailing edge.
struct AdvancedNumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Left out for text sizes, which read as bare numbers.
    var unit: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            SettingNumberField(value: $value, range: range, unit: unit)
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
    var unit: String? = nil

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
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
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
    TeleprompterSettingsView()
        .environmentObject(SettingsService.shared)
}
