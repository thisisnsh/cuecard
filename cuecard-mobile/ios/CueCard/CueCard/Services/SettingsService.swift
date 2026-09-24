import Foundation
import SwiftUI
import UIKit

/// Theme preference for the app
enum ThemePreference: String, Codable, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The Small / Medium / Large text sizes settings used to be saved as. Only
/// read, to carry an older choice over to the point size it stood for.
private enum LegacyFontSizePreset: String, Codable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var fontSize: Int {
        switch self {
        case .small: return 20
        case .medium: return 28
        case .large: return 40
        }
    }

    var pipFontSize: Int {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 22
        }
    }
}

/// Overlay dimension ratio presets
enum OverlayAspectRatio: String, Codable, CaseIterable {
    case ratio16x9 = "16:9"
    case ratio4x3 = "4:3"
    case ratio1x1 = "1:1"

    var ratio: CGFloat {
        switch self {
        case .ratio16x9:
            return 16.0 / 9.0
        case .ratio4x3:
            return 4.0 / 3.0
        case .ratio1x1:
            return 1.0
        }
    }

    /// The name Settings shows for this layout. The raw value is what's saved,
    /// so it stays the bare ratio.
    var displayName: String {
        switch self {
        case .ratio16x9: return "Rectangle 16:9"
        case .ratio4x3: return "Rectangle 4:3"
        case .ratio1x1: return "Square 1:1"
        }
    }
}

/// One of the named sizes a text size setting offers in its menu.
struct SettingPreset {
    let label: String
    let value: Int
}

/// How much bigger text needs to be on this device to look the size it does
/// on a phone. Sizes are designed on a 393-point-wide iPhone, and every other
/// screen is measured by its short side, so turning the device doesn't change them.
enum ScreenTextScale {
    private static let referenceWidth: Double = 393

    /// Grows with the screen, so a line holds about as many words on an iPad as
    /// on a phone. What the teleprompter needs, since it's read from a distance.
    static let teleprompter: Double = {
        let bounds = UIScreen.main.bounds
        return Double(min(bounds.width, bounds.height)) / referenceWidth
    }()

    /// Grows half as fast: the editor is read up close, where a phone's size
    /// times two is more than anyone writes in.
    static let editor: Double = 1 + (teleprompter - 1) / 2

    static func scaled(_ size: Int, by scale: Double) -> Int {
        Int((Double(size) * scale).rounded())
    }

    static func scaled(_ range: ClosedRange<Int>, by scale: Double) -> ClosedRange<Int> {
        scaled(range.lowerBound, by: scale)...scaled(range.upperBound, by: scale)
    }

    static func scaled(_ presets: [SettingPreset], by scale: Double) -> [SettingPreset] {
        presets.map { SettingPreset(label: $0.label, value: scaled($0.value, by: scale)) }
    }
}

/// Cards mode's own values for everything it has in common with the
/// teleprompter, so setting one up never changes the other.
struct CardsSettings: Codable, Equatable {
    /// Text size in the cards editor, in points.
    var editorFontSize: Int
    /// Text size on a card being read, in points.
    var fontSize: Int
    /// The color every `[cue …]` on a card is drawn in.
    var cueColor: CueColor
    var timerMinutes: Int
    var timerSeconds: Int
    /// A deck being read is on the Lock Screen too, as a Live Activity. It
    /// keeps cards short enough to read there.
    var showOnLockScreen: Bool

    var timerDurationSeconds: Int {
        timerMinutes * 60 + timerSeconds
    }

    /// Characters a card holds before the editor marks the rest as too long.
    var characterLimit: Int {
        CueCards.characterLimit(onLockScreen: showOnLockScreen)
    }

    init(editorFontSize: Int, fontSize: Int, cueColor: CueColor,
         timerMinutes: Int, timerSeconds: Int, showOnLockScreen: Bool = true) {
        self.editorFontSize = editorFontSize
        self.fontSize = fontSize
        self.cueColor = cueColor
        self.timerMinutes = timerMinutes
        self.timerSeconds = timerSeconds
        self.showOnLockScreen = showOnLockScreen
    }

