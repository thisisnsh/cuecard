package com.thisisnsh.cuecard.android.services

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
 * The new features for this build, read from `assets/WhatsNew.json`.
 *
 * Entries are keyed by `<version>-<build>`, so a release that forgets to add its
 * own entry shows nothing rather than the last release's features. Each build is
 * shown once on launch, remembered under `new-features-<version>-<build>`.
 */
class WhatsNewService private constructor(private val context: Context) {

    data class Release(val title: String?, val features: List<String>)

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val key = "${BuildConfig.VERSION_NAME}-${BuildConfig.VERSION_CODE}"
    private val seenKey = "new-features-$key"

    /** The version as people see it, e.g. "1.0.0". */
    val version: String = BuildConfig.VERSION_NAME

    /** This build's entry, or null when the file has none for it. */
    val release: Release? by lazy { loadRelease() }

    /** Whether the launch presentation is up. Settings shows its own copy. */
    private val _isPresented = MutableStateFlow(false)
    val isPresented: StateFlow<Boolean> = _isPresented.asStateFlow()

    private fun loadRelease(): Release? = runCatching {
        val raw = context.assets.open(ASSET_NAME).bufferedReader().use { it.readText() }
        val entry = Json.parseToJsonElement(raw).jsonObject[key]?.jsonObject ?: return null
        val features = entry["features"]?.jsonArray
            ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
            .orEmpty()
        val title = (entry["title"] as? JsonPrimitive)?.contentOrNull
        if (features.isEmpty()) null else Release(title, features)
    }.getOrNull()

    /**
     * Show this build's features if they haven't been seen. A fresh install has
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
     * Counts the people this build's features reached on their own. Opening the
     * card from Settings is a `button_click` instead, so this stays a clean
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
