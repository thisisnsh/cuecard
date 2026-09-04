package com.thisisnsh.cuecard.android.services

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.thisisnsh.cuecard.android.models.CueColor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "cuecard_settings")

/** Theme preference for the app */
@Serializable
enum class ThemePreference(val displayName: String) {
    SYSTEM("System"),
    LIGHT("Light"),
    DARK("Dark");

    companion object {
        fun fromString(value: String): ThemePreference =
            entries.find { it.displayName == value } ?: SYSTEM
    }
}

/** Font size presets for teleprompter */
@Serializable
enum class FontSizePreset(val displayName: String, val fontSize: Int, val pipFontSize: Int) {
    SMALL("Small", 20, 12),
    MEDIUM("Medium", 28, 16),
    LARGE("Large", 40, 22);

    companion object {
        fun fromString(value: String): FontSizePreset =
            entries.find { it.displayName == value } ?: MEDIUM
    }
}

/** Overlay dimension ratio presets */
@Serializable
enum class OverlayAspectRatio(val displayName: String, val ratio: Float) {
    RATIO_16X9("16:9", 16f / 9f),
    RATIO_4X3("4:3", 4f / 3f),
    RATIO_1X1("1:1", 1f);

    companion object {
        fun fromString(value: String): OverlayAspectRatio =
            entries.find { it.displayName == value } ?: RATIO_16X9
    }
}

/** Settings for the teleprompter */
@Serializable
data class TeleprompterSettings(
    val fontSizePreset: FontSizePreset = FontSizePreset.MEDIUM,
    val pipFontSizePreset: FontSizePreset = FontSizePreset.MEDIUM,
    val overlayAspectRatio: OverlayAspectRatio = OverlayAspectRatio.RATIO_16X9,
    val scrollSpeed: Double = 1.0,
    /** Scroll speed, in lines of the script as the teleprompter renders them. */
    val linesPerMinute: Int = 30,
    val timerMinutes: Int = 1,
    val timerSeconds: Int = 0,
    val themePreference: ThemePreference = ThemePreference.SYSTEM,
    val countdownSeconds: Int = 5,
    /** The color every `[cue …]` in every script is drawn in. */
    val cueColor: CueColor = CueColor.DEFAULT
) {
    /** Computed font size from preset */
    val fontSize: Int
        get() = fontSizePreset.fontSize

    /** Computed PiP font size from preset */
    val pipFontSize: Int
        get() = pipFontSizePreset.pipFontSize

    /** Get timer duration in seconds */
    val timerDurationSeconds: Int
        get() = timerMinutes * 60 + timerSeconds

    companion object {
        val DEFAULT = TeleprompterSettings()

        /** Scroll speed range (multiplier) */
        val SCROLL_SPEED_RANGE = 0.5..3.0

        /** Lines per minute range */
        val LPM_RANGE = 5..60
    }
}

