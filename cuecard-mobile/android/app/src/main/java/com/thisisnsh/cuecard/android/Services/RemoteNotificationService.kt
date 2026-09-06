package com.thisisnsh.cuecard.android.services

import android.content.Context
import androidx.core.content.edit
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.BuildConfig
import com.thisisnsh.cuecard.android.models.RemoteNotification
import com.thisisnsh.cuecard.android.models.RemoteNotifications
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches `/v2/notifications` from the mobile worker and decides which notice —
 * if any — belongs on a given screen.
 *
 * The whole thing is built to fail open. The last good response is kept on disk
 * and used immediately at launch, a fetch that times out or comes back malformed
 * changes nothing, and a client that has never once reached the worker simply
 * shows nothing. Nothing here blocks the UI.
 */
class RemoteNotificationService private constructor(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val analytics = Firebase.analytics

    private val _payload = MutableStateFlow(RemoteNotifications.EMPTY)
    val payload: StateFlow<RemoteNotifications> = _payload.asStateFlow()

    private val _dismissedIds = MutableStateFlow<Set<String>>(emptySet())
    val dismissedIds: StateFlow<Set<String>> = _dismissedIds.asStateFlow()

    private var lastRefresh: Long? = null

    init {
        prefs.getString(PAYLOAD_KEY, null)?.let { cached ->
            RemoteNotifications.decode(cached)?.let { _payload.value = it }
        }
        _dismissedIds.value = prefs.getStringSet(DISMISSED_KEY, emptySet())?.toSet() ?: emptySet()
    }

    // MARK: - Fetching

    /**
     * Pull the current list. Safe to call on every launch and every resume — it
     * throttles itself, and it never throws.
     */
    suspend fun refresh(force: Boolean = false) {
        val last = lastRefresh
        if (!force && last != null && System.currentTimeMillis() - last < MINIMUM_REFRESH_INTERVAL_MS) {
            return
        }

        val raw = withContext(Dispatchers.IO) {
            try {
                (URL(ENDPOINT).openConnection() as HttpURLConnection).run {
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                    requestMethod = "GET"
                    setRequestProperty("Accept", "application/json")
                    // The worker sends `Cache-Control: max-age=300`. We do our own
                    // throttling and keep our own copy on disk, so a second layer
                    // of caching here buys nothing and would hide a freshly
                    // deployed notification for another five minutes.
                    useCaches = false
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

        val fetched = RemoteNotifications.decode(raw) ?: return

        lastRefresh = System.currentTimeMillis()
        _payload.value = fetched
        prefs.edit { putString(PAYLOAD_KEY, raw) }
        pruneDismissals(fetched)
    }

    // MARK: - Notifications

    /**
     * The one notification to show on a surface: highest priority among those
     * still showable. One at a time — a stack of banners reads as spam.
     */
    fun notification(surface: RemoteNotification.Surface): RemoteNotification? =
        _payload.value.notifications
            .filter { it.surface == surface && isShowable(it) }
            .maxByOrNull { it.priority }

    fun dismiss(notification: RemoteNotification) {
        if (!notification.dismissible) return

        val updated = _dismissedIds.value + notification.id
        _dismissedIds.value = updated
        prefs.edit { putStringSet(DISMISSED_KEY, updated) }

        analytics.logEvent("remote_message_dismissed") {
            param("message_id", notification.id)
        }
    }

    fun logImpression(notification: RemoteNotification) {
        analytics.logEvent("remote_message_shown") {
            param("message_id", notification.id)
            param("surface", notification.surface.rawValue)
        }
    }

    fun logAction(action: RemoteNotification.Action, notification: RemoteNotification) {
        analytics.logEvent("remote_message_action") {
            param("message_id", notification.id)
            param("action", action.kind.rawValue)
        }
    }

    /**
     * Everyone gets the same list from the worker, so all four of these checks
     * are ours to make: drawable at all, meant for this build, still in date,
     * not already waved away.
     */
    private fun isShowable(notification: RemoteNotification): Boolean {
        if (!notification.isRenderable) return false
        if (!notification.isTargeted()) return false
        if (notification.hasExpired()) return false
        if (_dismissedIds.value.contains(notification.id)) return false

        return true
    }

    /**
     * Forget dismissals for notifications the worker has stopped sending, so the
     * list can't grow forever. Ids are never reused for different copy, so one
     * that comes back is the same one the user already waved away.
     */
    private fun pruneDismissals(payload: RemoteNotifications) {
        val live = payload.notifications.map { it.id }.toSet()
        val kept = _dismissedIds.value.intersect(live)

        if (kept == _dismissedIds.value) return

        _dismissedIds.value = kept
        prefs.edit { putStringSet(DISMISSED_KEY, kept) }
    }

    companion object {
        private const val ENDPOINT = "https://cuecard-mobile.thisisnsh.workers.dev/v2/notifications"

        /**
         * Long enough that foregrounding the app repeatedly doesn't hammer the edge,
         * short enough that pulling a bad notification takes effect within a session.
         *
         * Debug builds get a few seconds instead, because the release interval makes
         * testing one impossible: you edit the worker, background and foreground the
         * app, and nothing happens for a quarter of an hour.
         */
        private val MINIMUM_REFRESH_INTERVAL_MS =
            if (BuildConfig.DEBUG) 5L * 1000L else 15L * 60L * 1000L
        private const val TIMEOUT_MS = 5000

        private const val PREFS_NAME = "cuecard_remote_config"

        /**
         * Deliberately not the old `cuecard_remote_config` key: a cached payload
         * from a config-era build is a different shape, and this leaves it be.
         */
        private const val PAYLOAD_KEY = "cuecard_notifications"
        private const val DISMISSED_KEY = "cuecard_remote_config_dismissed"

        @Volatile
        private var instance: RemoteNotificationService? = null

        fun getInstance(context: Context): RemoteNotificationService {
            return instance ?: synchronized(this) {
                instance ?: RemoteNotificationService(context.applicationContext).also { instance = it }
            }
        }
    }
}
