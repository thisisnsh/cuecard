package com.thisisnsh.cuecard.android.models

import androidx.compose.ui.graphics.Color

/**
 * App colors matching cuecard-desktop design system
 *
 * Every accessor is a plain function taking `isDark`: the overlay renderer and
 * the parser-adjacent code read colors outside composition, so none of these can
 * be `@Composable`.
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
        val blue = Color(0xFF4DA6FF)
        val purple = Color(0xFFB07CFF)
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
        val blue = Color(0xFF1462C4)
        val purple = Color(0xFF6B3FBE)
    }

    fun background(isDark: Boolean): Color = if (isDark) Dark.background else Light.background

    fun textPrimary(isDark: Boolean): Color = if (isDark) Dark.textPrimary else Light.textPrimary

    fun textSecondary(isDark: Boolean): Color = if (isDark) Dark.textSecondary else Light.textSecondary

    fun yellow(isDark: Boolean): Color = if (isDark) Dark.yellow else Light.yellow

    fun green(isDark: Boolean): Color = if (isDark) Dark.green else Light.green

    fun pink(isDark: Boolean): Color = if (isDark) Dark.pink else Light.pink

    fun red(isDark: Boolean): Color = if (isDark) Dark.red else Light.red

    fun blue(isDark: Boolean): Color = if (isDark) Dark.blue else Light.blue

    fun purple(isDark: Boolean): Color = if (isDark) Dark.purple else Light.purple

    /**
     * Timer color based on remaining time and total duration
     * - Green: > 20% time remaining (or when no timer is set)
     * - Yellow: <= 20% time remaining
     * - Red: overtime
     */
    fun timerColor(remainingSeconds: Int, totalSeconds: Int, isDark: Boolean): Color {
        if (totalSeconds <= 0) return green(isDark)

        val percentage = remainingSeconds.toDouble() / totalSeconds.toDouble()

        return when {
            remainingSeconds < 0 -> red(isDark)
            percentage <= 0.2 -> yellow(isDark)
            else -> green(isDark)
        }
    }
}