    private enum CodingKeys: String, CodingKey {
        case editorFontSize, fontSize, cueColor, timerMinutes, timerSeconds, showOnLockScreen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editorFontSize = try container.decode(Int.self, forKey: .editorFontSize)
        fontSize = try container.decode(Int.self, forKey: .fontSize)
        cueColor = try container.decode(CueColor.self, forKey: .cueColor)
        timerMinutes = try container.decode(Int.self, forKey: .timerMinutes)
        timerSeconds = try container.decode(Int.self, forKey: .timerSeconds)
        showOnLockScreen = try container.decodeIfPresent(Bool.self, forKey: .showOnLockScreen) ?? true
    }
}

/// Settings for the teleprompter
struct TeleprompterSettings: Codable, Equatable {
    /// Text size in the script editor, in points.
    var editorFontSize: Int
    /// Text size in the in-app prompter, in points.
    var fontSize: Int
    /// Text size in the floating prompter, in points of its 320-point-wide page.
    var pipFontSize: Int
    var overlayAspectRatio: OverlayAspectRatio
    var scrollSpeed: Double
    /// Scroll speed, in lines of the script as the teleprompter renders them.
    var linesPerMinute: Int
    var timerMinutes: Int
    var timerSeconds: Int
    var themePreference: ThemePreference
    var countdownSeconds: Int
    /// The color every `[cue …]` in every script is drawn in.
    var cueColor: CueColor
    /// What the editor writes and the Play button opens. Chosen on the home
    /// screen, like the timer.
    var scriptMode: ScriptMode
    /// How the watch app shows cards.
    var watch: WatchSettings
    /// Cards mode's own text sizes, cue color and timer.
    var cards: CardsSettings

    static let `default` = TeleprompterSettings(
        editorFontSize: ScreenTextScale.scaled(16, by: ScreenTextScale.editor),
        fontSize: ScreenTextScale.scaled(28, by: ScreenTextScale.teleprompter),
        pipFontSize: 16,
        overlayAspectRatio: .ratio16x9,
        scrollSpeed: 1.0,
        linesPerMinute: 34,
        timerMinutes: 1,
        timerSeconds: 0,
        themePreference: .system,
        countdownSeconds: 5,
        cueColor: .default,
        scriptMode: .teleprompter,
        watch: .default,
        cards: CardsSettings(
            editorFontSize: ScreenTextScale.scaled(16, by: ScreenTextScale.editor),
            fontSize: ScreenTextScale.scaled(28, by: ScreenTextScale.teleprompter),
            cueColor: .default,
            timerMinutes: 1,
            timerSeconds: 0
        )
    )

    /// Scroll speed range (multiplier)
    static let scrollSpeedRange = 0.5...3.0

    /// The speeds a typed lines-a-minute figure is held to.
    static let lpmRange = 1...300

    /// The countdowns a typed start delay is held to.
    static let countdownRange = 0...60

    /// The editor's text sizes, in points, a typed size is held to. Sized for
    /// this screen, like its presets.
    static let editorFontSizeRange = ScreenTextScale.scaled(12...40, by: ScreenTextScale.editor)

    /// The in-app text sizes, in points, a typed size is held to. Sized for
    /// this screen, like its presets.
    static let fontSizeRange = ScreenTextScale.scaled(16...72, by: ScreenTextScale.teleprompter)

    /// The floating prompter's text sizes, in points, a typed size is held to.
    /// Its page is 320 points wide on every device, so these aren't scaled.
    static let pipFontSizeRange = 10...32

    /// The editor's text sizes offered as presets, around the 16 pt it has
    /// always been set in on a phone, and scaled up for bigger screens.
    static let editorFontSizePresets = ScreenTextScale.scaled([
        SettingPreset(label: "XS", value: 12),
        SettingPreset(label: "S", value: 14),
        SettingPreset(label: "M", value: 16),
        SettingPreset(label: "L", value: 20),
        SettingPreset(label: "XL", value: 24),
    ], by: ScreenTextScale.editor)

