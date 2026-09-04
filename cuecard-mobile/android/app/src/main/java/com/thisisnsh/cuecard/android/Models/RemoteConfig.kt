package com.thisisnsh.cuecard.android.models

import com.thisisnsh.cuecard.android.BuildConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.net.URI
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

/**
 * The payload behind `GET /v2/config` on the mobile worker.
 *
 * Decoding is deliberately forgiving. Every flag defaults to its permissive
 * value, so a build that can't reach the worker behaves exactly as shipped, and
 * anything a newer worker adds that this build doesn't understand is skipped
 * rather than taking the whole payload down with it. The failure mode we want is
 * always "nothing to show", never "app is broken".
 */
data class RemoteConfig(
    val flags: Flags = Flags(),
    val messages: List<RemoteMessage> = emptyList()
) {
    companion object {
        val EMPTY = RemoteConfig()

        /** Lenient by design: see the class comment. */
        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        /**
         * Decode a worker response. One unreadable message drops out without
         * taking the rest of the payload with it — the parallel to the iOS
         * `Skipping<Wrapped>` wrapper.
         */
        fun decode(raw: String): RemoteConfig? {
            val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return null

            val flags = (root["flags"] as? JsonObject)
                ?.let { runCatching { json.decodeFromJsonElement(FlagsDTO.serializer(), it) }.getOrNull() }
                ?.toFlags()
                ?: Flags()

            val messages = (root["messages"] as? JsonArray).orEmpty().mapNotNull { element ->
                runCatching { json.decodeFromJsonElement(RemoteMessageDTO.serializer(), element) }
                    .getOrNull()
                    ?.toMessage()
            }

            return RemoteConfig(flags = flags, messages = messages)
        }
    }
}

// MARK: - Flags

/** Behaviour the app reads silently. Only `minSupportedVersion` draws any UI. */
data class Flags(
    val minSupportedVersion: String = "0.0.0",
    val updateURL: String? = null,
    val features: Features = Features()
)

/**
 * Kill switches. All on by default — turning one off is the only thing that has
 * any effect, which keeps an unreachable worker from costing anyone a feature.
 */
data class Features(
    val pip: Boolean = true,
    val appleSignIn: Boolean = true,
    val googleSignIn: Boolean = true
)

// MARK: - Messages

