package com.thisisnsh.cuecard.android.models

import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.AppStrings
import androidx.compose.ui.graphics.Color
import kotlinx.serialization.Serializable

/**
 * The color every delivery cue is drawn in.
 *
 * One color covers the whole app — the choice lives in Settings, not in the
 * script — so changing it recolors every cue in every script at once.
 *
 * The stored name is persisted with the settings, so it has to stay stable once
 * shipped: renaming a case resets that user's choice back to the default.
 */
@Serializable
enum class CueColor {
    PINK,
    YELLOW,
    GREEN,
    BLUE,
    PURPLE,
    RED;

    /** The persisted form, matching the iOS raw value exactly. */
    val rawValue: String
        get() = name.lowercase()

    val displayName: String
        get() = AppStrings.get(
            when (this) {
                PINK -> R.string.color_pink
                YELLOW -> R.string.color_yellow
                GREEN -> R.string.color_green
                BLUE -> R.string.color_blue
                PURPLE -> R.string.color_purple
                RED -> R.string.color_red
            }
        )

    fun color(isDark: Boolean): Color = when (this) {
        PINK -> AppColors.pink(isDark)
        YELLOW -> AppColors.yellow(isDark)
        GREEN -> AppColors.green(isDark)
        BLUE -> AppColors.blue(isDark)
        PURPLE -> AppColors.purple(isDark)
        RED -> AppColors.red(isDark)
    }

    companion object {
        /** What cues are drawn in until the user picks something else. */
        val DEFAULT = PINK

        fun fromString(value: String?): CueColor =
            entries.find { it.rawValue == value?.lowercase() } ?: DEFAULT
    }
}
