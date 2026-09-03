import Foundation
import SwiftUI

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

/// Font size presets for teleprompter
enum FontSizePreset: String, Codable, CaseIterable {
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
}

/// Settings for the teleprompter
struct TeleprompterSettings: Codable, Equatable {
    var fontSizePreset: FontSizePreset
    var pipFontSizePreset: FontSizePreset
    var overlayAspectRatio: OverlayAspectRatio
    var scrollSpeed: Double
    var wordsPerMinute: Int
    var linesPerMinute: Int
    var timerMinutes: Int
    var timerSeconds: Int
    var themePreference: ThemePreference
    var countdownSeconds: Int

    /// Computed font size from preset
    var fontSize: Int {
        fontSizePreset.fontSize
    }

    /// Computed PiP font size from preset
    var pipFontSize: Int {
        pipFontSizePreset.pipFontSize
    }

    static let `default` = TeleprompterSettings(
        fontSizePreset: .medium,
        pipFontSizePreset: .medium,
        overlayAspectRatio: .ratio16x9,
        scrollSpeed: 1.0,
        wordsPerMinute: 150,
        linesPerMinute: 10,
        timerMinutes: 1,
        timerSeconds: 0,
        themePreference: .system,
        countdownSeconds: 5
    )

    /// Scroll speed range (multiplier)
    static let scrollSpeedRange = 0.5...3.0

    /// Words per minute range
    static let wpmRange = 50...300

    /// Lines per minute range
    static let lpmRange = 5...30

    /// Get timer duration in seconds
    var timerDurationSeconds: Int {
        timerMinutes * 60 + timerSeconds
    }

    enum CodingKeys: String, CodingKey {
        case fontSizePreset
        case pipFontSizePreset
        case overlayAspectRatio
        case scrollSpeed
        case wordsPerMinute
        case linesPerMinute
        case timerMinutes
        case timerSeconds
        case themePreference
        case countdownSeconds
    }

    init(
        fontSizePreset: FontSizePreset,
        pipFontSizePreset: FontSizePreset,
        overlayAspectRatio: OverlayAspectRatio,
        scrollSpeed: Double,
        wordsPerMinute: Int,
        linesPerMinute: Int,
        timerMinutes: Int,
        timerSeconds: Int,
        themePreference: ThemePreference,
        countdownSeconds: Int
    ) {
        self.fontSizePreset = fontSizePreset
        self.pipFontSizePreset = pipFontSizePreset
        self.overlayAspectRatio = overlayAspectRatio
        self.scrollSpeed = scrollSpeed
        self.wordsPerMinute = wordsPerMinute
        self.linesPerMinute = linesPerMinute
        self.timerMinutes = timerMinutes
        self.timerSeconds = timerSeconds
        self.themePreference = themePreference
        self.countdownSeconds = countdownSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSizePreset = try container.decode(FontSizePreset.self, forKey: .fontSizePreset)
        pipFontSizePreset = try container.decode(FontSizePreset.self, forKey: .pipFontSizePreset)
        overlayAspectRatio = try container.decodeIfPresent(OverlayAspectRatio.self, forKey: .overlayAspectRatio) ?? .ratio16x9
        scrollSpeed = try container.decode(Double.self, forKey: .scrollSpeed)
        wordsPerMinute = try container.decode(Int.self, forKey: .wordsPerMinute)
        linesPerMinute = try container.decode(Int.self, forKey: .linesPerMinute)
        timerMinutes = try container.decode(Int.self, forKey: .timerMinutes)
        timerSeconds = try container.decode(Int.self, forKey: .timerSeconds)
        themePreference = try container.decode(ThemePreference.self, forKey: .themePreference)
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSizePreset, forKey: .fontSizePreset)
        try container.encode(pipFontSizePreset, forKey: .pipFontSizePreset)
        try container.encode(overlayAspectRatio, forKey: .overlayAspectRatio)
        try container.encode(scrollSpeed, forKey: .scrollSpeed)
        try container.encode(wordsPerMinute, forKey: .wordsPerMinute)
        try container.encode(linesPerMinute, forKey: .linesPerMinute)
        try container.encode(timerMinutes, forKey: .timerMinutes)
        try container.encode(timerSeconds, forKey: .timerSeconds)
        try container.encode(themePreference, forKey: .themePreference)
        try container.encode(countdownSeconds, forKey: .countdownSeconds)
    }
}

