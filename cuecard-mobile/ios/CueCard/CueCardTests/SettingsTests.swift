import Foundation
import SwiftUI
import Testing
@testable import CueCard

/// Saved settings and notes have to keep decoding across releases: a decode
/// that fails puts the user back on the defaults, or loses their notes.
@Suite("Settings")
struct SettingsTests {

    private func decodeSettings(_ json: String) throws -> TeleprompterSettings {
        try JSONDecoder().decode(TeleprompterSettings.self, from: Data(json.utf8))
    }

    // MARK: - Round trip

    @Test func defaultSettingsSurviveEncoding() throws {
        let data = try JSONEncoder().encode(TeleprompterSettings.default)
        #expect(try JSONDecoder().decode(TeleprompterSettings.self, from: data) == .default)
    }

    @Test func changedSettingsSurviveEncoding() throws {
        var settings = TeleprompterSettings.default
        settings.scriptMode = .cards
        settings.cueColor = .blue
        settings.cards.cueColor = .purple
        settings.cards.showOnLockScreen = false
        settings.timerMinutes = 3
        settings.timerStyle.warningSeconds = 30
        settings.themePreference = .dark
        settings.watch.haptics = false

        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TeleprompterSettings.self, from: data) == settings)
    }

    // MARK: - Older saved settings

    @Test func oldestSettingsDecodeWithDefaults() throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 2, "timerSeconds": 30, "themePreference": "Light"}
        """)
        let defaults = TeleprompterSettings.default

        #expect(settings.themePreference == .light)
        #expect(settings.timerDurationSeconds == 150)
        #expect(settings.fontSize == defaults.fontSize)
        #expect(settings.pipFontSize == defaults.pipFontSize)
        #expect(settings.linesPerMinute == defaults.linesPerMinute)
        #expect(settings.countdownSeconds == 5)
        #expect(settings.cueColor == .default)
        #expect(settings.scriptMode == .teleprompter)
        #expect(settings.timerStyle == .default)
        #expect(settings.watch == .default)
        #expect(settings.overlayAspectRatio == .ratio16x9)
    }

    @Test func cardsStartOnTheTeleprompterValuesFromBeforeTheyHadTheirOwn() throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 2, "timerSeconds": 30, "themePreference": "System",
         "cueColor": "blue", "fontSize": 30}
        """)
        #expect(settings.cards.timerMinutes == 2)
        #expect(settings.cards.timerSeconds == 30)
        #expect(settings.cards.cueColor == .blue)
        #expect(settings.cards.fontSize == settings.fontSize)
        #expect(settings.cards.showOnLockScreen)
    }

    @Test(arguments: [("Small", 20, 12), ("Medium", 28, 16), ("Large", 40, 22)])
    func carriesOverOldTextSizePresets(_ preset: String, _ fontSize: Int, _ pipFontSize: Int) throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 1, "timerSeconds": 0, "themePreference": "System",
         "fontSizePreset": "\(preset)", "pipFontSizePreset": "\(preset)"}
        """)
        #expect(settings.fontSize == fontSize)
        #expect(settings.pipFontSize == pipFontSize)
    }

    @Test(arguments: [(170, 34), (0, 1), (5_000, 300)])
    func convertsOldWordsPerMinute(_ wordsPerMinute: Int, _ linesPerMinute: Int) throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 1, "timerSeconds": 0, "themePreference": "System",
         "wordsPerMinute": \(wordsPerMinute)}
        """)
        #expect(settings.linesPerMinute == linesPerMinute)
    }

    @Test(arguments: [("inApp", false), ("lockScreen", true)])
    func carriesOverTheOldCardDisplayChoice(_ display: String, _ showOnLockScreen: Bool) throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 1, "timerSeconds": 0, "themePreference": "System",
         "cardDisplay": "\(display)"}
        """)
        #expect(settings.cards.showOnLockScreen == showOnLockScreen)
    }

    @Test func clampsTextSizesIntoRange() throws {
        let settings = try decodeSettings("""
        {"scrollSpeed": 1.0, "timerMinutes": 1, "timerSeconds": 0, "themePreference": "System",
         "fontSize": 1000, "pipFontSize": 1, "editorFontSize": 1000}
        """)
        #expect(settings.fontSize == TeleprompterSettings.fontSizeRange.upperBound)
        #expect(settings.pipFontSize == TeleprompterSettings.pipFontSizeRange.lowerBound)
        #expect(settings.editorFontSize == TeleprompterSettings.editorFontSizeRange.upperBound)
    }

    @Test func cardsSettingsFromBeforeTimerColorsAndLockScreenDecode() throws {
        let cards = try JSONDecoder().decode(CardsSettings.self, from: Data("""
        {"editorFontSize": 16, "fontSize": 28, "cueColor": "green", "timerMinutes": 0, "timerSeconds": 45}
        """.utf8))
        #expect(cards.timerStyle == .default)
        #expect(cards.showOnLockScreen)
        #expect(cards.timerDurationSeconds == 45)
        #expect(cards.characterLimit == 120)
    }

    // MARK: - Persisted names

    @Test func persistedRawValuesStayStable() {
        #expect(CueColor.allCases.map(\.rawValue) == ["pink", "yellow", "green", "blue", "purple", "red"])
        #expect(CueColor.default == .pink)
        #expect(ThemePreference.allCases.map(\.rawValue) == ["System", "Light", "Dark"])
        #expect(OverlayAspectRatio.allCases.map(\.rawValue) == ["16:9", "4:3", "1:1"])
        #expect(WatchCardTextSize.allCases.map(\.rawValue) == ["Small", "Medium", "Large"])
    }

    @Test func themePreferenceColorSchemes() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }

    @Test func overlayRatios() {
        #expect(OverlayAspectRatio.ratio16x9.ratio == 16.0 / 9.0)
        #expect(OverlayAspectRatio.ratio4x3.ratio == 4.0 / 3.0)
        #expect(OverlayAspectRatio.ratio1x1.ratio == 1.0)
    }

    // MARK: - Each mode's own values

    @Test func activeValuesFollowTheMode() {
        var settings = TeleprompterSettings.default
        settings.cueColor = .blue
        settings.cards.cueColor = .red

        settings.scriptMode = .teleprompter
        #expect(settings.activeCueColor == .blue)
        settings.activeTimerMinutes = 7
        #expect(settings.timerMinutes == 7)
        #expect(settings.cards.timerMinutes != 7)

        settings.scriptMode = .cards
        #expect(settings.activeCueColor == .red)
        settings.activeTimerMinutes = 4
        settings.activeTimerSeconds = 20
        #expect(settings.cards.timerMinutes == 4)
        #expect(settings.cards.timerSeconds == 20)
        #expect(settings.timerMinutes == 7)
    }

    // MARK: - Sizes

    @Test func scalesSizesAndRanges() {
        #expect(ScreenTextScale.scaled(16, by: 1.5) == 24)
        #expect(ScreenTextScale.scaled(10...20, by: 2) == 20...40)
        #expect(ScreenTextScale.scaled([SettingPreset(label: "M", value: 10)], by: 1.25).map(\.value) == [13])
    }

    @Test func presetsSitInsideTheirRanges() {
        for preset in TeleprompterSettings.fontSizePresets {
            #expect(TeleprompterSettings.fontSizeRange.contains(preset.value))
        }
        for preset in TeleprompterSettings.pipFontSizePresets {
            #expect(TeleprompterSettings.pipFontSizeRange.contains(preset.value))
        }
        for preset in TeleprompterSettings.editorFontSizePresets {
            #expect(TeleprompterSettings.editorFontSizeRange.contains(preset.value))
        }
    }

    // MARK: - Saved notes

    @Test func savedNoteSurvivesEncoding() throws {
        let note = SavedNote(title: "Talk", content: "Hello [cue smile]", mode: .cards,
                             createdAt: Date(timeIntervalSince1970: 100),
                             updatedAt: Date(timeIntervalSince1970: 200))
        let decoded = try JSONDecoder().decode(SavedNote.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
    }

    @Test(arguments: [("Just a script", ScriptMode.teleprompter), ("One[separator]Two", .cards)])
    func noteFromBeforeModesGetsOneFromItsContent(_ content: String, _ mode: ScriptMode) throws {
        let json = """
        {"id": "\(UUID().uuidString)", "title": "Old", "content": "\(content)", "createdAt": 0, "updatedAt": 0}
        """
        let note = try JSONDecoder().decode(SavedNote.self, from: Data(json.utf8))
        #expect(note.mode == mode)
    }
}
