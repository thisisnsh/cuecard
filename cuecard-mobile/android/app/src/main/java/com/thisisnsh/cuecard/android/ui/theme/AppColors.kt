package com.thisisnsh.cuecard.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * App colors matching iOS cuecard-app design system
 */
object AppColors {
    // Dark Mode Colors
    object Dark {
        val background = Color(0xFF000000)
        val textPrimary = Color.White
        val textSecondary = Color(0xFFA8A6A6)
        val yellow = Color(0xFFFEBC2E)
        val green = Color(0xFF19C332)
        val pink = Color(0xFFFF6ADF)
        val red = Color(0xFFFF605C)
    }

    // Light Mode Colors
    object Light {
        val background = Color(0xFFF7F4EF)
        val textPrimary = Color(0xFF141312)
        val textSecondary = Color(0xFF5F5B55)
        val yellow = Color(0xFFB36A00)
        val green = Color(0xFF0C7A29)
        val pink = Color(0xFFB82A82)
        val red = Color(0xFFC23A36)
    }

    /**
     * Get background color based on dark mode
     */
    @Composable
    fun background(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.background else Light.background
    }

    /**
     * Get primary text color based on dark mode
     */
    @Composable
    fun textPrimary(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.textPrimary else Light.textPrimary
    }

    /**
     * Get secondary text color based on dark mode
     */
    @Composable
    fun textSecondary(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.textSecondary else Light.textSecondary
    }

    /**
     * Get yellow accent color based on dark mode
     */
    @Composable
    fun yellow(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.yellow else Light.yellow
    }

    /**
     * Get green accent color based on dark mode
     */
    @Composable
    fun green(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.green else Light.green
    }

    /**
     * Get pink accent color based on dark mode
     */
    @Composable
    fun pink(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.pink else Light.pink
    }

    /**
     * Get red accent color based on dark mode
     */
    @Composable
    fun red(isDark: Boolean = isSystemInDarkTheme()): Color {
        return if (isDark) Dark.red else Light.red
    }

    /**
     * Get timer color based on remaining time and total duration
     * - Green: > 20% time remaining (or when totalSeconds <= 0)
     * - Yellow: <= 20% time remaining
     * - Red: overtime (negative remaining time)
     */
    @Composable
    fun timerColor(remainingSeconds: Int, totalSeconds: Int, isDark: Boolean = isSystemInDarkTheme()): Color {
        // Match iOS: return green when no timer duration set
        if (totalSeconds <= 0) {
            return green(isDark)
        }

        val percentage = remainingSeconds.toDouble() / totalSeconds.toDouble()

        return when {
            remainingSeconds < 0 -> red(isDark) // Overtime
            percentage <= 0.2 -> yellow(isDark)
            else -> green(isDark)
        }
    }

    /**
     * Non-composable version for timer color
     */
    fun timerColorValue(remainingSeconds: Int, totalSeconds: Int, isDark: Boolean): Color {
        // Match iOS: return green when no timer duration set
        if (totalSeconds <= 0) {
            return if (isDark) Dark.green else Light.green
        }

        val percentage = remainingSeconds.toDouble() / totalSeconds.toDouble()

        return when {
            remainingSeconds < 0 -> if (isDark) Dark.red else Light.red
            percentage <= 0.2 -> if (isDark) Dark.yellow else Light.yellow
            else -> if (isDark) Dark.green else Light.green
        }
    }
}
