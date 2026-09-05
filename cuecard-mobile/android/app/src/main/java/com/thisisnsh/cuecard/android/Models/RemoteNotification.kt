package com.thisisnsh.cuecard.android.models

import com.thisisnsh.cuecard.android.BuildConfig
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

/**
 * The build asking for notifications, for the `targets` check below. Fixed for
 * the life of the process.
 */
data class AppBuild(
    val platform: String,
    val version: List<Int>?,
    val build: Int?
) {
    companion object {
        /**
         * `platform` is matched as a plain string rather than an enum: a platform
         * this build doesn't recognise simply never matches, so the worker can
         * start targeting a new one without breaking anything shipped. `version`
         * is null if the version name turns out to be unreadable, in which case
         * no version range matches and a targeted notification passes us by.
         */
        val CURRENT = AppBuild(
            platform = "android",
            version = parseVersionComponents(BuildConfig.VERSION_NAME),
            build = BuildConfig.VERSION_CODE
        )
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
    val targets: List<Target> = emptyList(),
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
     * One audience a notification is for: a platform, optionally narrowed to a
     * range of versions or builds. Every bound is inclusive.
     */
    data class Target(
        val platform: String,
        val minVersion: List<Int>? = null,
        val maxVersion: List<Int>? = null,
        val minBuild: Int? = null,
        val maxBuild: Int? = null
    ) {
        fun matches(app: AppBuild): Boolean {
            if (platform != app.platform) return false

            // A bound this build can't be measured against doesn't match. A
            // target we can't evaluate should reach nobody rather than everybody
            // — the wrong audience is the whole thing targeting exists to avoid.
            if (minVersion != null || maxVersion != null) {
                val version = app.version ?: return false

                if (minVersion != null && compareVersions(version, minVersion) < 0) return false
                if (maxVersion != null && compareVersions(version, maxVersion) > 0) return false
            }

            if (minBuild != null || maxBuild != null) {
                val build = app.build ?: return false

                if (minBuild != null && build < minBuild) return false
                if (maxBuild != null && build > maxBuild) return false
            }

            return true
        }
    }

    /**
     * Whether this build is in the audience. No targets means everyone, which is
     * what every notification was before targeting existed.
     *
     * Enforced here alone: the worker serves one list and leaves the filtering to
     * us, so a build too old to know about `targets` shows the notification to
     * everyone regardless.
     */
    fun isTargeted(app: AppBuild = AppBuild.CURRENT): Boolean {
        if (targets.isEmpty()) return true

        return targets.any { it.matches(app) }
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
 * "1.3.0" -> [1, 3, 0]. Null for anything that isn't one to four plain numbers
 * separated by dots — a version we can't read is one we won't guess at.
 */
private fun parseVersionComponents(value: String): List<Int>? {
    val parts = value.split(".")
    if (parts.size !in 1..4) return null

    return parts.map { part ->
        if (part.isEmpty() || !part.all { it in '0'..'9' }) return null
        part.toIntOrNull() ?: return null
    }
}

/**
 * Component-wise, padding the shorter side with zeroes, so 1.10.0 lands above
 * 1.9.0 — which a plain string comparison gets backwards.
 */
private fun compareVersions(lhs: List<Int>, rhs: List<Int>): Int {
    for (index in 0 until maxOf(lhs.size, rhs.size)) {
        val left = lhs.getOrElse(index) { 0 }
        val right = rhs.getOrElse(index) { 0 }

        if (left != right) return left.compareTo(right)
    }

    return 0
}

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
private data class TargetDTO(
    val platform: String,
    val minVersion: String? = null,
    val maxVersion: String? = null,
    val minBuild: Int? = null,
    val maxBuild: Int? = null
) {
    fun toTarget(): RemoteNotification.Target = RemoteNotification.Target(
        platform = platform,
        minVersion = minVersion?.let(::parseBound),
        maxVersion = maxVersion?.let(::parseBound),
        minBuild = minBuild,
        maxBuild = maxBuild
    )

    /**
     * A version string we can't parse is a bound we can't honour, so this throws
     * and the notification goes with it — quieter than showing it to the builds
     * the bound was written to exclude.
     */
    private fun parseBound(value: String): List<Int> =
        parseVersionComponents(value) ?: throw IllegalArgumentException("Unreadable version: $value")
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
    val targets: List<TargetDTO>? = null,
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
            // A target we can't read would quietly widen the audience to
            // everyone, so it takes the notification with it for the same reason.
            targets = targets?.map { it.toTarget() } ?: emptyList(),
            expiresAt = expiresAt?.let { parseISO8601(it) }
        )
    }
}
