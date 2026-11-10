import SwiftUI
import UIKit
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - Settings

/// Where Settings opens: the group for the screen it's opened from.
enum SettingsGroup: Hashable {
    case teleprompter, cards

    /// The group for what's written in that mode.
    init(_ mode: ScriptMode) {
        switch mode {
        case .teleprompter: self = .teleprompter
        case .cards: self = .cards
        }
    }
}

/// The one Settings screen, opened from the library, the editor and both
/// readers. It shows every setting, in groups: the teleprompter's, with its
/// mirror and floating window, the camera, the cards', then the rest. It
/// opens scrolled to the group for the screen it was opened from. The
/// teleprompter and the cards each keep their own text sizes and cue color;
/// the camera, the theme and the language are the same for both.
struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    // Not from the environment: a reader's full screen cover may not pass it on.
    @ObservedObject private var notifications = RemoteNotificationService.shared

    /// The group to show first, or the top.
    var opensAt: SettingsGroup?

    private static let screen = "settings"

    @State private var confirmingLockScreen = false

    private var isCrashlyticsTestEnabled: Bool {
        ProcessInfo.processInfo.environment["CRASHLYTICS_TEST_CRASH"] == "1"
    }

    var body: some View {
        SettingsScreen(screen: Self.screen, title: "Settings", opensAt: opensAt) {
            remoteMessageSection

            teleprompterSections
            CameraSection(screen: Self.screen)
            cardsSection
            AppleIntelligenceSection(screen: Self.screen)
            AppleWatchSection(screen: Self.screen)
            LanguageSection(screen: Self.screen)
            advancedSection
            AboutSection(screen: Self.screen)
            themeSection

            diagnosticsSection
        }
        .environmentObject(notifications)
    }

    /// The teleprompter's reading and editor settings, then its mirror and
    /// floating window.
    @ViewBuilder
    private var teleprompterSections: some View {
        Section("Teleprompter") {
            AdvancedNumberRow(
                title: "Scroll Speed",
                value: $settingsService.settings.linesPerMinute,
                range: TeleprompterSettings.lpmRange,
                unit: "lines/min"
            )

            SizePresetPicker(
                title: "Text Size",
                value: $settingsService.settings.fontSize.loggingClicks("settings_text_size", screen: Self.screen),
                presets: TeleprompterSettings.fontSizePresets
            )

            SizePresetPicker(
                title: "Editor Text Size",
                value: $settingsService.settings.editorFontSize.loggingClicks("settings_editor_text_size", screen: Self.screen),
                presets: TeleprompterSettings.editorFontSizePresets
            )

            ColorSwatchRow(title: "Cue Color",
                           selection: $settingsService.settings.cueColor.loggingClicks("settings_cue_color", screen: Self.screen))

            Toggle("Reading Guide Line", isOn: $settingsService.settings.showsReadingGuide.loggingClicks("settings_reading_guide", screen: Self.screen))
        }
        .id(SettingsGroup.teleprompter)

        Section {
            Toggle("Flip Horizontally", isOn: $settingsService.settings.mirrorsText.loggingClicks("settings_flip_horizontal", screen: Self.screen))

            Toggle("Flip Vertically", isOn: $settingsService.settings.flipsTextVertically.loggingClicks("settings_flip_vertical", screen: Self.screen))
        } header: {
            Text("Mirror")
        } footer: {
            Text("Flip the teleprompter and floating window text to read it off a teleprompter's glass.")
        }

        Section("Floating Window") {
            SizePresetPicker(
                title: "Text Size",
                value: $settingsService.settings.pipFontSize.loggingClicks("settings_floating_text_size", screen: Self.screen),
                presets: TeleprompterSettings.pipFontSizePresets
            )

            AspectRatioPicker(selection: $settingsService.settings.overlayAspectRatio.loggingClicks("settings_floating_layout", screen: Self.screen))
        }
    }

    /// The cards' reading and editor settings, and the Lock Screen. That
    /// keeps cards short enough to fit there, which the toggle's subtitle
    /// says only while it's on. Turning it on asks first, since anyone who
    /// can see the phone can read the card there.
    private var cardsSection: some View {
        Section {
            SizePresetPicker(
                title: "Text Size",
                value: $settingsService.settings.cards.fontSize.loggingClicks("settings_cards_text_size", screen: Self.screen),
                presets: TeleprompterSettings.fontSizePresets
            )

            SizePresetPicker(
                title: "Editor Text Size",
                value: $settingsService.settings.cards.editorFontSize.loggingClicks("settings_cards_editor_text_size", screen: Self.screen),
                presets: TeleprompterSettings.editorFontSizePresets
            )

            ColorSwatchRow(title: "Cue Color",
                           selection: $settingsService.settings.cards.cueColor.loggingClicks("settings_cards_cue_color", screen: Self.screen))

            Toggle(isOn: Binding(
                get: { settingsService.settings.cards.showOnLockScreen },
                set: { isOn in
                    if isOn {
                        confirmingLockScreen = true
                    } else {
                        AnalyticsEvents.logButtonClick("cards_lock_screen_off", screen: Self.screen)
                        settingsService.settings.cards.showOnLockScreen = false
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show on Lock Screen")
                    if settingsService.settings.cards.showOnLockScreen {
                        Text("Anyone who can see your iPhone can read the current card. Cards longer than \(CueCards.characterLimit(onLockScreen: true)) characters will be truncated on the Lock Screen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Show Cards on Lock Screen?", isPresented: $confirmingLockScreen) {
                Button("Cancel", role: .cancel) {
                    AnalyticsEvents.logButtonClick("cards_lock_screen_cancel", screen: Self.screen)
                }
                Button("Show on Lock Screen") {
                    AnalyticsEvents.logButtonClick("cards_lock_screen_on", screen: Self.screen)
                    settingsService.settings.cards.showOnLockScreen = true
                }
            } message: {
                Text("While you read a deck, its title and the current card are shown on the Lock Screen, where anyone who can see your iPhone can read them, even while it's locked.")
            }
        } header: {
            Text("Cards")
        }
        .id(SettingsGroup.cards)
    }

    /// Every text size as a number, past the presets.
    private var advancedSection: some View {
        AdvancedSection(screen: Self.screen, footer: advancedFooter) {
            AdvancedNumberRow(
                title: "Teleprompter Text Size",
                value: $settingsService.settings.fontSize,
                range: TeleprompterSettings.fontSizeRange
            )
            AdvancedNumberRow(
                title: "Teleprompter Editor Text Size",
                value: $settingsService.settings.editorFontSize,
                range: TeleprompterSettings.editorFontSizeRange
            )
            AdvancedNumberRow(
                title: "Floating Window Text Size",
                value: $settingsService.settings.pipFontSize,
                range: TeleprompterSettings.pipFontSizeRange
            )
            AdvancedNumberRow(
                title: "Card Text Size",
                value: $settingsService.settings.cards.fontSize,
                range: TeleprompterSettings.fontSizeRange
            )
            AdvancedNumberRow(
                title: "Cards Editor Text Size",
                value: $settingsService.settings.cards.editorFontSize,
                range: TeleprompterSettings.editorFontSizeRange
            )
        }
    }

    private var advancedFooter: LocalizedStringKey {
        let reading = TeleprompterSettings.fontSizeRange
        let pip = TeleprompterSettings.pipFontSizeRange
        let editor = TeleprompterSettings.editorFontSizeRange
        return "Teleprompter and card text can be set from \(reading.lowerBound) to \(reading.upperBound), floating window text from \(pip.lowerBound) to \(pip.upperBound), and editor text from \(editor.lowerBound) to \(editor.upperBound)."
    }

    /// One for the whole app.
    private var themeSection: some View {
        Section {
            Picker("Theme", selection: $settingsService.settings.themePreference.loggingClicks("settings_theme", screen: Self.screen)) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
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
                    AnalyticsEvents.logButtonClick("test_crash", screen: Self.screen)
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

// MARK: - Shared Sections

/// A switch for each of CueCard's beta Apple Intelligence features, each
/// with a line on what it does, and a way to report a problem with them.
/// Only on an iPhone that has it. Every switch is logged with which way it
/// went.
private struct AppleIntelligenceSection: View {
    let screen: String

    @Environment(\.openURL) private var openURL
    @AppStorage(AppleIntelligenceSetting.suggestionsKey) private var isSuggestionsEnabled = true
    @AppStorage(AppleIntelligenceSetting.askAIKey) private var isAskAIEnabled = true
    @AppStorage(AppleIntelligenceSetting.followVoiceKey) private var isFollowVoiceEnabled = true

    var body: some View {
        if OnDeviceModelAvailability.onDevice != .unsupported {
            Section {
                feature("Suggestions AI",
                        detail: "Suggests spelling fixes, cues and formatting to accept or reject.",
                        isOn: $isSuggestionsEnabled, button: "settings_ai_suggestions")
                feature("Help AI",
                        detail: "Answers your questions about CueCard in Help.",
                        isOn: $isAskAIEnabled, button: "settings_ask_ai")
                feature("Follow Me AI",
                        detail: "Scrolls the script as you read it aloud.",
                        isOn: $isFollowVoiceEnabled, button: "settings_follow_voice")

                Button {
                    AnalyticsEvents.logButtonClick("settings_apple_intelligence_report", screen: screen)
                    openURL(AppLinks.appleIntelligenceReport)
                } label: {
                    Text("Report an Issue")
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Runs on this iPhone with Apple Intelligence.")
            }
        }
    }

    /// A feature's switch, with a line below its name on what it does.
    private func feature(_ title: LocalizedStringKey, detail: LocalizedStringKey,
                         isOn: Binding<Bool>, button: String) -> some View {
        Toggle(isOn: isOn.loggingToggle(button, screen: screen)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                    BetaBadge()
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The list Settings is built on, with a Done button and a way
/// off the number pad, which has no return key.
private struct SettingsScreen<Content: View>: View {
    @Environment(\.dismiss) var dismiss

    let screen: String
    let title: LocalizedStringKey
    let opensAt: SettingsGroup?
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    content
                }
                .onAppear {
                    guard let opensAt else { return }
                    // Once the list is laid out, so the group is there to go to.
                    DispatchQueue.main.async { proxy.scrollTo(opensAt, anchor: .top) }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        AnalyticsEvents.logButtonClick("settings_done", screen: screen)
                        dismiss()
                    }
                }
            }
            .numberPadDoneButton()
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: screen,
                AnalyticsParameterScreenClass: "SettingsView"
            ])
        }
    }
}

/// The floating camera, the same for both modes: whether the script is drawn
/// over it, whether the teleprompter plays and pauses with it, and how it
/// records, as in the Camera app's video settings. No camera is on here, so
/// it offers what either of this iPhone's cameras has, given the other
/// choices, and each camera records the nearest it can. The reader's own
/// choices are kept, for when another one makes them possible again.
private struct CameraSection: View {
    @EnvironmentObject var settingsService: SettingsService
    let screen: String

    @State private var preferred = CameraSettings.saved

    var body: some View {
        let offered = CameraCapture.offered(for: preferred)
        let settings = offered.settings
        let options = offered.options
        Section {
            Toggle("Text Above Camera", isOn: $settingsService.settings.showsTextAboveCamera.loggingClicks("settings_text_above_camera", screen: screen))

            Toggle("Sync with Teleprompter", isOn: $settingsService.settings.syncsCamera.loggingClicks("settings_sync_camera", screen: screen))

            Picker("Resolution", selection: setting(\.resolution, "resolution", shown: settings)) {
                ForEach(options.resolutions, id: \.self) { Text(verbatim: $0.label).tag($0) }
            }
            Picker("Frame Rate", selection: setting(\.frameRate, "frame_rate", shown: settings)) {
                ForEach(options.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            if options.dynamicRanges.count > 1 {
                Picker("Dynamic Range", selection: setting(\.dynamicRange, "dynamic_range", shown: settings)) {
                    ForEach(options.dynamicRanges, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
            }
            if options.codecs.count > 1 {
                Picker("Codec", selection: setting(\.codec, "codec", shown: settings)) {
                    ForEach(options.codecs, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
            }
            if options.stabilizations.count > 1 {
                Picker("Stabilization", selection: setting(\.stabilization, "stabilization", shown: settings)) {
                    ForEach(options.stabilizations, id: \.self) { Text($0.label).tag($0) }
                }
            }
            if options.isFrontCamera {
                Toggle("Mirror Front Camera", isOn: setting(\.mirrorsFrontCamera, "mirror_front_camera", shown: settings))
            }
        } header: {
            Text("Camera")
        } footer: {
            Text("Text Above Camera keeps your script or cards in view over the camera. Sync with Teleprompter plays and pauses the teleprompter and camera together. Each camera records as close to these settings as it can.")
        }
    }

    /// Shows what the cameras will record with, and saves a change to the
    /// reader's own choices, for the next time the camera opens.
    private func setting<Value: Equatable>(_ keyPath: WritableKeyPath<CameraSettings, Value>,
                                           _ name: String, shown: CameraSettings) -> Binding<Value> {
        Binding {
            shown[keyPath: keyPath]
        } set: { value in
            guard value != shown[keyPath: keyPath] else { return }
            AnalyticsEvents.logButtonClick("camera_setting", screen: screen,
                                           parameters: ["setting": name, "value": "\(value)"])
            preferred[keyPath: keyPath] = value
            preferred.save()
        }
    }
}

private extension CameraSettings.Resolution {
    var label: String {
        switch self {
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }
}

private extension CameraSettings.DynamicRange {
    var label: String {
        switch self {
        case .sdr: "SDR"
        case .hdr: "HDR"
        case .appleLog: "Apple Log"
        case .appleLog2: "Apple Log 2"
        }
    }
}

private extension CameraSettings.Codec {
    var label: String {
        switch self {
        case .hevc: "HEVC"
        case .h264: "H.264"
        case .proRes: "ProRes"
        }
    }
}

private extension CameraSettings.Stabilization {
    var label: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .standard: "Standard"
        case .cinematic: "Cinematic"
        case .extended: "Extended"
        }
    }
}

/// How big the watch app draws cards, once it's installed. Installing it is
/// offered with Share and Review.
private struct AppleWatchSection: View {
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject private var watch = WatchSessionService.shared

    let screen: String

    var body: some View {
        if watch.isWatchAppInstalled {
            Section {
                Picker("Card Text Size", selection: $settingsService.settings.watch.cardTextSize.loggingClicks("settings_watch_text_size", screen: screen)) {
                    ForEach(WatchCardTextSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
            } header: {
                Text("Apple Watch")
            }
        }
    }
}

/// The app's language, which lives in the Settings app, and a way to report
/// a mistake in its translation.
private struct LanguageSection: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    let screen: String

    /// The language the app is showing, as its code.
    private var languageCode: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The language the app is showing, named in that language.
    private var languageName: String {
        Locale(identifier: languageCode).localizedString(forIdentifier: languageCode)?.localizedCapitalized ?? languageCode
    }

    var body: some View {
        Section {
            // iOS keeps each app's language in the Settings app, which opens
            // on CueCard's page; choosing one there relaunches the app in it.
            Button {
                AnalyticsEvents.logButtonClick("language", screen: screen)
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            } label: {
                HStack {
                    Text("Language")
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    Spacer()
                    Text(languageName)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .contentShape(Rectangle())
            }

            // English is the original, so there's no translation to get wrong.
            if languageCode != "en" {
                Button {
                    AnalyticsEvents.logButtonClick("report_translation", screen: screen)
                    openURL(AppLinks.translationReport(language: languageCode))
                } label: {
                    HStack {
                        Text("Report a Translation Mistake")
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                        Spacer()
                        Image(systemName: "envelope")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text("Language")
        } footer: {
            // iOS only offers the choice once there is more than one language
            // to choose from, and doesn't tell the app whether it's offering it.
            Text("CueCard's page in the Settings app only shows Language once you've added a second language under General › Language & Region.")
        }
    }
}

/// A row of the app's colors to pick one from.
struct ColorSwatchRow: View {
    @Environment(\.colorScheme) var colorScheme

    let title: LocalizedStringKey
    @Binding var selection: CueColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)

            HStack(spacing: 14) {
                ForEach(CueColor.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        Circle()
                            .fill(option.color(for: colorScheme))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AppColors.background(for: colorScheme))
                                }
                            }
                            .overlay(
                                Circle()
                                    .stroke(AppColors.textPrimary(for: colorScheme),
                                            lineWidth: option == selection ? 2 : 0)
                                    .padding(-4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(Text(title)): \(option.displayName)"))
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Typed sizes for anyone who wants one the presets don't offer. Hidden until
/// asked for, and the choice to show it is remembered across both modes.
private struct AdvancedSection<Fields: View>: View {
    @AppStorage("settings.showAdvancedSettings") private var showAdvanced = false

    let screen: String
    let footer: LocalizedStringKey
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

/// Share, review, installing on a paired watch without the app, and reset.
///
/// Each row is a plain button whose action does the work. A Link or ShareLink
/// with a tap gesture laid over it for analytics competes with the row for the
/// tap, which is what used to take several tries to get through.
private struct AboutSection: View {
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject private var watch = WatchSessionService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    let screen: String

    /// The Watch app on the iPhone, open on its App Store.
    private static let watchAppURL = URL(string: "itms-watchs://")!

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

            if watch.isPaired && !watch.isWatchAppInstalled {
                Button {
                    AnalyticsEvents.logButtonClick("watch_install", screen: screen)
                    openURL(Self.watchAppURL)
                } label: {
                    row("Install on Apple Watch", systemImage: "applewatch")
                }
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

    private func row(_ title: LocalizedStringKey, systemImage: String) -> some View {
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
    let title: LocalizedStringKey
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
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Left out for text sizes, which read as bare numbers.
    var unit: LocalizedStringKey? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            SettingNumberField(value: $value, range: range, unit: unit)
        }
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
    var unit: LocalizedStringKey? = nil

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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.textSecondary(for: colorScheme).opacity(0.12))
        )
        // The unit is part of the target: tapping anywhere in the box
        // starts editing, not only the digits themselves.
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The box is drawn past the text, but takes only the text's height,
        // so its row is as tall as the others.
        .padding(.vertical, -5)
        .onTapGesture { isFocused = true }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused || Int(text) != newValue { text = String(newValue) }
        }
        .onChange(of: text) { _, typed in
            guard isFocused, let number = Int(typed.filter(\.isNumber)), range.contains(number) else { return }
            if number != value { value = number }
        }
        .onChange(of: isFocused) { _, focused in
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
                    AnalyticsEvents.logButtonClick("number_pad_done", screen: "settings")
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteNotificationService.shared)
}
