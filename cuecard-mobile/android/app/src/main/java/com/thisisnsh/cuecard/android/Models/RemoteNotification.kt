package com.thisisnsh.cuecard.android.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonObject
import java.net.URI
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

/**
 * The payload behind `GET /v2/notifications` on the mobile worker. Mirrors
 * `src/types.ts` there — change both together.
 *
 * Decoding is deliberately forgiving. Anything a newer worker adds that this
 * build doesn't understand is skipped rather than taking the whole payload down
 * with it. The failure mode we want is always "nothing to show", never "app is
 * broken".
 */
data class RemoteNotifications(
    val notifications: List<RemoteNotification> = emptyList()
) {
    companion object {
        val EMPTY = RemoteNotifications()

        /** Lenient by design: see the class comment. */
        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        /**
         * Decode a worker response. One unreadable notification drops out without
         * taking the rest of the payload with it — the parallel to the iOS
         * `Skipping<Wrapped>` wrapper.
         */
        fun decode(raw: String): RemoteNotifications? {
            val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return null

            val notifications = (root["notifications"] as? JsonArray).orEmpty().mapNotNull { element ->
                runCatching { json.decodeFromJsonElement(RemoteNotificationDTO.serializer(), element) }
                    .getOrNull()
                    ?.toNotification()
            }

            return RemoteNotifications(notifications = notifications)
        }
    }
}

/** One thing to show, on one surface. */
data class RemoteNotification(
    val id: String,
    val surface: Surface,
    val severity: Severity = Severity.INFO,
    val priority: Int = 0,
    val title: String,
    val body: String? = null,
    val actions: List<Action> = emptyList(),
    val dismissible: Boolean = true,
    val expiresAt: Instant? = null
) {
    /**
     * Where it's rendered. A surface this build doesn't know about is one it
     * can't draw, so the notification is dropped in decoding.
     */
    enum class Surface(val rawValue: String) {
        HOME_BANNER("homeBanner"),
        SETTINGS_ROW("settingsRow");

        companion object {
            fun from(value: String?): Surface? = entries.find { it.rawValue == value }
        }
    }

    enum class Severity(val rawValue: String) {
        INFO("info"),
        WARNING("warning"),
        CRITICAL("critical");

        companion object {
            fun from(value: String?): Severity? = entries.find { it.rawValue == value }
        }
    }

    data class Action(
        val kind: Kind,
        val label: String,
        val url: String? = null
    ) {
        enum class Kind(val rawValue: String) {
            OPEN_URL("openURL"),
            APP_STORE("appStore"),
            DISMISS("dismiss");

            companion object {
                fun from(value: String?): Kind? = entries.find { it.rawValue == value }
            }
        }
    }

    /**
     * Whether this is safe and sensible to draw: a title, no more than two
     * actions, every link pointing somewhere we recognise, and some way out.
     */
    val isRenderable: Boolean
        get() {
            if (title.trim().isEmpty()) return false
            if (actions.size > 2) return false

            for (action in actions.filter { it.kind == Action.Kind.OPEN_URL }) {
                val url = action.url ?: return false
                val host = runCatching { URI(url).host }.getOrNull() ?: return false
                if (!allowedHosts.contains(host)) return false
            }

            return dismissible || actions.isNotEmpty()
        }

    /**
     * Expiry is enforced here alone — the worker serves the same list to everyone
     * and doesn't filter on it.
     */
    fun hasExpired(now: Instant = Instant.now()): Boolean {
        val expiry = expiresAt ?: return false
        return !expiry.isAfter(now)
    }

    companion object {
        /**
         * Hosts a notification is allowed to link to. The worker no longer checks
         * these itself, so this is the only enforcement: a link anywhere else
         * means the notification is dropped rather than shown without its action.
         */
        val allowedHosts = setOf(
            "cuecard.dev", "www.cuecard.dev", "play.google.com", "github.com"
        )
    }
}

// MARK: - Decoding

/**
 * The worker writes plain ISO 8601; accept fractional seconds too in case that
 * ever changes underneath us.
 */
private fun parseISO8601(value: String): Instant? =
    runCatching { OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant() }
        .recoverCatching { Instant.parse(value) }
        .getOrNull()

@Serializable
private data class ActionDTO(
    val kind: String,
    val label: String,
    val url: String? = null
) {
    /**
     * An action kind we don't recognise is one we can't carry out, and the action
     * is usually the point — so this throws, and the notification goes with it.
     */
    fun toAction(): RemoteNotification.Action {
        val parsed = RemoteNotification.Action.Kind.from(kind)
            ?: throw IllegalArgumentException("Unknown action kind: $kind")
        return RemoteNotification.Action(kind = parsed, label = label, url = url)
    }
}

@Serializable
private data class RemoteNotificationDTO(
    val id: String,
    val surface: String,
    val severity: String? = null,
    val priority: Int? = null,
    val title: String,
    val body: String? = null,
    val actions: List<ActionDTO>? = null,
    val dismissible: Boolean? = null,
    val expiresAt: String? = null
) {
    /**
     * An id, a surface and a title are the notification. Without all three there's
     * nothing to draw or remember, so this throws and it is skipped.
     */
    fun toNotification(): RemoteNotification {
        val parsedSurface = RemoteNotification.Surface.from(surface)
            ?: throw IllegalArgumentException("Unknown surface: $surface")

        return RemoteNotification(
            id = id,
            surface = parsedSurface,
            severity = RemoteNotification.Severity.from(severity) ?: RemoteNotification.Severity.INFO,
            priority = priority ?: 0,
            title = title,
            body = body,
            actions = actions?.map { it.toAction() } ?: emptyList(),
            dismissible = dismissible ?: true,
            expiresAt = expiresAt?.let { parseISO8601(it) }
        )
    }
}
