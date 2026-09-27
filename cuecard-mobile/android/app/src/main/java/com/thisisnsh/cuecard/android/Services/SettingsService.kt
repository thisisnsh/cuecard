package com.thisisnsh.cuecard.android.services

import android.content.Context
import android.content.res.Resources
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.TimerStyle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID
import kotlin.math.roundToInt

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

/**
 * The Small / Medium / Large text sizes settings used to be saved as. Only read,
 * to carry an older choice over to the size it stood for.
 */
private enum class LegacyFontSizePreset(val displayName: String, val fontSize: Int, val pipFontSize: Int) {
    SMALL("Small", 20, 12),
    MEDIUM("Medium", 28, 16),
    LARGE("Large", 40, 22);

    companion object {
        fun fromString(value: String?): LegacyFontSizePreset? =
            entries.find { it.displayName == value }
    }
}

/**
 * Overlay dimension ratio presets. `displayName` is what's saved, so it stays
 * the bare ratio; `label` is what Settings shows.
 */
@Serializable
enum class OverlayAspectRatio(val displayName: String, val label: String, val ratio: Float) {
    RATIO_16X9("16:9", "Rectangle 16:9", 16f / 9f),
    RATIO_4X3("4:3", "Rectangle 4:3", 4f / 3f),
    RATIO_1X1("1:1", "Square 1:1", 1f);

    companion object {
        fun fromString(value: String): OverlayAspectRatio =
            entries.find { it.displayName == value } ?: TeleprompterSettings.DEFAULT.overlayAspectRatio
    }
}

/** One of the named sizes a text size setting offers in its menu. */
data class SettingPreset(val label: String, val value: Int)

/**
 * How much bigger text needs to be on this device to look the size it does on a
 * phone. Sizes are designed on a 393-dp-wide phone, and every other screen is
 * measured by its short side, so turning the device doesn't change them.
 */
object ScreenTextScale {
    private const val REFERENCE_WIDTH = 393.0

    /**
     * Grows with the screen, so a line holds about as many words on a tablet as
     * on a phone. What the teleprompter needs, since it's read from a distance.
     */
    val teleprompter: Double by lazy {
        val metrics = Resources.getSystem().displayMetrics
        minOf(metrics.widthPixels, metrics.heightPixels) / metrics.density / REFERENCE_WIDTH
    }

    /**
     * Grows half as fast: the editor is read up close, where a phone's size times
     * two is more than anyone writes in.
     */
    val editor: Double by lazy { 1 + (teleprompter - 1) / 2 }

    fun scaled(size: Int, by: Double): Int = (size * by).roundToInt()

    fun scaled(range: IntRange, by: Double): IntRange =
        scaled(range.first, by)..scaled(range.last, by)

    fun scaled(presets: List<SettingPreset>, by: Double): List<SettingPreset> =
        presets.map { it.copy(value = scaled(it.value, by)) }
}

/**
 * Cards mode's own values for everything it has in common with the
 * teleprompter, so setting one up never changes the other.
 */
@Serializable
data class CardsSettings(
    /** Text size in the cards editor, in sp. */
    val editorFontSize: Int = ScreenTextScale.scaled(16, ScreenTextScale.editor),
    /** Text size on a card being read, in sp. */
    val fontSize: Int = ScreenTextScale.scaled(28, ScreenTextScale.teleprompter),
    /** The color every `[cue …]` on a card is drawn in. */
    val cueColor: CueColor = CueColor.DEFAULT,
    val timerMinutes: Int = 1,
    val timerSeconds: Int = 0,
    /** When and how the cards timer changes color. */
    val timerStyle: TimerStyle = TimerStyle.DEFAULT
) {
    val timerDurationSeconds: Int
        get() = timerMinutes * 60 + timerSeconds
}

