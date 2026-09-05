package com.thisisnsh.cuecard.android.services

import android.content.Context
import androidx.core.content.edit
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.models.AppVersion
import com.thisisnsh.cuecard.android.models.RemoteConfig
import com.thisisnsh.cuecard.android.models.RemoteMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.random.Random

/**
 * Fetches `/v2/config` from the mobile worker and decides what the app does with
 * it: which features stay switched on, whether this build is too old to run, and
 * which notice — if any — belongs on a given screen.
 *
 * The whole thing is built to fail open. The last good response is kept on disk
 * and used immediately at launch, a fetch that times out or comes back malformed
 * changes nothing, and a client that has never once reached the worker behaves
 * exactly as it was shipped. Nothing here blocks the UI: the config arrives when
 * it arrives, and the views update if it changes anything.
 */
class RemoteConfigService private constructor(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val analytics = Firebase.analytics

    private val _config = MutableStateFlow(RemoteConfig.EMPTY)
    val config: StateFlow<RemoteConfig> = _config.asStateFlow()

    private val _dismissedIds = MutableStateFlow<Set<String>>(emptySet())
    val dismissedIds: StateFlow<Set<String>> = _dismissedIds.asStateFlow()

    private var lastRefresh: Long? = null

    init {
        prefs.getString(CONFIG_KEY, null)?.let { cached ->
            RemoteConfig.decode(cached)?.let { _config.value = it }
        }
        _dismissedIds.value = prefs.getStringSet(DISMISSED_KEY, emptySet())?.toSet() ?: emptySet()
    }

    // MARK: - Fetching

    /**
     * Pull a fresh config. Safe to call on every launch and every resume — it
     * throttles itself, and it never throws.
     */
    suspend fun refresh(force: Boolean = false) {
        val last = lastRefresh
        if (!force && last != null && System.currentTimeMillis() - last < MINIMUM_REFRESH_INTERVAL_MS) {
            return
        }

        val raw = withContext(Dispatchers.IO) {
            try {
                val url = URL(
                    "$ENDPOINT?p=android" +
                        "&v=${AppVersion.current}" +
                        "&b=${AppVersion.build}" +
                        "&l=$languageCode"
                )
                (url.openConnection() as HttpURLConnection).run {
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                    requestMethod = "GET"
                    setRequestProperty("Accept", "application/json")
                    try {
                        if (responseCode != 200) return@withContext null
                        inputStream.bufferedReader().use { it.readText() }
                    } finally {
                        disconnect()
                    }
                }
            } catch (e: Exception) {
                // Offline, slow, or the worker returned something we couldn't read.
                // Whatever was cached stays in force.
                null
            }
        } ?: return

        val fetched = RemoteConfig.decode(raw) ?: return

        lastRefresh = System.currentTimeMillis()
        _config.value = fetched
        prefs.edit { putString(CONFIG_KEY, raw) }
        pruneDismissals(fetched)
    }

    // MARK: - Flags

    /**
     * True when this build is older than the worker's stated floor. The one piece
     * of remote config allowed to stand in front of the app, so it's only ever
     * set when a shipped build is genuinely unusable.
     */
    val requiresUpdate: Boolean
        get() = AppVersion.compare(AppVersion.current, _config.value.flags.minSupportedVersion) < 0

    /**
     * Where the update screen sends people, falling back to our own listing if
     * the worker didn't name one.
     */
    val updateURL: String
        get() = _config.value.flags.updateURL ?: AppLinks.PLAY_STORE

    val isPiPEnabled: Boolean get() = _config.value.flags.features.pip

    /**
     * Parsed and exposed, never acted on. iOS can switch a provider off because
     * the other one still lets people in; Android has one provider, so honouring
     * this would lock every user out with no fallback.
     */
    val isGoogleSignInEnabled: Boolean get() = _config.value.flags.features.googleSignIn

    /** Parsed so the payload shape stays identical across platforms. Unused here. */
    val isAppleSignInEnabled: Boolean get() = _config.value.flags.features.appleSignIn

    // MARK: - Messages

    /**
     * The one message to show on a surface: highest priority among those this
     * install is eligible for. One at a time — a stack of banners reads as spam.
     */
    fun message(surface: RemoteMessage.Surface): RemoteMessage? =
        _config.value.messages
            .filter { it.surface == surface && isEligible(it) }
            .maxByOrNull { it.priority }

    fun dismiss(message: RemoteMessage) {
        if (!message.dismissible) return

        val updated = _dismissedIds.value + message.id
        _dismissedIds.value = updated
        prefs.edit { putStringSet(DISMISSED_KEY, updated) }

        analytics.logEvent("remote_message_dismissed") {
            param("message_id", message.id)
        }
    }

    fun logImpression(message: RemoteMessage) {
        analytics.logEvent("remote_message_shown") {
            param("message_id", message.id)
            param("surface", message.surface.rawValue)
        }
    }

    fun logAction(action: RemoteMessage.Action, message: RemoteMessage) {
        analytics.logEvent("remote_message_action") {
            param("message_id", message.id)
            param("action", action.kind.rawValue)
        }
    }

    private fun isEligible(message: RemoteMessage): Boolean {
        if (!message.isRenderable) return false
        if (message.hasExpired()) return false
        if (_dismissedIds.value.contains(message.id)) return false
        if (rolloutBucket >= message.rolloutPercent) return false

        // The worker filters on `match` as well, but a cached payload can outlive
        // the app version it was fetched for, so check again here.
        message.match?.let { match ->
            val admits = match.admits(
                platform = "android",
                version = AppVersion.current,
                build = AppVersion.build,
                locale = languageCode
            )
            if (!admits) return false
        }

        return true
    }

    /**
     * Forget dismissals for messages the worker has stopped sending, so the list
     * can't grow forever. Ids are never reused for different copy, so a message
     * that comes back is the same one the user already waved away.
     */
    private fun pruneDismissals(config: RemoteConfig) {
        val live = config.messages.map { it.id }.toSet()
        val kept = _dismissedIds.value.intersect(live)

        if (kept == _dismissedIds.value) return

        _dismissedIds.value = kept
        prefs.edit { putStringSet(DISMISSED_KEY, kept) }
    }

    /**
     * A number in 0..<100, drawn once and kept, so a partial rollout stays
     * consistent for this install instead of flickering between launches.
     */
    private val rolloutBucket: Int
        get() {
            val stored = prefs.getInt(BUCKET_KEY, -1)
            if (stored >= 0) return stored

            val bucket = Random.nextInt(0, 100)
            prefs.edit { putInt(BUCKET_KEY, bucket) }
            return bucket
        }

    private val languageCode: String
        get() = Locale.getDefault().language.ifEmpty { "en" }

    companion object {
        private const val ENDPOINT = "https://cuecard-mobile.thisisnsh.workers.dev/v2/config"

        /**
         * Long enough that foregrounding the app repeatedly doesn't hammer the edge,
         * short enough that pulling a bad message takes effect within a session.
         */
        private const val MINIMUM_REFRESH_INTERVAL_MS = 15L * 60L * 1000L
        private const val TIMEOUT_MS = 5000

        private const val PREFS_NAME = "cuecard_remote_config"
        private const val CONFIG_KEY = "cuecard_remote_config"
        private const val DISMISSED_KEY = "cuecard_remote_config_dismissed"
        private const val BUCKET_KEY = "cuecard_remote_config_bucket"

        @Volatile
        private var instance: RemoteConfigService? = null

        fun getInstance(context: Context): RemoteConfigService {
            return instance ?: synchronized(this) {
                instance ?: RemoteConfigService(context.applicationContext).also { instance = it }
            }
        }
    }
}
