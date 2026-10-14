package com.thisisnsh.cuecard.android.services

import com.thisisnsh.cuecard.android.R
import android.content.Context
import androidx.core.content.edit
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * The new features for this version, read from `assets/WhatsNew.json`.
 *
 * Entries are keyed by `<version>`, so a release that forgets to add its own
 * entry shows nothing rather than the last release's features. Builds of the
 * same version share an entry, so a rebuild doesn't show it again. Each version
 * is shown once on launch, remembered under `new-features-<version>`.
 */
class WhatsNewService private constructor(private val context: Context) {

    data class Release(val title: String?, val features: List<String>)

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val seenKey = "new-features-${BuildConfig.VERSION_NAME}"

    /** The version as people see it, e.g. "1.0.0". */
    val version: String = BuildConfig.VERSION_NAME

    /** This version's entry as the file writes it, in English. */
    private val englishRelease: Release? by lazy { loadRelease() }

    /**
     * This version's entry, or null when the file has none for it. Translated
     * as it's read, so it follows the app's language if that changes.
     */
    val release: Release?
        get() = englishRelease?.let { release ->
            Release(release.title?.let(::localized), release.features.map(::localized))
        }

    /** Whether the launch presentation is up. Help shows its own copy. */
    private val _isPresented = MutableStateFlow(false)
    val isPresented: StateFlow<Boolean> = _isPresented.asStateFlow()

    private fun loadRelease(): Release? = runCatching {
        val raw = context.assets.open(ASSET_NAME).bufferedReader().use { it.readText() }
        val entry = Json.parseToJsonElement(raw).jsonObject[version]?.jsonObject ?: return null
        val features = entry["features"]?.jsonArray
            ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
            .orEmpty()
        val title = (entry["title"] as? JsonPrimitive)?.contentOrNull
        if (features.isEmpty()) null else Release(title, features)
    }.getOrNull()

    /**
     * The JSON's text in the app's language. Translations are added to
     * strings.xml by hand, as `whats_new_text`, in the same order as the
     * English in `whats_new_english`. Text without one shows in English.
     */
    private fun localized(text: String): String {
        val index = context.resources.getStringArray(R.array.whats_new_english).indexOf(text)
        if (index < 0) return text
        return context.resources.getStringArray(R.array.whats_new_text).getOrNull(index) ?: text
    }

    /**
     * Show this version's features if they haven't been seen. A fresh install has
     * only just met the app, so it skips them: `hasSeenWelcome` is false there.
     * Counted as seen once shown, so closing the app on the card doesn't bring
     * it back.
     */
    fun presentIfUnseen(hasSeenWelcome: Boolean) {
        if (release == null || prefs.getBoolean(seenKey, false)) return
        prefs.edit { putBoolean(seenKey, true) }
        if (!hasSeenWelcome) return

        _isPresented.value = true
        logShown()
    }

    fun dismiss() {
        _isPresented.value = false
    }

    /**
     * Counts the people this version's features reached on their own. Opening the
     * card from Help is a `button_click` instead, so this stays a clean
     * impression count rather than one mixed with people going looking.
     */
    private fun logShown() {
        AnalyticsEvents.logEvent("whats_new_shown", mapOf("version" to version))
    }

    companion object {
        private const val PREFS_NAME = "cuecard_whats_new"
        private const val ASSET_NAME = "WhatsNew.json"

        @Volatile
        private var instance: WhatsNewService? = null

        fun getInstance(context: Context): WhatsNewService {
            return instance ?: synchronized(this) {
                instance ?: WhatsNewService(context.applicationContext).also { instance = it }
            }
        }
    }
}