/** Settings for the teleprompter */
@Serializable
data class TeleprompterSettings(
    /** Text size in the script editor, in sp. */
    val editorFontSize: Int = ScreenTextScale.scaled(16, ScreenTextScale.editor),
    /** Text size in the in-app prompter, in sp. */
    val fontSize: Int = ScreenTextScale.scaled(28, ScreenTextScale.teleprompter),
    /** Text size in the floating prompter, in sp. */
    val pipFontSize: Int = 16,
    val overlayAspectRatio: OverlayAspectRatio = OverlayAspectRatio.RATIO_16X9,
    val scrollSpeed: Double = 1.0,
    /** Scroll speed, in lines of the script as the teleprompter renders them. */
    val linesPerMinute: Int = 34,
    val timerMinutes: Int = 1,
    val timerSeconds: Int = 0,
    /** When and how the teleprompter's timer changes color. */
    val timerStyle: TimerStyle = TimerStyle.DEFAULT,
    val themePreference: ThemePreference = ThemePreference.SYSTEM,
    val countdownSeconds: Int = 5,
    /** The color every `[cue …]` in every script is drawn in. */
    val cueColor: CueColor = CueColor.DEFAULT,
    /**
     * What the editor writes and the Play button opens. Chosen on the home
     * screen, like the timer.
     */
    val scriptMode: ScriptMode = ScriptMode.TELEPROMPTER,
    /** Cards mode's own text sizes, cue color and timer. */
    val cards: CardsSettings = CardsSettings()
) {
    /** Get timer duration in seconds */
    val timerDurationSeconds: Int
        get() = timerMinutes * 60 + timerSeconds

    // MARK: Mode's own values

    private val isCards: Boolean
        get() = scriptMode == ScriptMode.CARDS

    /** The editor text size for the mode being written in. */
    val activeEditorFontSize: Int
        get() = if (isCards) cards.editorFontSize else editorFontSize

    /** The cue color for the mode being written in. */
    val activeCueColor: CueColor
        get() = if (isCards) cards.cueColor else cueColor

    /** The timer length, in seconds, for the mode being written in. */
    val activeTimerDurationSeconds: Int
        get() = if (isCards) cards.timerDurationSeconds else timerDurationSeconds

    /** The timer colors for the mode being written in. */
    val activeTimerStyle: TimerStyle
        get() = if (isCards) cards.timerStyle else timerStyle

    fun withActiveEditorFontSize(size: Int): TeleprompterSettings =
        if (isCards) copy(cards = cards.copy(editorFontSize = size)) else copy(editorFontSize = size)

    fun withActiveCueColor(color: CueColor): TeleprompterSettings =
        if (isCards) copy(cards = cards.copy(cueColor = color)) else copy(cueColor = color)

    fun withActiveTimer(minutes: Int, seconds: Int): TeleprompterSettings =
        if (isCards) {
            copy(cards = cards.copy(timerMinutes = minutes, timerSeconds = seconds))
        } else {
            copy(timerMinutes = minutes, timerSeconds = seconds)
        }

    fun withActiveTimerStyle(style: TimerStyle): TeleprompterSettings =
        if (isCards) copy(cards = cards.copy(timerStyle = style)) else copy(timerStyle = style)

    companion object {
        val DEFAULT = TeleprompterSettings()

        /** Scroll speed range (multiplier) */
        val SCROLL_SPEED_RANGE = 0.5..3.0

        /** The speeds a typed lines-a-minute figure is held to. */
        val LPM_RANGE = 1..300

        /** The countdowns a typed start delay is held to. */
        val COUNTDOWN_RANGE = 0..60

        /** The editor's text sizes a typed size is held to. Sized for this screen, like its presets. */
        val EDITOR_FONT_SIZE_RANGE = ScreenTextScale.scaled(12..40, ScreenTextScale.editor)

        /** The in-app text sizes a typed size is held to. Sized for this screen, like its presets. */
        val FONT_SIZE_RANGE = ScreenTextScale.scaled(16..72, ScreenTextScale.teleprompter)

        /**
         * The floating prompter's text sizes a typed size is held to. The overlay
         * window is about the same size on every device, so these aren't scaled.
         */
        val PIP_FONT_SIZE_RANGE = 10..32

        /**
         * The editor's text sizes offered as presets, around the 16 sp it has
         * always been set in on a phone, and scaled up for bigger screens.
         */
        val EDITOR_FONT_SIZE_PRESETS = ScreenTextScale.scaled(
            listOf(
                SettingPreset("XS", 12),
                SettingPreset("S", 14),
                SettingPreset("M", 16),
                SettingPreset("L", 20),
                SettingPreset("XL", 24)
            ),
            ScreenTextScale.editor
        )

        /**
         * The in-app text sizes offered as presets, as a phone sees them and scaled
         * to this screen. Past 40 sp a phone line holds fewer than three words, so
         * the larger sizes are left to Advanced.
         */
        val FONT_SIZE_PRESETS = ScreenTextScale.scaled(
            listOf(
                SettingPreset("XS", 20),
                SettingPreset("S", 24),
                SettingPreset("M", 28),
                SettingPreset("L", 34),
                SettingPreset("XL", 40)
            ),
            ScreenTextScale.teleprompter
        )

        /**
         * The floating prompter's text sizes offered as presets, spaced like the
         * in-app ones around its own default. Not scaled: see `PIP_FONT_SIZE_RANGE`.
         */
        val PIP_FONT_SIZE_PRESETS = listOf(
            SettingPreset("XS", 12),
            SettingPreset("S", 14),
            SettingPreset("M", 16),
            SettingPreset("L", 19),
            SettingPreset("XL", 22)
        )
    }
}