    /// The in-app text sizes offered as presets, as a phone sees them and scaled
    /// to this screen. Past 40 pt a phone line holds fewer than three words, so
    /// the larger sizes are left to Advanced.
    static let fontSizePresets = ScreenTextScale.scaled([
        SettingPreset(label: "XS", value: 20),
        SettingPreset(label: "S", value: 24),
        SettingPreset(label: "M", value: 28),
        SettingPreset(label: "L", value: 34),
        SettingPreset(label: "XL", value: 40),
    ], by: ScreenTextScale.teleprompter)

    /// The floating prompter's text sizes offered as presets, spaced like the
    /// in-app ones around its own default. Not scaled: see `pipFontSizeRange`.
    static let pipFontSizePresets = [
        SettingPreset(label: "XS", value: 12),
        SettingPreset(label: "S", value: 14),
        SettingPreset(label: "M", value: 16),
        SettingPreset(label: "L", value: 19),
        SettingPreset(label: "XL", value: 22),
    ]

    /// Get timer duration in seconds
    var timerDurationSeconds: Int {
        timerMinutes * 60 + timerSeconds
    }

    // MARK: Mode's own values

    /// The editor text size for the mode being written in.
    var activeEditorFontSize: Int {
        get { scriptMode == .cards ? cards.editorFontSize : editorFontSize }
        set { if scriptMode == .cards { cards.editorFontSize = newValue } else { editorFontSize = newValue } }
    }

    /// The cue color for the mode being written in.
    var activeCueColor: CueColor {
        get { scriptMode == .cards ? cards.cueColor : cueColor }
        set { if scriptMode == .cards { cards.cueColor = newValue } else { cueColor = newValue } }
    }

    /// The timer minutes for the mode being written in.
    var activeTimerMinutes: Int {
        get { scriptMode == .cards ? cards.timerMinutes : timerMinutes }
        set { if scriptMode == .cards { cards.timerMinutes = newValue } else { timerMinutes = newValue } }
    }

    /// The timer seconds for the mode being written in.
    var activeTimerSeconds: Int {
        get { scriptMode == .cards ? cards.timerSeconds : timerSeconds }
        set { if scriptMode == .cards { cards.timerSeconds = newValue } else { timerSeconds = newValue } }
    }

    enum CodingKeys: String, CodingKey {
        case editorFontSize
        /// Only read, and only to carry an older size setting over. See `init(from:)`.
        case fontSizePreset
        case pipFontSizePreset
        case fontSize
        case pipFontSize
        case overlayAspectRatio
        case scrollSpeed
        /// Only read, and only to carry an older speed setting over. See `init(from:)`.
        case wordsPerMinute
        case linesPerMinute
        case timerMinutes
        case timerSeconds
        case themePreference
        case countdownSeconds
        case cueColor
        case scriptMode
        /// Only read, to carry the old Lock Screen / In App choice over to
        /// `cards.showOnLockScreen`. See `init(from:)`.
        case cardDisplay
        case watch
        case cards
    }

