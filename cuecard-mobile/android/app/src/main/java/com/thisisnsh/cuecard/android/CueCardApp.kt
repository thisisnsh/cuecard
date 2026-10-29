package com.thisisnsh.cuecard.android

import androidx.annotation.StringRes
import androidx.annotation.PluralsRes
import android.net.Uri
import android.content.Context
import android.app.Activity
import android.app.Application
import android.os.Build
import android.os.Bundle
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.crashlytics.ktx.crashlytics
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.services.ScriptImages
import com.thisisnsh.cuecard.android.services.ThemePreference

class CueCardApplication : Application() {

    lateinit var analytics: FirebaseAnalytics
        private set

    override fun onCreate() {
        super.onCreate()
        AppStrings.context = this
        ScriptImages.init(this)
        FirebaseApp.initializeApp(this)
        analytics = Firebase.analytics

        // Configure Crashlytics
        Firebase.crashlytics.setCrashlyticsCollectionEnabled(true)

        // The language the app is showing, which can differ from the phone's.
        // One event per language, so the Events report counts each one's users
        // as it is. Event names can't hold a hyphen, so pt-BR becomes pt_br.
        val language = getString(R.string.language_code).lowercase().replace('-', '_')
        analytics.logEvent("app_language_$language", null)

        // Log app open event
        analytics.logEvent(FirebaseAnalytics.Event.APP_OPEN, null)
    }
}

// MARK: - Analytics Helper

/**
 * Analytics helper for consistent event logging across the app.
 * Mirrors iOS AnalyticsEvents structure.
 */
object AnalyticsEvents {
    private val analytics = Firebase.analytics
    private val crashlytics = Firebase.crashlytics

    fun logButtonClick(buttonName: String, screen: String, parameters: Map<String, Any>? = null) {
        val params = Bundle().apply {
            putString("button_name", buttonName)
            putString("screen_name", screen)
            parameters?.forEach { (key, value) ->
                when (value) {
                    is String -> putString(key, value)
                    is Int -> putInt(key, value)
                    is Long -> putLong(key, value)
                    is Double -> putDouble(key, value)
                    is Boolean -> putBoolean(key, value)
                }
            }
        }
        analytics.logEvent("button_click", params)
        crashlytics.log("Button clicked: $buttonName on $screen")
    }

    /** Any other event, with the same parameter handling as a button click. */
    fun logEvent(name: String, parameters: Map<String, Any>? = null) {
        val params = Bundle().apply {
            parameters?.forEach { (key, value) ->
                when (value) {
                    is String -> putString(key, value)
                    is Int -> putInt(key, value)
                    is Long -> putLong(key, value)
                    is Double -> putDouble(key, value)
                    is Boolean -> putBoolean(key, value)
                }
            }
        }
        analytics.logEvent(name, params)
    }

    fun logScreenView(screenName: String) {
        analytics.logEvent(FirebaseAnalytics.Event.SCREEN_VIEW) {
            param(FirebaseAnalytics.Param.SCREEN_NAME, screenName)
        }
        crashlytics.log("Screen viewed: $screenName")
    }

    fun log(message: String) {
        crashlytics.log(message)
    }
}

// MARK: - External Links

object AppLinks {
    const val SOURCE_CODE = "https://github.com/thisisnsh/cuecard"
    const val PRIVACY_POLICY = "https://cuecard.dev/privacy/"
    val PLAY_STORE = "https://play.google.com/store/apps/details?id=${BuildConfig.APPLICATION_ID}"

    /** An email to support about a translation, with the language's code. */
    fun translationReport(language: String): String =
        supportEmail("CueCard Translation Mistake ($language)", AppStrings.get(R.string.translation_report_body))

    /** An email to support about something that's broken. */
    val bugReport: String
        get() = supportEmail("CueCard Bug Report", AppStrings.get(R.string.bug_report_body))

    /** An email to support asking for something new. */
    val featureRequest: String
        get() = supportEmail("CueCard Feature Request", AppStrings.get(R.string.feature_request_body))

    /**
     * An email to support. The subject stays English so emails sort together
     * whatever the language.
     */
    private fun supportEmail(subject: String, body: String): String =
        "mailto:support@cuecard.dev?subject=" + Uri.encode(subject) +
            "&body=" + Uri.encode(body + "\n\n—\n" + emailFooter)

    /** The app's version, platform and device, so support knows what the sender runs. */
    private val emailFooter: String
        get() = "CueCard ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}"

    /** What goes out when someone shares the app. */
    val shareMessage: String get() = AppStrings.get(R.string.share_message, PLAY_STORE)
}

// MARK: - Strings

/**
 * The app's text for code that runs outside a composable, which has
 * `stringResource` instead. Read from the application, which takes the app's
 * language the same as its screens do.
 */
object AppStrings {
    internal lateinit var context: Context

    fun get(@StringRes id: Int, vararg args: Any): String = context.getString(id, *args)

    fun plural(@PluralsRes id: Int, count: Int, vararg args: Any): String =
        context.resources.getQuantityString(id, count, *args)
}

// MARK: - Theme

/**
 * Whether the app is drawing in dark mode, which is what every `AppColors` call
 * needs. The parallel to SwiftUI's `@Environment(\.colorScheme)`, and it follows
 * the Theme setting rather than the system, the way `preferredColorScheme` does.
 */
val LocalIsDarkTheme = staticCompositionLocalOf { true }

@Composable
fun CueCardTheme(
    themePreference: ThemePreference = ThemePreference.SYSTEM,
    content: @Composable () -> Unit
) {
    val isDark = when (themePreference) {
        ThemePreference.SYSTEM -> isSystemInDarkTheme()
        ThemePreference.LIGHT -> false
        ThemePreference.DARK -> true
    }

    val colorScheme = if (isDark) {
        darkColorScheme(
            primary = AppColors.Dark.green,
            secondary = AppColors.Dark.pink,
            tertiary = AppColors.Dark.yellow,
            background = AppColors.Dark.background,
            surface = AppColors.Dark.background,
            onPrimary = AppColors.Dark.background,
            onSecondary = AppColors.Dark.textPrimary,
            onTertiary = AppColors.Dark.background,
            onBackground = AppColors.Dark.textPrimary,
            onSurface = AppColors.Dark.textPrimary,
            error = AppColors.Dark.red,
            onError = AppColors.Dark.textPrimary
        )
    } else {
        lightColorScheme(
            primary = AppColors.Light.green,
            secondary = AppColors.Light.pink,
            tertiary = AppColors.Light.yellow,
            background = AppColors.Light.background,
            surface = AppColors.Light.background,
            onPrimary = AppColors.Light.background,
            onSecondary = AppColors.Light.textPrimary,
            onTertiary = AppColors.Light.background,
            onBackground = AppColors.Light.textPrimary,
            onSurface = AppColors.Light.textPrimary,
            error = AppColors.Light.red,
            onError = AppColors.Light.textPrimary
        )
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !isDark
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !isDark
            @Suppress("DEPRECATION")
            window.statusBarColor = colorScheme.background.toArgb()
            @Suppress("DEPRECATION")
            window.navigationBarColor = colorScheme.background.toArgb()
        }
    }

    CompositionLocalProvider(LocalIsDarkTheme provides isDark) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content
        )
    }
}