/** Saved note model */
data class SavedNote(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val content: String,
    /** The mode it was written in, and opens back up in. */
    val mode: ScriptMode,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

/**
 * Service for persisting user settings using DataStore
 */
class SettingsService(private val context: Context) {

    companion object {
        /** Sample text for teleprompter mode: a short talk about the teleprompter. */
        val DEFAULT_NOTE_TEXT = """
Hi everyone.

I'm excited to be here today to talk about CueCard's teleprompter.

[cue smile and pause]

It scrolls your script at your pace, so your eyes stay up and your words stay on track.

[cue pause]

Leave the app and it keeps going in a floating window, right over your camera or your video call.

[cue slow down]

Lost your place? Drag the script back. Running long? Skip ahead.

And the timer turns yellow near the end… and red if you get a little too passionate.

[cue light chuckle]

And these colored words?

[cue emphasize]

Those are your cues. Reminders to smile, pause, or not panic. They're never meant to be read out.

[cue pause]

Try it out. I think you'll love it.
""".trimIndent()

        /** Sample text for cards mode: a short talk about cards. */
        val DEFAULT_CARDS_TEXT = """
Hi everyone. Introducing Cue Cards. [cue smile]
[separator]
One thought per card. Swipe to the next one when you're ready.
[separator]
The timer at the top keeps you honest. [cue light chuckle]
[separator]
Colored words are cues, not lines. [cue emphasize]
[separator]
Thanks for listening. Questions?
""".trimIndent()

        // Preference keys
        private val EDITOR_FONT_SIZE = intPreferencesKey("editor_font_size")
        private val FONT_SIZE = intPreferencesKey("font_size")
        private val PIP_FONT_SIZE = intPreferencesKey("pip_font_size")
        private val OVERLAY_ASPECT_RATIO = stringPreferencesKey("overlay_aspect_ratio")
        private val SCROLL_SPEED = doublePreferencesKey("scroll_speed")
        private val LINES_PER_MINUTE = intPreferencesKey("lines_per_minute")
        private val TIMER_MINUTES = intPreferencesKey("timer_minutes")
        private val TIMER_SECONDS = intPreferencesKey("timer_seconds")
        private val TIMER_STYLE = stringPreferencesKey("timer_style")
        private val THEME_PREFERENCE = stringPreferencesKey("theme_preference")
        private val COUNTDOWN_SECONDS = intPreferencesKey("countdown_seconds")
        private val CUE_COLOR = stringPreferencesKey("cue_color")
        private val SCRIPT_MODE = stringPreferencesKey("script_mode")
        private val CARDS = stringPreferencesKey("cards")
        /** The teleprompter's script. Named from when it was the only one. */
        private val NOTES = stringPreferencesKey("notes")
        private val CARDS_NOTES = stringPreferencesKey("cards_notes")
        private val SAVED_NOTES = stringPreferencesKey("saved_notes")
        /** The teleprompter's open note. Named from when it was the only one. */
        private val CURRENT_NOTE_ID = stringPreferencesKey("current_note_id")
        private val CARDS_NOTE_ID = stringPreferencesKey("cards_note_id")

        /**
         * Speed used to be set in words a minute, back when a highlight ran along
         * the words, and scrolling was a switch rather than a rate. Both keys are
         * only ever read, and only once — see `settingsFrom`.
         */
        private val RETIRED_WORDS_PER_MINUTE = intPreferencesKey("words_per_minute")
        private val RETIRED_AUTO_SCROLL = booleanPreferencesKey("auto_scroll")

        /**
         * Text size used to be one of three presets. Settings saved then carry the
         * preset and no size — see `settingsFrom`.
         */
        private val RETIRED_FONT_SIZE_PRESET = stringPreferencesKey("font_size_preset")
        private val RETIRED_PIP_FONT_SIZE_PRESET = stringPreferencesKey("pip_font_size_preset")

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

    /**
     * Each mode keeps its own script, so switching modes never shows one written
     * for the other. `notes` is the one for the mode the editor is in.
     */
    private var teleprompterNotes = ""
    private var cardsNotes = ""
    private val _notes = MutableStateFlow("")
    val notes: StateFlow<String> = _notes.asStateFlow()

    private val _savedNotes = MutableStateFlow<List<SavedNote>>(emptyList())
    val savedNotes: StateFlow<List<SavedNote>> = _savedNotes.asStateFlow()

    /** The saved note open in each mode, and in the one the editor is in. */
    private var teleprompterNoteId: String? = null
    private var cardsNoteId: String? = null
    private val _currentNoteId = MutableStateFlow<String?>(null)
    val currentNoteId: StateFlow<String?> = _currentNoteId.asStateFlow()

    private var isLoadingNote = false

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Read the settings out of a preferences snapshot, carrying an older
     * words-a-minute speed over — a line holds about five words at these sizes —
     * and an older text size preset over to the size it drew at.
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

        val defaults = TeleprompterSettings.DEFAULT
        val editorFontSize = prefs[EDITOR_FONT_SIZE]?.coerceIn(TeleprompterSettings.EDITOR_FONT_SIZE_RANGE)
            ?: defaults.editorFontSize
        val fontSize = prefs[FONT_SIZE]?.coerceIn(TeleprompterSettings.FONT_SIZE_RANGE)
            ?: LegacyFontSizePreset.fromString(prefs[RETIRED_FONT_SIZE_PRESET])?.fontSize
            ?: defaults.fontSize
        val pipFontSize = prefs[PIP_FONT_SIZE]?.coerceIn(TeleprompterSettings.PIP_FONT_SIZE_RANGE)
            ?: LegacyFontSizePreset.fromString(prefs[RETIRED_PIP_FONT_SIZE_PRESET])?.pipFontSize
            ?: defaults.pipFontSize
        val timerMinutes = prefs[TIMER_MINUTES] ?: 1
        val timerSeconds = prefs[TIMER_SECONDS] ?: 0
        val cueColor = CueColor.fromString(prefs[CUE_COLOR])

        return TeleprompterSettings(
            editorFontSize = editorFontSize,
            fontSize = fontSize,
            pipFontSize = pipFontSize,
            overlayAspectRatio = OverlayAspectRatio.fromString(prefs[OVERLAY_ASPECT_RATIO] ?: TeleprompterSettings.DEFAULT.overlayAspectRatio.displayName),
            scrollSpeed = prefs[SCROLL_SPEED] ?: 1.0,
            linesPerMinute = linesPerMinute,
            timerMinutes = timerMinutes,
            timerSeconds = timerSeconds,
            timerStyle = decodeOrNull<TimerStyle>(prefs[TIMER_STYLE]) ?: TimerStyle.DEFAULT,
            themePreference = ThemePreference.fromString(prefs[THEME_PREFERENCE] ?: ThemePreference.SYSTEM.displayName),
            countdownSeconds = prefs[COUNTDOWN_SECONDS] ?: 5,
            cueColor = cueColor,
            scriptMode = ScriptMode.fromString(prefs[SCRIPT_MODE]),
            // From before cards kept their own: start them on what both used.
            cards = decodeOrNull<CardsSettings>(prefs[CARDS]) ?: CardsSettings(
                editorFontSize = editorFontSize,
                fontSize = fontSize,
                cueColor = cueColor,
                timerMinutes = timerMinutes,
                timerSeconds = timerSeconds
            )
        )
    }

    private inline fun <reified T> decodeOrNull(value: String?): T? =
        value?.let { runCatching { json.decodeFromString<T>(it) }.getOrNull() }

    /**
     * Load settings from DataStore
     */
    suspend fun loadSettings() {
        val prefs = context.dataStore.data.first()
        val loaded = settingsFrom(prefs)
        _settings.value = loaded
        teleprompterNotes = prefs[NOTES] ?: ""
        cardsNotes = prefs[CARDS_NOTES] ?: ""
        teleprompterNoteId = prefs[CURRENT_NOTE_ID]
        cardsNoteId = prefs[CARDS_NOTE_ID]
        showScript(loaded.scriptMode)

        prefs[SAVED_NOTES]?.let { jsonStr ->
            try {
                _savedNotes.value = json.decodeFromString<List<SavedNoteJson>>(jsonStr)
                    .map { it.toSavedNote() }
            } catch (e: Exception) {
                _savedNotes.value = emptyList()
            }
        }

        // A speed or size carried over from an old setting is written back
        // straight away, so the retired keys are gone before anything else reads them.
        if (prefs[LINES_PER_MINUTE] == null || prefs[FONT_SIZE] == null) {
            saveSettings(loaded)
        }
    }

    /**
     * Save settings to DataStore
     */
    suspend fun saveSettings(newSettings: TeleprompterSettings) {
        val modeChanged = newSettings.scriptMode != _settings.value.scriptMode
        _settings.value = newSettings
        if (modeChanged) showScript(newSettings.scriptMode)
        context.dataStore.edit { prefs ->
            prefs[EDITOR_FONT_SIZE] = newSettings.editorFontSize
            prefs[FONT_SIZE] = newSettings.fontSize
            prefs[PIP_FONT_SIZE] = newSettings.pipFontSize
            prefs[OVERLAY_ASPECT_RATIO] = newSettings.overlayAspectRatio.displayName
            prefs[SCROLL_SPEED] = newSettings.scrollSpeed
            prefs[LINES_PER_MINUTE] = newSettings.linesPerMinute
            prefs[TIMER_MINUTES] = newSettings.timerMinutes
            prefs[TIMER_SECONDS] = newSettings.timerSeconds
            prefs[TIMER_STYLE] = json.encodeToString(newSettings.timerStyle)
            prefs[THEME_PREFERENCE] = newSettings.themePreference.displayName
            prefs[COUNTDOWN_SECONDS] = newSettings.countdownSeconds
            prefs[CUE_COLOR] = newSettings.cueColor.rawValue
            prefs[SCRIPT_MODE] = newSettings.scriptMode.rawValue
            prefs[CARDS] = json.encodeToString(newSettings.cards)
            prefs.remove(RETIRED_WORDS_PER_MINUTE)
            prefs.remove(RETIRED_AUTO_SCROLL)
            prefs.remove(RETIRED_FONT_SIZE_PRESET)
            prefs.remove(RETIRED_PIP_FONT_SIZE_PRESET)
        }
    }

    /** Put the script and open note of `mode` in front of the editor. */
    private fun showScript(mode: ScriptMode) {
        _notes.value = if (mode == ScriptMode.CARDS) cardsNotes else teleprompterNotes
        _currentNoteId.value = if (mode == ScriptMode.CARDS) cardsNoteId else teleprompterNoteId
    }

    /**
     * Save the script for the mode the editor is in. Editing the script bumps the
     * timestamp on the note it belongs to, the way the iOS `notes` observer does.
     */
    suspend fun saveNotes(newNotes: String) {
        val isCards = _settings.value.scriptMode == ScriptMode.CARDS
        if (isCards) cardsNotes = newNotes else teleprompterNotes = newNotes
        _notes.value = newNotes
        context.dataStore.edit { prefs ->
            prefs[if (isCards) CARDS_NOTES else NOTES] = newNotes
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
     * Put everything Settings shows back to its default. The timer's length and
     * the mode are set on the home screen, not in Settings, so they are left as
     * they are.
     */
    suspend fun resetSettings() {
        saveSettings(defaultsKeepingTimer(_settings.value))
    }

    /** Whether Reset to Defaults has anything to reset. */
    fun canResetSettings(settings: TeleprompterSettings): Boolean =
        settings != defaultsKeepingTimer(settings)

    private fun defaultsKeepingTimer(settings: TeleprompterSettings): TeleprompterSettings {
        val defaults = TeleprompterSettings.DEFAULT
        return defaults.copy(
            timerMinutes = settings.timerMinutes,
            timerSeconds = settings.timerSeconds,
            scriptMode = settings.scriptMode,
            cards = defaults.cards.copy(
                timerMinutes = settings.cards.timerMinutes,
                timerSeconds = settings.cards.timerSeconds
            )
        )
    }

    /**
     * Clear all stored data
     */
    suspend fun clearAllData() {
        _settings.value = TeleprompterSettings.DEFAULT
        teleprompterNotes = ""
        cardsNotes = ""
        teleprompterNoteId = null
        cardsNoteId = null
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
    suspend fun update(change: (TeleprompterSettings) -> TeleprompterSettings) {
        saveSettings(change(_settings.value))
    }

    suspend fun updateScriptMode(mode: ScriptMode) {
        saveSettings(_settings.value.copy(scriptMode = mode))
    }

    suspend fun updateFontSize(size: Int) {
        saveSettings(_settings.value.copy(fontSize = size))
    }

    suspend fun updatePipFontSize(size: Int) {
        saveSettings(_settings.value.copy(pipFontSize = size))
    }

    suspend fun updateOverlayAspectRatio(ratio: OverlayAspectRatio) {
        saveSettings(_settings.value.copy(overlayAspectRatio = ratio))
    }

    suspend fun updateLinesPerMinute(lines: Int) {
        saveSettings(_settings.value.copy(linesPerMinute = lines))
    }

    suspend fun updateThemePreference(theme: ThemePreference) {
        saveSettings(_settings.value.copy(themePreference = theme))
    }

    suspend fun updateCountdownSeconds(seconds: Int) {
        saveSettings(_settings.value.copy(countdownSeconds = seconds))
    }

    /** Add sample text to current note, written for the mode the editor is in. */
    suspend fun addSampleText() {
        saveNotes(if (_settings.value.scriptMode == ScriptMode.CARDS) DEFAULT_CARDS_TEXT else DEFAULT_NOTE_TEXT)
    }

    /**
     * Start the first script off with the sample, so the editor is never opened
     * empty. Anything already written is left alone.
     */
    suspend fun addSampleTextIfEmpty() {
        if (_notes.value.isBlank()) addSampleText()
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
            content = _notes.value,
            mode = _settings.value.scriptMode
        )
        _savedNotes.value = listOf(note) + _savedNotes.value
        setCurrentNoteId(note.id)
        saveSavedNotes()
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
     * Load a saved note into the editor, switching to the mode it was written in.
     */
    suspend fun loadNote(note: SavedNote) {
        updateScriptMode(note.mode)
        isLoadingNote = true
        setCurrentNoteId(note.id)
        saveNotes(note.content)
        isLoadingNote = false
    }

    /**
     * Delete a saved note
     */
    suspend fun deleteNote(id: String) {
        _savedNotes.value = _savedNotes.value.filter { it.id != id }
        if (teleprompterNoteId == id || cardsNoteId == id) {
            context.dataStore.edit { prefs ->
                if (teleprompterNoteId == id) prefs.remove(CURRENT_NOTE_ID)
                if (cardsNoteId == id) prefs.remove(CARDS_NOTE_ID)
            }
            if (teleprompterNoteId == id) teleprompterNoteId = null
            if (cardsNoteId == id) cardsNoteId = null
            if (_currentNoteId.value == id) _currentNoteId.value = null
        }
        saveSavedNotes()
    }

    /**
     * Create a new empty note
     */
    suspend fun createNewNote() {
        isLoadingNote = true
        setCurrentNoteId(null)
        saveNotes("")
        isLoadingNote = false
    }

    /**
     * Load imported file content into the editor and keep it as a saved note.
     * The file already carries a name, so there's nothing to prompt the user for.
     */
    suspend fun importNote(title: String, content: String) {
        isLoadingNote = true
        setCurrentNoteId(null)
        saveNotes(content)
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

    /** Open `id` in the mode the editor is in, and remember it there. */
    private suspend fun setCurrentNoteId(id: String?) {
        val isCards = _settings.value.scriptMode == ScriptMode.CARDS
        if (isCards) cardsNoteId = id else teleprompterNoteId = id
        _currentNoteId.value = id
        context.dataStore.edit { prefs ->
            val key = if (isCards) CARDS_NOTE_ID else CURRENT_NOTE_ID
            if (id != null) {
                prefs[key] = id
            } else {
                prefs.remove(key)
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
    /** Missing from notes saved before each mode kept its own. */
    val mode: String? = null,
    val createdAt: Long,
    val updatedAt: Long
) {
    fun toSavedNote() = SavedNote(
        id = id,
        title = title,
        content = content,
        // Notes saved before each mode kept its own are cards if they were
        // split into any.
        mode = mode?.let { ScriptMode.fromString(it) }
            ?: if (CueCards.separatorRanges(content).isEmpty()) ScriptMode.TELEPROMPTER else ScriptMode.CARDS,
        createdAt = createdAt,
        updatedAt = updatedAt
    )

    companion object {
        fun fromSavedNote(note: SavedNote) = SavedNoteJson(
            id = note.id,
            title = note.title,
            content = note.content,
            mode = note.mode.rawValue,
            createdAt = note.createdAt,
            updatedAt = note.updatedAt
        )
    }
}