/** Saved note model */
data class SavedNote(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val content: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

/**
 * Service for persisting user settings using DataStore
 */
class SettingsService(private val context: Context) {

    companion object {
        /** Default text for new notes */
        val DEFAULT_NOTE_TEXT = """
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
""".trimIndent()

        // Preference keys
        private val FONT_SIZE_PRESET = stringPreferencesKey("font_size_preset")
        private val PIP_FONT_SIZE_PRESET = stringPreferencesKey("pip_font_size_preset")
        private val OVERLAY_ASPECT_RATIO = stringPreferencesKey("overlay_aspect_ratio")
        private val SCROLL_SPEED = doublePreferencesKey("scroll_speed")
        private val LINES_PER_MINUTE = intPreferencesKey("lines_per_minute")
        private val TIMER_MINUTES = intPreferencesKey("timer_minutes")
        private val TIMER_SECONDS = intPreferencesKey("timer_seconds")
        private val THEME_PREFERENCE = stringPreferencesKey("theme_preference")
        private val COUNTDOWN_SECONDS = intPreferencesKey("countdown_seconds")
        private val CUE_COLOR = stringPreferencesKey("cue_color")
        private val NOTES = stringPreferencesKey("notes")
        private val SAVED_NOTES = stringPreferencesKey("saved_notes")
        private val CURRENT_NOTE_ID = stringPreferencesKey("current_note_id")

        /**
         * Speed used to be set in words a minute, back when a highlight ran along
         * the words, and scrolling was a switch rather than a rate. Both keys are
         * only ever read, and only once — see `settingsFrom`.
         */
        private val RETIRED_WORDS_PER_MINUTE = intPreferencesKey("words_per_minute")
        private val RETIRED_AUTO_SCROLL = booleanPreferencesKey("auto_scroll")

        @Volatile
        private var instance: SettingsService? = null

        fun getInstance(context: Context): SettingsService {
            return instance ?: synchronized(this) {
                instance ?: SettingsService(context.applicationContext).also { instance = it }
            }
        }
    }

    private val _settings = MutableStateFlow(TeleprompterSettings.DEFAULT)
    val settings: StateFlow<TeleprompterSettings> = _settings.asStateFlow()

    private val _notes = MutableStateFlow("")
    val notes: StateFlow<String> = _notes.asStateFlow()

    private val _savedNotes = MutableStateFlow<List<SavedNote>>(emptyList())
    val savedNotes: StateFlow<List<SavedNote>> = _savedNotes.asStateFlow()

    private val _currentNoteId = MutableStateFlow<String?>(null)
    val currentNoteId: StateFlow<String?> = _currentNoteId.asStateFlow()

    private var isLoadingNote = false

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Read the settings out of a preferences snapshot, carrying an older
     * words-a-minute speed over: a line holds about five words at these sizes.
     */
    private fun settingsFrom(prefs: Preferences): TeleprompterSettings {
        val storedLines = prefs[LINES_PER_MINUTE]
        val retiredWords = prefs[RETIRED_WORDS_PER_MINUTE]

        val linesPerMinute = when {
            storedLines != null -> storedLines
            retiredWords != null -> (retiredWords / 5).coerceIn(
                TeleprompterSettings.LPM_RANGE.first,
                TeleprompterSettings.LPM_RANGE.last
            )
            else -> TeleprompterSettings.DEFAULT.linesPerMinute
        }

        return TeleprompterSettings(
            fontSizePreset = FontSizePreset.fromString(prefs[FONT_SIZE_PRESET] ?: FontSizePreset.MEDIUM.displayName),
            pipFontSizePreset = FontSizePreset.fromString(prefs[PIP_FONT_SIZE_PRESET] ?: FontSizePreset.MEDIUM.displayName),
            overlayAspectRatio = OverlayAspectRatio.fromString(prefs[OVERLAY_ASPECT_RATIO] ?: OverlayAspectRatio.RATIO_16X9.displayName),
            scrollSpeed = prefs[SCROLL_SPEED] ?: 1.0,
            linesPerMinute = linesPerMinute,
            timerMinutes = prefs[TIMER_MINUTES] ?: 1,
            timerSeconds = prefs[TIMER_SECONDS] ?: 0,
            themePreference = ThemePreference.fromString(prefs[THEME_PREFERENCE] ?: ThemePreference.SYSTEM.displayName),
            countdownSeconds = prefs[COUNTDOWN_SECONDS] ?: 5,
            cueColor = CueColor.fromString(prefs[CUE_COLOR])
        )
    }

    /**
     * Load settings from DataStore
     */
    suspend fun loadSettings() {
        val prefs = context.dataStore.data.first()
        val loaded = settingsFrom(prefs)
        _settings.value = loaded
        _notes.value = prefs[NOTES] ?: ""

        prefs[SAVED_NOTES]?.let { jsonStr ->
            try {
                _savedNotes.value = json.decodeFromString<List<SavedNoteJson>>(jsonStr)
                    .map { it.toSavedNote() }
            } catch (e: Exception) {
                _savedNotes.value = emptyList()
            }
        }
        _currentNoteId.value = prefs[CURRENT_NOTE_ID]

        // A speed carried over from the old setting is written back straight
        // away, so the retired keys are gone before anything else reads them.
        if (prefs[LINES_PER_MINUTE] == null) {
            saveSettings(loaded)
        }
    }

    /**
     * Save settings to DataStore
     */
    suspend fun saveSettings(newSettings: TeleprompterSettings) {
        _settings.value = newSettings
        context.dataStore.edit { prefs ->
            prefs[FONT_SIZE_PRESET] = newSettings.fontSizePreset.displayName
            prefs[PIP_FONT_SIZE_PRESET] = newSettings.pipFontSizePreset.displayName
            prefs[OVERLAY_ASPECT_RATIO] = newSettings.overlayAspectRatio.displayName
            prefs[SCROLL_SPEED] = newSettings.scrollSpeed
            prefs[LINES_PER_MINUTE] = newSettings.linesPerMinute
            prefs[TIMER_MINUTES] = newSettings.timerMinutes
            prefs[TIMER_SECONDS] = newSettings.timerSeconds
            prefs[THEME_PREFERENCE] = newSettings.themePreference.displayName
            prefs[COUNTDOWN_SECONDS] = newSettings.countdownSeconds
            prefs[CUE_COLOR] = newSettings.cueColor.rawValue
            prefs.remove(RETIRED_WORDS_PER_MINUTE)
            prefs.remove(RETIRED_AUTO_SCROLL)
        }
    }

    /**
     * Save notes to DataStore. Editing the script bumps the timestamp on the
     * note it belongs to, the way the iOS `notes` observer does.
     */
    suspend fun saveNotes(newNotes: String) {
        _notes.value = newNotes
        context.dataStore.edit { prefs ->
            prefs[NOTES] = newNotes
        }

        if (isLoadingNote) return
        val id = _currentNoteId.value ?: return
        val index = _savedNotes.value.indexOfFirst { it.id == id }
        if (index == -1) return

        val updated = _savedNotes.value.toMutableList()
        updated[index] = updated[index].copy(updatedAt = System.currentTimeMillis())
        _savedNotes.value = updated
        saveSavedNotes()
    }

    /**
     * Reset settings to defaults
     */
    suspend fun resetSettings() {
        saveSettings(TeleprompterSettings.DEFAULT)
    }

    /**
     * Clear all stored data
     */
    suspend fun clearAllData() {
        _settings.value = TeleprompterSettings.DEFAULT
        _notes.value = ""
        _savedNotes.value = emptyList()
        _currentNoteId.value = null
        context.dataStore.edit { prefs ->
            prefs.clear()
        }
        ReviewPromptService.getInstance(context).reset()
    }

    /**
     * Update individual setting properties
     */
    suspend fun updateFontSizePreset(preset: FontSizePreset) {
        saveSettings(_settings.value.copy(fontSizePreset = preset))
    }

    suspend fun updatePipFontSizePreset(preset: FontSizePreset) {
        saveSettings(_settings.value.copy(pipFontSizePreset = preset))
    }

    suspend fun updateOverlayAspectRatio(ratio: OverlayAspectRatio) {
        saveSettings(_settings.value.copy(overlayAspectRatio = ratio))
    }

    suspend fun updateLinesPerMinute(lines: Int) {
        saveSettings(_settings.value.copy(linesPerMinute = lines))
    }

    suspend fun updateTimerMinutes(minutes: Int) {
        saveSettings(_settings.value.copy(timerMinutes = minutes))
    }

    suspend fun updateTimerSeconds(seconds: Int) {
        saveSettings(_settings.value.copy(timerSeconds = seconds))
    }

    suspend fun updateThemePreference(theme: ThemePreference) {
        saveSettings(_settings.value.copy(themePreference = theme))
    }

    suspend fun updateCountdownSeconds(seconds: Int) {
        saveSettings(_settings.value.copy(countdownSeconds = seconds))
    }

    suspend fun updateCueColor(cueColor: CueColor) {
        saveSettings(_settings.value.copy(cueColor = cueColor))
    }

    /** Add sample text to current note */
    suspend fun addSampleText() {
        saveNotes(DEFAULT_NOTE_TEXT)
    }

    // ==================== Saved Notes Methods ====================

    /**
     * Save current notes as a new note
     */
    suspend fun saveCurrentNote(title: String) {
        val trimmedContent = _notes.value.trim()
        if (trimmedContent.isEmpty()) return

        val note = SavedNote(
            title = title,
            content = _notes.value
        )
        _savedNotes.value = listOf(note) + _savedNotes.value
        _currentNoteId.value = note.id
        saveSavedNotes()
        saveCurrentNoteId()
    }

    /**
     * Update an existing saved note
     */
    suspend fun updateNote(id: String, title: String? = null, content: String? = null) {
        val index = _savedNotes.value.indexOfFirst { it.id == id }
        if (index == -1) return

        val currentNote = _savedNotes.value[index]
        val updatedNote = currentNote.copy(
            title = title ?: currentNote.title,
            content = content ?: currentNote.content,
            updatedAt = System.currentTimeMillis()
        )

        val updatedList = _savedNotes.value.toMutableList()
        updatedList[index] = updatedNote
        _savedNotes.value = updatedList
        saveSavedNotes()
    }

    /**
     * Save current changes to the currently loaded note
     */
    suspend fun saveChangesToCurrentNote() {
        val id = _currentNoteId.value ?: return
        updateNote(id, content = _notes.value)
    }

    /**
     * Load a saved note into the editor
     */
    suspend fun loadNote(note: SavedNote) {
        isLoadingNote = true
        _currentNoteId.value = note.id
        saveNotes(note.content)
        saveCurrentNoteId()
        isLoadingNote = false
    }

    /**
     * Delete a saved note
     */
    suspend fun deleteNote(id: String) {
        _savedNotes.value = _savedNotes.value.filter { it.id != id }
        if (_currentNoteId.value == id) {
            _currentNoteId.value = null
            saveCurrentNoteId()
        }
        saveSavedNotes()
    }

    /**
     * Create a new empty note
     */
    suspend fun createNewNote() {
        isLoadingNote = true
        _currentNoteId.value = null
        saveNotes("")
        saveCurrentNoteId()
        isLoadingNote = false
    }

    /**
     * Load imported file content into the editor and keep it as a saved note.
     * The file already carries a name, so there's nothing to prompt the user for.
     */
    suspend fun importNote(title: String, content: String) {
        isLoadingNote = true
        _currentNoteId.value = null
        saveNotes(content)
        saveCurrentNoteId()
        isLoadingNote = false
        saveCurrentNote(title)
    }

    /**
     * Get the currently loaded note if any
     */
    val currentNote: SavedNote?
        get() {
            val id = _currentNoteId.value ?: return null
            return _savedNotes.value.find { it.id == id }
        }

    /**
     * Check if current notes have unsaved changes
     */
    val hasUnsavedChanges: Boolean
        get() {
            val current = currentNote ?: return _notes.value.trim().isNotEmpty()
            return current.content != _notes.value
        }

    private suspend fun saveSavedNotes() {
        val jsonList = _savedNotes.value.map { SavedNoteJson.fromSavedNote(it) }
        val jsonStr = json.encodeToString(jsonList)
        context.dataStore.edit { prefs ->
            prefs[SAVED_NOTES] = jsonStr
        }
    }

    private suspend fun saveCurrentNoteId() {
        context.dataStore.edit { prefs ->
            val id = _currentNoteId.value
            if (id != null) {
                prefs[CURRENT_NOTE_ID] = id
            } else {
                prefs.remove(CURRENT_NOTE_ID)
            }
        }
    }
}

/**
 * JSON serializable version of SavedNote
 */
@Serializable
private data class SavedNoteJson(
    val id: String,
    val title: String,
    val content: String,
    val createdAt: Long,
    val updatedAt: Long
) {
    fun toSavedNote() = SavedNote(
        id = id,
        title = title,
        content = content,
        createdAt = createdAt,
        updatedAt = updatedAt
    )

    companion object {
        fun fromSavedNote(note: SavedNote) = SavedNoteJson(
            id = note.id,
            title = note.title,
            content = note.content,
            createdAt = note.createdAt,
            updatedAt = note.updatedAt
        )
    }
}
