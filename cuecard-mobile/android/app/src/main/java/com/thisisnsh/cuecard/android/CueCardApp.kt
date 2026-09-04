package com.thisisnsh.cuecard.android

import android.app.Activity
import android.app.Application
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
import com.thisisnsh.cuecard.android.services.ThemePreference

class CueCardApplication : Application() {

    lateinit var analytics: FirebaseAnalytics
        private set

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        analytics = Firebase.analytics

        // Configure Crashlytics
        Firebase.crashlytics.setCrashlyticsCollectionEnabled(true)

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
    const val PLAY_STORE = "https://play.google.com/apps/testing/com.thisisnsh.cuecard.android"
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
