import SwiftUI
import UIKit
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - Settings

/// The one Settings screen, opened from the library, the editor and both
/// readers. It shows every setting, in groups: the teleprompter's, the
/// camera, the cards', then the rest, each with a line on what it does. The
/// teleprompter and the cards each keep their own text sizes and cue color;
/// the camera, the theme and the language are the same for both.
struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    // Not from the environment: a reader's full screen cover may not pass it on.
    @ObservedObject private var notifications = RemoteNotificationService.shared

    private static let screen = "settings"

    @State private var confirmingLockScreen = false

    private var isCrashlyticsTestEnabled: Bool {
        ProcessInfo.processInfo.environment["CRASHLYTICS_TEST_CRASH"] == "1"
    }

    var body: some View {
        SettingsScreen(screen: Self.screen, title: "Settings") {
            remoteMessageSection

            teleprompterSection
            CameraSection(screen: Self.screen)
            cardsSection
            AppleIntelligenceSection(screen: Self.screen)
            AppleWatchSection(screen: Self.screen)
            LanguageSection(screen: Self.screen)
            AboutSection(screen: Self.screen)
            themeSection
            advancedSection

            diagnosticsSection
        }
        .environmentObject(notifications)
    }

    /// The teleprompter's reading, editor and floating window settings, and
    /// its mirror.
    private var teleprompterSection: some View {
        Section("Teleprompter") {
            AdvancedNumberRow(
                title: "Scroll Speed",
                detail: "Lines that pass each minute.",
                value: $settingsService.settings.linesPerMinute,
                range: TeleprompterSettings.lpmRange,
                unit: "lines/min"
            )

            SizePresetPicker(
                title: "Viewer Text Size",
                detail: "The script as it scrolls.",
                value: $settingsService.settings.fontSize.loggingClicks("settings_text_size", screen: Self.screen),
                presets: TeleprompterSettings.fontSizePresets
            )

            SizePresetPicker(
                title: "Editor Text Size",
                detail: "The script as you write it.",
                value: $settingsService.settings.editorFontSize.loggingClicks("settings_editor_text_size", screen: Self.screen),
                presets: TeleprompterSettings.editorFontSizePresets
            )

            SizePresetPicker(
                title: "Floating Window Text Size",
                detail: "The script over other apps.",
                value: $settingsService.settings.pipFontSize.loggingClicks("settings_floating_text_size", screen: Self.screen),
                presets: TeleprompterSettings.pipFontSizePresets
            )

            AspectRatioPicker(selection: $settingsService.settings.overlayAspectRatio.loggingClicks("settings_floating_layout", screen: Self.screen))

            CueColorPicker(detail: "Cues in your script.",
                           selection: $settingsService.settings.cueColor.loggingClicks("settings_cue_color", screen: Self.screen))

            Toggle(isOn: $settingsService.settings.showsReadingGuide.loggingClicks("settings_reading_guide", screen: Self.screen)) {
                SettingLabel("Reading Guide Line", detail: "Marks the line to read.")
            }

            Toggle(isOn: $settingsService.settings.mirrorsText.loggingClicks("settings_flip_horizontal", screen: Self.screen)) {
                SettingLabel("Flip Horizontally", detail: "For reading off a teleprompter's glass.")
            }

            Toggle(isOn: $settingsService.settings.flipsTextVertically.loggingClicks("settings_flip_vertical", screen: Self.screen)) {
                SettingLabel("Flip Vertically", detail: "For a screen lying the other way up.")
            }
        }
    }

    /// The cards' reading and editor settings, and the Lock Screen, which
    /// cuts long cards short. Turning it on asks first, since anyone who can
    /// see the phone can read the card there.
    private var cardsSection: some View {
        Section {
            SizePresetPicker(
                title: "Viewer Text Size",
                detail: "Each card as you read it.",
                value: $settingsService.settings.cards.fontSize.loggingClicks("settings_cards_text_size", screen: Self.screen),
                presets: TeleprompterSettings.fontSizePresets
            )

            SizePresetPicker(
                title: "Editor Text Size",
                detail: "The deck as you write it.",
                value: $settingsService.settings.cards.editorFontSize.loggingClicks("settings_cards_editor_text_size", screen: Self.screen),
                presets: TeleprompterSettings.editorFontSizePresets
            )

            CueColorPicker(detail: "Cues on your cards.",
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
                SettingLabel("Show on Lock Screen",
                             detail: "Cards over \(CueCards.characterLimit(onLockScreen: true)) characters are cut short there.")
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
    }

    /// Every text size as a number, past the presets, each with its range.
    private var advancedSection: some View {
        AdvancedSection(screen: Self.screen) {
            AdvancedNumberRow(
                title: "Teleprompter Text Size",
                showsRange: true,
                value: $settingsService.settings.fontSize,
                range: TeleprompterSettings.fontSizeRange
            )
            AdvancedNumberRow(
                title: "Teleprompter Editor Text Size",
                showsRange: true,
                value: $settingsService.settings.editorFontSize,
                range: TeleprompterSettings.editorFontSizeRange
            )
            AdvancedNumberRow(
                title: "Floating Window Text Size",
                showsRange: true,
                value: $settingsService.settings.pipFontSize,
                range: TeleprompterSettings.pipFontSizeRange
            )
            AdvancedNumberRow(
                title: "Card Text Size",
                showsRange: true,
                value: $settingsService.settings.cards.fontSize,
                range: TeleprompterSettings.fontSizeRange
            )
            AdvancedNumberRow(
                title: "Cards Editor Text Size",
                showsRange: true,
                value: $settingsService.settings.cards.editorFontSize,
                range: TeleprompterSettings.editorFontSizeRange
            )
        }
    }

    /// One for the whole app.
    private var themeSection: some View {
        Section {
            Picker(selection: $settingsService.settings.themePreference.loggingClicks("settings_theme", screen: Self.screen)) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            } label: {
                SettingLabel("Theme", detail: "Light, dark, or match your iPhone.")
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
                feature("Follow Me AI",
                        detail: "Scrolls the script as you read it aloud.",
                        isOn: $isFollowVoiceEnabled, button: "settings_follow_voice")
                feature("Suggestions AI",
                        detail: "Suggests fixes, cues and formatting.",
                        isOn: $isSuggestionsEnabled, button: "settings_ai_suggestions")
                feature("Help AI",
                        detail: "Answers your questions in Help.",
                        isOn: $isAskAIEnabled, button: "settings_ask_ai")

                Button {
                    AnalyticsEvents.logButtonClick("settings_apple_intelligence_report", screen: screen)
                    openURL(AppLinks.appleIntelligenceReport)
                } label: {
                    Text("Report an Issue")
                }
            } header: {
                Text("Apple Intelligence")
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
                    .lineLimit(1)
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
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            List {
                content
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
            Toggle(isOn: $settingsService.settings.showsTextAboveCamera.loggingClicks("settings_text_above_camera", screen: screen)) {
                SettingLabel("Text Above Camera", detail: "Keeps your words in view over the camera.")
            }

            Toggle(isOn: $settingsService.settings.syncsCamera.loggingClicks("settings_sync_camera", screen: screen)) {
                SettingLabel("Sync with Teleprompter", detail: "Plays and pauses with the camera.")
            }

            Picker(selection: setting(\.resolution, "resolution", shown: settings)) {
                ForEach(options.resolutions, id: \.self) { Text(verbatim: $0.label).tag($0) }
            } label: {
                SettingLabel("Resolution", detail: "The size of each video.")
            }
            Picker(selection: setting(\.frameRate, "frame_rate", shown: settings)) {
                ForEach(options.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            } label: {
                SettingLabel("Frame Rate", detail: "Frames recorded each second.")
            }
            if options.dynamicRanges.count > 1 {
                Picker(selection: setting(\.dynamicRange, "dynamic_range", shown: settings)) {
                    ForEach(options.dynamicRanges, id: \.self) { Text(verbatim: $0.label).tag($0) }
                } label: {
                    SettingLabel("Dynamic Range", detail: "HDR and Log keep more light and color.")
                }
            }
            if options.codecs.count > 1 {
                Picker(selection: setting(\.codec, "codec", shown: settings)) {
                    ForEach(options.codecs, id: \.self) { Text(verbatim: $0.label).tag($0) }
                } label: {
                    SettingLabel("Codec", detail: "How each video is compressed.")
                }
            }
            if options.stabilizations.count > 1 {
                Picker(selection: setting(\.stabilization, "stabilization", shown: settings)) {
                    ForEach(options.stabilizations, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    SettingLabel("Stabilization", detail: "Steadies a shaky picture.")
                }
            }
            if options.isFrontCamera {
                Toggle(isOn: setting(\.mirrorsFrontCamera, "mirror_front_camera", shown: settings)) {
                    SettingLabel("Mirror Front Camera", detail: "Records it as you see it.")
                }
            }
        } header: {
            Text("Camera")
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
                Picker(selection: $settingsService.settings.watch.cardTextSize.loggingClicks("settings_watch_text_size", screen: screen)) {
                    ForEach(WatchCardTextSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                } label: {
                    SettingLabel("Card Text Size", detail: "Cards on your wrist.")
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
            // It's only offered once there is more than one language to
            // choose from, and iOS doesn't tell the app whether it is.
            Button {
                AnalyticsEvents.logButtonClick("language", screen: screen)
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            } label: {
                HStack {
                    SettingLabel("Language", detail: "Needs a second language added in iOS.")
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
        }
    }
}

/// A setting's name, with one short line below it on what it does.
private struct SettingLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The cue color, from a menu of the app's colors, each with a dot of it:
/// a row as tall as the others.
private struct CueColorPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    let detail: LocalizedStringKey
    @Binding var selection: CueColor

    var body: some View {
        Picker(selection: $selection) {
            ForEach(CueColor.allCases) { option in
                Label {
                    Text(option.displayName)
                } icon: {
                    Image(uiImage: Self.dot(option.uiColor(isDarkMode: colorScheme == .dark)))
                }
                .tag(option)
            }
        } label: {
            SettingLabel("Cue Color", detail: detail)
        }
    }

    /// Drawn as an image in its own color: menus draw symbols in the text
    /// color. The dot sits in the middle of a wider image, so the chosen
    /// color, which the row shows with no space of its own, stands clear of
    /// its name.
    private static func dot(_ color: UIColor) -> UIImage {
        let diameter: CGFloat = 14
        let gap: CGFloat = 6
        let size = CGSize(width: diameter + 2 * gap, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: gap, y: 0, width: diameter, height: diameter)).fill()
        }
        .withRenderingMode(.alwaysOriginal)
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

/// The last group: typed sizes for anyone who wants one the presets don't
/// offer, hidden until asked for, and Reset to Defaults. Whether the sizes
/// show is remembered.
private struct AdvancedSection<Fields: View>: View {
    @EnvironmentObject var settingsService: SettingsService
    @AppStorage("settings.showAdvancedSettings") private var showAdvanced = false

    let screen: String
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

            Button("Reset to Defaults") {
                AnalyticsEvents.logButtonClick("reset_to_defaults", screen: screen)
                withAnimation { settingsService.resetSettings() }
            }
            // Greyed out once there's nothing left to reset, so a tap that
            // changes nothing never looks like one that didn't register.
            .disabled(!settingsService.canResetSettings)
        }
    }
}

/// Share, review, and installing on a paired watch without the app.
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
    /// A line below the title on what it sizes.
    var detail: LocalizedStringKey? = nil
    @Binding var value: Int
    let presets: [SettingPreset]

    var body: some View {
        Picker(selection: $value) {
            ForEach(presets, id: \.value) { preset in
                Text(preset.label).tag(preset.value)
            }
            if !presets.contains(where: { $0.value == value }) {
                Text("Custom (\(value))").tag(value)
            }
        } label: {
            if let detail {
                SettingLabel(title, detail: detail)
            } else {
                Text(title)
            }
        }
    }
}

/// The floating window's layout, picked from a menu like Theme.
struct AspectRatioPicker: View {
    @Binding var selection: OverlayAspectRatio

    var body: some View {
        Picker(selection: $selection) {
            ForEach(OverlayAspectRatio.allCases, id: \.self) { ratio in
                Text(ratio.displayName).tag(ratio)
            }
        } label: {
            SettingLabel("Floating Window Layout", detail: "Its shape over other apps.")
        }
    }
}

/// A title with its typed number field at the trailing edge.
struct AdvancedNumberRow: View {
    let title: LocalizedStringKey
    /// A line below the title on what it does.
    var detail: LocalizedStringKey? = nil
    /// Shows the lowest and highest it takes, on a line below the title.
    var showsRange = false
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Left out for text sizes, which read as bare numbers.
    var unit: LocalizedStringKey? = nil

    var body: some View {
        HStack {
            if let detail {
                SettingLabel(title, detail: detail)
            } else if showsRange {
                SettingLabel(title, detail: "\(range.lowerBound) to \(range.upperBound)")
            } else {
                Text(title)
            }
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