/** One thing to show, on one surface. */
data class RemoteMessage(
    val id: String,
    val surface: Surface,
    val severity: Severity = Severity.INFO,
    val priority: Int = 0,
    val title: String,
    val body: String? = null,
    val actions: List<Action> = emptyList(),
    val dismissible: Boolean = true,
    val expiresAt: Instant? = null,
    val rolloutPercent: Int = 100,
    val match: Match? = null
) {
    /**
     * Where the message is rendered. A surface this build doesn't know about
     * means the message can't be drawn at all, so it's dropped in decoding.
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
     * Narrows the audience. The worker filters on this too; the client re-checks
     * because a cached payload can outlive the app version it was fetched for.
     */
    data class Match(
        val platforms: List<String>? = null,
        val minVersion: String? = null,
        val maxVersion: String? = null,
        val minBuild: Int? = null,
        val locales: List<String>? = null
    ) {
        fun admits(platform: String, version: String, build: Int, locale: String): Boolean {
            if (platforms != null && !platforms.contains(platform)) return false
            if (minVersion != null && AppVersion.compare(version, minVersion) < 0) return false
            if (maxVersion != null && AppVersion.compare(version, maxVersion) > 0) return false
            if (minBuild != null && build < minBuild) return false

            // Language alone: "en" covers en-US, en-GB and the rest.
            if (locales != null) {
                val language = locale.split("-").firstOrNull()?.lowercase() ?: locale.lowercase()
                val admitted = locales.any { it.split("-").firstOrNull()?.lowercase() == language }
                if (!admitted) return false
            }

            return true
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

    fun hasExpired(now: Instant = Instant.now()): Boolean {
        val expiry = expiresAt ?: return false
        return !expiry.isAfter(now)
    }

    companion object {
        /**
         * Hosts a message is allowed to link to, mirrored from the worker. A link
         * anywhere else means someone got at the response, so the message is
         * dropped rather than shown without its action.
         */
        val allowedHosts = setOf(
            "cuecard.dev", "www.cuecard.dev", "play.google.com", "github.com"
        )
    }
}

// MARK: - Version numbers

object AppVersion {
    val current: String
        get() = BuildConfig.VERSION_NAME

    val build: Int
        get() = BuildConfig.VERSION_CODE

    /**
     * Compare two dotted versions numerically. Missing components count as zero,
     * so "1.2" and "1.2.0" are the same version.
     */
    fun compare(lhs: String, rhs: String): Int {
        val left = lhs.split(".").map { it.toIntOrNull() ?: 0 }
        val right = rhs.split(".").map { it.toIntOrNull() ?: 0 }

        for (index in 0 until maxOf(left.size, right.size)) {
            val l = left.getOrElse(index) { 0 }
            val r = right.getOrElse(index) { 0 }
            if (l != r) return if (l < r) -1 else 1
        }

        return 0
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
private data class FeaturesDTO(
    val pip: Boolean? = null,
    val appleSignIn: Boolean? = null,
    val googleSignIn: Boolean? = null
) {
    fun toFeatures() = Features(
        pip = pip ?: true,
        appleSignIn = appleSignIn ?: true,
        googleSignIn = googleSignIn ?: true
    )
}

@Serializable
private data class FlagsDTO(
    val minSupportedVersion: String? = null,
    @SerialName("updateURL") val updateUrl: String? = null,
    val features: FeaturesDTO? = null
) {
    fun toFlags() = Flags(
        minSupportedVersion = minSupportedVersion ?: "0.0.0",
        updateURL = updateUrl,
        features = features?.toFeatures() ?: Features()
    )
}

@Serializable
private data class ActionDTO(
    val kind: String,
    val label: String,
    val url: String? = null
) {
    /**
     * An action kind we don't recognise is one we can't carry out, and the action
     * is usually the point of the message — so this throws, and the message goes
     * with it.
     */
    fun toAction(): RemoteMessage.Action {
        val parsed = RemoteMessage.Action.Kind.from(kind)
            ?: throw IllegalArgumentException("Unknown action kind: $kind")
        return RemoteMessage.Action(kind = parsed, label = label, url = url)
    }
}

@Serializable
private data class MatchDTO(
    val platforms: List<String>? = null,
    val minVersion: String? = null,
    val maxVersion: String? = null,
    val minBuild: Int? = null,
    val locales: List<String>? = null
) {
    fun toMatch() = RemoteMessage.Match(
        platforms = platforms,
        minVersion = minVersion,
        maxVersion = maxVersion,
        minBuild = minBuild,
        locales = locales
    )
}

@Serializable
private data class RemoteMessageDTO(
    val id: String,
    val surface: String,
    val severity: String? = null,
    val priority: Int? = null,
    val title: String,
    val body: String? = null,
    val actions: List<ActionDTO>? = null,
    val dismissible: Boolean? = null,
    val expiresAt: String? = null,
    val rolloutPercent: Int? = null,
    val match: MatchDTO? = null
) {
    /**
     * An id, a surface and a title are the message. Without all three there's
     * nothing to draw or remember, so this throws and the message is skipped.
     */
    fun toMessage(): RemoteMessage {
        val parsedSurface = RemoteMessage.Surface.from(surface)
            ?: throw IllegalArgumentException("Unknown surface: $surface")

        return RemoteMessage(
            id = id,
            surface = parsedSurface,
            severity = RemoteMessage.Severity.from(severity) ?: RemoteMessage.Severity.INFO,
            priority = priority ?: 0,
            title = title,
            body = body,
            actions = actions?.map { it.toAction() } ?: emptyList(),
            dismissible = dismissible ?: true,
            expiresAt = expiresAt?.let { parseISO8601(it) },
            rolloutPercent = rolloutPercent ?: 100,
            match = match?.toMatch()
        )
    }
}