/// Saved note model
struct SavedNote: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Service for persisting user settings
@MainActor
class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let userDefaults = UserDefaults.standard
    private let settingsKey = "cuecard_settings"
    private let notesKey = "cuecard_notes"
    private let savedNotesKey = "cuecard_saved_notes"
    private let currentNoteIdKey = "cuecard_current_note_id"
    private var isLoadingNote = false

    @Published var settings: TeleprompterSettings {
        didSet {
            saveSettings()
        }
    }

    @Published var notes: String {
        didSet {
            saveNotes()
            // Update the timestamp on the current note when content changes (but not when loading)
            if !isLoadingNote,
               let id = currentNoteId,
               let index = savedNotes.firstIndex(where: { $0.id == id }) {
                savedNotes[index].updatedAt = Date()
            }
        }
    }

    @Published var savedNotes: [SavedNote] = [] {
        didSet {
            saveSavedNotes()
        }
    }

    @Published var currentNoteId: UUID? {
        didSet {
            saveCurrentNoteId()
        }
    }

    /// Default text for new notes
    static let defaultNoteText = """
Welcome everyone.

I'm excited to be here today to talk about CueCard.

[cue:pink smile and pause]

It keeps your speaker notes visible above all apps, so you can use your existing camera apps and still read your notes.

[cue:yellow pause]

It has a timer so you know if you're being brief… or too passionate.

[cue:green light chuckle]

And the colored highlights?

[cue:purple emphasize]

Those are your secret cues — reminders to smile, pause, or not panic.

[cue:yellow pause]

Try it out. I think you'll love it.
"""

    private init() {
        // Load settings from UserDefaults
        var needsSave = false
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(TeleprompterSettings.self, from: data) {
            let normalizedSettings = decoded
            self.settings = normalizedSettings
        } else {
            self.settings = .default
            needsSave = true
        }

        // Load notes from UserDefaults
        self.notes = userDefaults.string(forKey: notesKey) ?? ""

        // Load saved notes from UserDefaults
        if let data = userDefaults.data(forKey: savedNotesKey),
           let decoded = try? JSONDecoder().decode([SavedNote].self, from: data) {
            self.savedNotes = decoded
        }

        // Load current note id
        if let idString = userDefaults.string(forKey: currentNoteIdKey),
           let id = UUID(uuidString: idString) {
            self.currentNoteId = id
        }

        // Scripts written before the rename still say [note …]; rewrite them once so
        // what users see in the editor matches what the cue bar now writes.
        let migratedNotes = TeleprompterParser.migratedToCueTags(self.notes)
        if migratedNotes != self.notes {
            self.notes = migratedNotes
            userDefaults.set(migratedNotes, forKey: notesKey)
        }

        let migratedSavedNotes = self.savedNotes.map { note -> SavedNote in
            var migrated = note
            migrated.content = TeleprompterParser.migratedToCueTags(note.content)
            return migrated
        }
        if migratedSavedNotes != self.savedNotes {
            self.savedNotes = migratedSavedNotes
            if let encoded = try? JSONEncoder().encode(migratedSavedNotes) {
                userDefaults.set(encoded, forKey: savedNotesKey)
            }
        }

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

    private func saveNotes() {
        userDefaults.set(notes, forKey: notesKey)
    }

    private func saveSavedNotes() {
        if let encoded = try? JSONEncoder().encode(savedNotes) {
            userDefaults.set(encoded, forKey: savedNotesKey)
        }
    }

    private func saveCurrentNoteId() {
        if let id = currentNoteId {
            userDefaults.set(id.uuidString, forKey: currentNoteIdKey)
        } else {
            userDefaults.removeObject(forKey: currentNoteIdKey)
        }
    }

    /// Reset settings to defaults
    func resetSettings() {
        settings = .default
    }

    /// Save current notes as a new note
    func saveCurrentNote(title: String) {
        let trimmedContent = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        let note = SavedNote(title: title, content: notes)
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

    /// Load a saved note into the editor
    func loadNote(_ note: SavedNote) {
        isLoadingNote = true
        notes = note.content
        currentNoteId = note.id
        isLoadingNote = false
    }

    /// Delete a saved note
    func deleteNote(id: UUID) {
        savedNotes.removeAll { $0.id == id }
        if currentNoteId == id {
            currentNoteId = nil
        }
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
        notes = TeleprompterParser.migratedToCueTags(content)
        currentNoteId = nil
        isLoadingNote = false
        saveCurrentNote(title: title)
    }

    /// Add sample text to current note
    func addSampleText() {
        notes = Self.defaultNoteText
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
        notes = ""
        savedNotes = []
        currentNoteId = nil
        userDefaults.removeObject(forKey: settingsKey)
        userDefaults.removeObject(forKey: notesKey)
        userDefaults.removeObject(forKey: savedNotesKey)
        userDefaults.removeObject(forKey: currentNoteIdKey)
        ReviewPromptService.shared.reset()
    }
}