    init(
        editorFontSize: Int,
        fontSize: Int,
        pipFontSize: Int,
        overlayAspectRatio: OverlayAspectRatio,
        scrollSpeed: Double,
        linesPerMinute: Int,
        timerMinutes: Int,
        timerSeconds: Int,
        themePreference: ThemePreference,
        countdownSeconds: Int,
        cueColor: CueColor,
        scriptMode: ScriptMode,
        watch: WatchSettings,
        cards: CardsSettings
    ) {
        self.editorFontSize = editorFontSize
        self.fontSize = fontSize
        self.pipFontSize = pipFontSize
        self.overlayAspectRatio = overlayAspectRatio
        self.scrollSpeed = scrollSpeed
        self.linesPerMinute = linesPerMinute
        self.timerMinutes = timerMinutes
        self.timerSeconds = timerSeconds
        self.themePreference = themePreference
        self.countdownSeconds = countdownSeconds
        self.cueColor = cueColor
        self.scriptMode = scriptMode
        self.watch = watch
        self.cards = cards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editorFontSize = TeleprompterSettings.clamp(
            try container.decodeIfPresent(Int.self, forKey: .editorFontSize) ?? TeleprompterSettings.default.editorFontSize,
            to: TeleprompterSettings.editorFontSizeRange
        )
        // Text size used to be one of three presets. Settings saved then carry the
        // preset and no size, so start them on the size that preset drew at.
        if let size = try container.decodeIfPresent(Int.self, forKey: .fontSize) {
            fontSize = TeleprompterSettings.clamp(size, to: TeleprompterSettings.fontSizeRange)
        } else {
            fontSize = try container.decodeIfPresent(LegacyFontSizePreset.self, forKey: .fontSizePreset)?.fontSize
                ?? TeleprompterSettings.default.fontSize
        }
        if let size = try container.decodeIfPresent(Int.self, forKey: .pipFontSize) {
            pipFontSize = TeleprompterSettings.clamp(size, to: TeleprompterSettings.pipFontSizeRange)
        } else {
            pipFontSize = try container.decodeIfPresent(LegacyFontSizePreset.self, forKey: .pipFontSizePreset)?.pipFontSize
                ?? TeleprompterSettings.default.pipFontSize
        }
        overlayAspectRatio = try container.decodeIfPresent(OverlayAspectRatio.self, forKey: .overlayAspectRatio)
            ?? TeleprompterSettings.default.overlayAspectRatio
        scrollSpeed = try container.decode(Double.self, forKey: .scrollSpeed)
        // Speed used to be set in words a minute, back when a highlight ran along
        // the words. Settings saved then carry the old figure and no usable line
        // speed, so convert it: a line holds about five words at the sizes on offer.
        if let wordsPerMinute = try container.decodeIfPresent(Int.self, forKey: .wordsPerMinute) {
            linesPerMinute = min(max(wordsPerMinute / 5, TeleprompterSettings.lpmRange.lowerBound), TeleprompterSettings.lpmRange.upperBound)
        } else {
            linesPerMinute = try container.decodeIfPresent(Int.self, forKey: .linesPerMinute) ?? TeleprompterSettings.default.linesPerMinute
        }
        timerMinutes = try container.decode(Int.self, forKey: .timerMinutes)
        timerSeconds = try container.decode(Int.self, forKey: .timerSeconds)
        themePreference = try container.decode(ThemePreference.self, forKey: .themePreference)
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 5
        cueColor = try container.decodeIfPresent(CueColor.self, forKey: .cueColor) ?? .default
        scriptMode = try container.decodeIfPresent(ScriptMode.self, forKey: .scriptMode)
            ?? TeleprompterSettings.default.scriptMode
        watch = try container.decodeIfPresent(WatchSettings.self, forKey: .watch)
            ?? TeleprompterSettings.default.watch
        // From before cards kept their own: start them on what both used.
        cards = try container.decodeIfPresent(CardsSettings.self, forKey: .cards)
            ?? CardsSettings(editorFontSize: editorFontSize, fontSize: fontSize, cueColor: cueColor,
                             timerMinutes: timerMinutes, timerSeconds: timerSeconds)
        // Cards used to be read either on the Lock Screen or in the app. Now
        // they're read in the app, and In App was the choice to keep them off
        // the Lock Screen.
        if let display = try container.decodeIfPresent(String.self, forKey: .cardDisplay) {
            cards.showOnLockScreen = display != "inApp"
        }
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(editorFontSize, forKey: .editorFontSize)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(pipFontSize, forKey: .pipFontSize)
        try container.encode(overlayAspectRatio, forKey: .overlayAspectRatio)
        try container.encode(scrollSpeed, forKey: .scrollSpeed)
        try container.encode(linesPerMinute, forKey: .linesPerMinute)
        try container.encode(timerMinutes, forKey: .timerMinutes)
        try container.encode(timerSeconds, forKey: .timerSeconds)
        try container.encode(themePreference, forKey: .themePreference)
        try container.encode(countdownSeconds, forKey: .countdownSeconds)
        try container.encode(cueColor, forKey: .cueColor)
        try container.encode(scriptMode, forKey: .scriptMode)
        try container.encode(watch, forKey: .watch)
        try container.encode(cards, forKey: .cards)
    }
}

/// Saved note model
struct SavedNote: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var content: String
    /// The mode it was written in, and opens back up in.
    var mode: ScriptMode
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, content: String, mode: ScriptMode,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        // Notes saved before each mode kept its own are cards if they were
        // split into any.
        mode = try container.decodeIfPresent(ScriptMode.self, forKey: .mode)
            ?? (CueCards.separatorRanges(in: content).isEmpty ? .teleprompter : .cards)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// Service for persisting user settings
@MainActor
class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let userDefaults = UserDefaults.standard
    private let settingsKey = "cuecard_settings"
    /// The teleprompter's script. Named from when it was the only one.
    private let notesKey = "cuecard_notes"
    private let cardsNotesKey = "cuecard_cards_notes"
    private let savedNotesKey = "cuecard_saved_notes"
    /// The teleprompter's open note. Named from when it was the only one.
    private let currentNoteIdKey = "cuecard_current_note_id"
    private let cardsNoteIdKey = "cuecard_cards_note_id"
    private let watchNoteIDsKey = "cuecard_watch_note_ids"
    private let hasSeenWelcomeKey = "cuecard_has_seen_welcome"
    /// Cues used to be saved in a library. They're written straight into the
    /// script now, so the stored library is cleared out on the way past.
    private let retiredCuesKey = "cuecard_cues"
    private var isLoadingNote = false

    @Published var settings: TeleprompterSettings {
        didSet {
            saveSettings()
        }
    }

    /// Each mode keeps its own script, so switching modes never shows one
    /// written for the other.
    @Published private var teleprompterNotes: String {
        didSet { userDefaults.set(teleprompterNotes, forKey: notesKey) }
    }

    @Published private var cardsNotes: String {
        didSet { userDefaults.set(cardsNotes, forKey: cardsNotesKey) }
    }

    /// The script for the mode the editor is in.
    var notes: String {
        get { notes(for: settings.scriptMode) }
        set {
            setNotes(newValue, for: settings.scriptMode)
            // Update the timestamp on the current note when content changes (but not when loading)
            if !isLoadingNote,
               let id = currentNoteId,
               let index = savedNotes.firstIndex(where: { $0.id == id }) {
                savedNotes[index].updatedAt = Date()
            }
        }
    }

    func notes(for mode: ScriptMode) -> String {
        mode == .cards ? cardsNotes : teleprompterNotes
    }

    private func setNotes(_ text: String, for mode: ScriptMode) {
        if mode == .cards {
            cardsNotes = text
        } else {
            teleprompterNotes = text
        }
    }

    @Published var savedNotes: [SavedNote] = [] {
        didSet {
            saveSavedNotes()
        }
    }

    /// The saved note open in each mode.
    @Published private var teleprompterNoteId: UUID? {
        didSet { saveNoteId(teleprompterNoteId, forKey: currentNoteIdKey) }
    }

    @Published private var cardsNoteId: UUID? {
        didSet { saveNoteId(cardsNoteId, forKey: cardsNoteIdKey) }
    }

    /// The saved note open in the mode the editor is in.
    var currentNoteId: UUID? {
        get { settings.scriptMode == .cards ? cardsNoteId : teleprompterNoteId }
        set { setNoteId(newValue, for: settings.scriptMode) }
    }

    private func setNoteId(_ id: UUID?, for mode: ScriptMode) {
        if mode == .cards {
            cardsNoteId = id
        } else {
            teleprompterNoteId = id
        }
    }

    /// The saved notes the user has put on their Apple Watch.
    @Published var watchNoteIDs: Set<UUID> = [] {
        didSet {
            userDefaults.set(watchNoteIDs.map(\.uuidString), forKey: watchNoteIDsKey)
        }
    }

    /// Whether the welcome screen has been through. Kept on the device and
    /// nowhere else, so a fresh install opens on it again.
    @Published private(set) var hasSeenWelcome: Bool

    /// Default text for new notes
    static let defaultNoteText = """
Welcome everyone.

I'm excited to be here today to talk about CueCard.

[cue smile and pause]

It keeps your speaker notes visible above all apps, so you can use your existing camera apps and still read your notes.

[cue pause]

It has a timer so you know if you're being brief… or too passionate.

[cue light chuckle]

And the colored highlights?

[cue emphasize]

Those are your secret cues — reminders to smile, pause, or not panic.

[cue pause]

Try it out. I think you'll love it.
"""

    /// Sample text for cards mode: short meeting notes, each short enough for
    /// the Lock Screen.
    static let defaultCardsText = """
Thank everyone for joining. [cue smile]
[separator]
Q3 revenue is up 18%. Lead with this.
[separator]
Two engineers start in October. [cue pause]
[separator]
Ask for questions before wrapping up.
"""

    private init() {
        self.hasSeenWelcome = userDefaults.bool(forKey: hasSeenWelcomeKey)

        // Load settings from UserDefaults
        var needsSave = false
        let loadedSettings: TeleprompterSettings
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(TeleprompterSettings.self, from: data) {
            loadedSettings = decoded
        } else {
            loadedSettings = .default
            needsSave = true
        }
        self.settings = loadedSettings

        // Load notes from UserDefaults
        let legacyNotes = userDefaults.string(forKey: notesKey) ?? ""
        let legacyNoteId = userDefaults.string(forKey: currentNoteIdKey).flatMap(UUID.init(uuidString:))
        if userDefaults.object(forKey: cardsNotesKey) == nil && loadedSettings.scriptMode == .cards {
            // From before each mode kept its own script: what was being
            // written belongs to cards, the mode it was written in.
            self.teleprompterNotes = ""
            self.cardsNotes = legacyNotes
            self.teleprompterNoteId = nil
            self.cardsNoteId = legacyNoteId
            userDefaults.set(legacyNotes, forKey: cardsNotesKey)
            userDefaults.set("", forKey: notesKey)
            userDefaults.set(legacyNoteId?.uuidString, forKey: cardsNoteIdKey)
            userDefaults.removeObject(forKey: currentNoteIdKey)
        } else {
            self.teleprompterNotes = legacyNotes
            self.cardsNotes = userDefaults.string(forKey: cardsNotesKey) ?? ""
            self.teleprompterNoteId = legacyNoteId
            self.cardsNoteId = userDefaults.string(forKey: cardsNoteIdKey).flatMap(UUID.init(uuidString:))
        }

        // Load saved notes from UserDefaults
        if let data = userDefaults.data(forKey: savedNotesKey),
           let decoded = try? JSONDecoder().decode([SavedNote].self, from: data) {
            self.savedNotes = decoded
        }

        if let strings = userDefaults.stringArray(forKey: watchNoteIDsKey) {
            self.watchNoteIDs = Set(strings.compactMap(UUID.init(uuidString:)))
        }

        userDefaults.removeObject(forKey: retiredCuesKey)

        // Notes start empty - users can add sample text via the button
        if needsSave {
            saveSettings()
        }
    }

    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }

    private func saveSavedNotes() {
        if let encoded = try? JSONEncoder().encode(savedNotes) {
            userDefaults.set(encoded, forKey: savedNotesKey)
        }
    }

    private func saveNoteId(_ id: UUID?, forKey key: String) {
        if let id {
            userDefaults.set(id.uuidString, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Leave the welcome screen behind: remember it was seen, and start the
    /// first script off with the sample so the editor is never opened empty.
    func completeWelcome() {
        hasSeenWelcome = true
        userDefaults.set(true, forKey: hasSeenWelcomeKey)

        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addSampleText()
        }
    }

    /// Put everything Settings shows back to its default. The timer, the mode
    /// and where cards are read are set on the home screen, not in Settings,
    /// so they are left as they are.
    func resetSettings() {
        settings = defaultsKeepingTimer
    }

    /// Whether Reset to Defaults has anything to reset.
    var canResetSettings: Bool {
        settings != defaultsKeepingTimer
    }

    private var defaultsKeepingTimer: TeleprompterSettings {
        var defaults = TeleprompterSettings.default
        defaults.timerMinutes = settings.timerMinutes
        defaults.timerSeconds = settings.timerSeconds
        defaults.cards.timerMinutes = settings.cards.timerMinutes
        defaults.cards.timerSeconds = settings.cards.timerSeconds
        defaults.scriptMode = settings.scriptMode
        return defaults
    }

    /// Save current notes as a new note
    func saveCurrentNote(title: String) {
        let trimmedContent = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        let note = SavedNote(title: title, content: notes, mode: settings.scriptMode)
        savedNotes.insert(note, at: 0)
        currentNoteId = note.id
    }

    /// Update an existing saved note
    func updateNote(id: UUID, title: String? = nil, content: String? = nil) {
        guard let index = savedNotes.firstIndex(where: { $0.id == id }) else { return }
        if let title = title {
            savedNotes[index].title = title
        }
        if let content = content {
            savedNotes[index].content = content
        }
        savedNotes[index].updatedAt = Date()
    }

    /// Save current changes to the currently loaded note
    func saveChangesToCurrentNote() {
        guard let id = currentNoteId else { return }
        updateNote(id: id, content: notes)
    }

    /// Load a saved note into the editor, switching to the mode it was written in.
    func loadNote(_ note: SavedNote) {
        settings.scriptMode = note.mode
        isLoadingNote = true
        notes = note.content
        currentNoteId = note.id
        isLoadingNote = false
    }

    /// Delete a saved note
    func deleteNote(id: UUID) {
        savedNotes.removeAll { $0.id == id }
        watchNoteIDs.remove(id)
        if teleprompterNoteId == id { teleprompterNoteId = nil }
        if cardsNoteId == id { cardsNoteId = nil }
    }

    /// Create a new empty note
    func createNewNote() {
        isLoadingNote = true
        notes = ""
        currentNoteId = nil
        isLoadingNote = false
    }

    /// Load imported file content into the editor and keep it as a saved note.
    /// The file already carries a name, so there's nothing to prompt the user for.
    func importNote(title: String, content: String) {
        isLoadingNote = true
        notes = content
        currentNoteId = nil
        isLoadingNote = false
        saveCurrentNote(title: title)
    }

    /// Add sample text to current note, written for the mode the editor is in.
    func addSampleText() {
        notes = settings.scriptMode == .cards ? Self.defaultCardsText : Self.defaultNoteText
    }

    /// Put a saved note on the watch, or take it off.
    func setOnWatch(_ isOnWatch: Bool, noteID: UUID) {
        if isOnWatch {
            watchNoteIDs.insert(noteID)
        } else {
            watchNoteIDs.remove(noteID)
        }
    }

    /// Get the currently loaded note if any
    var currentNote: SavedNote? {
        guard let id = currentNoteId else { return nil }
        return savedNotes.first { $0.id == id }
    }

    /// Check if current notes have unsaved changes
    var hasUnsavedChanges: Bool {
        guard let current = currentNote else {
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return current.content != notes
    }

    /// Clear all stored data
    func clearAllData() {
        settings = .default
        teleprompterNotes = ""
        cardsNotes = ""
        savedNotes = []
        teleprompterNoteId = nil
        cardsNoteId = nil
        watchNoteIDs = []
        userDefaults.removeObject(forKey: settingsKey)
        userDefaults.removeObject(forKey: notesKey)
        userDefaults.removeObject(forKey: cardsNotesKey)
        userDefaults.removeObject(forKey: savedNotesKey)
        userDefaults.removeObject(forKey: currentNoteIdKey)
        userDefaults.removeObject(forKey: cardsNoteIdKey)
        ReviewPromptService.shared.reset()
    }
}
