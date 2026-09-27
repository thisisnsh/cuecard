package com.thisisnsh.cuecard.android.models

import kotlinx.serialization.Serializable

/**
 * How a set timer is colored: one color while there's time, another from
 * `warningSeconds` left, and a third from zero on into overtime. With no timer
 * set it counts up in the normal color, and the teleprompter's start delay
 * counts down in another.
 */
@Serializable
data class TimerStyle(
    /** Time left when the warning color starts. Zero skips the warning. */
    val warningSeconds: Int = 10,
    val normalColor: CueColor = CueColor.GREEN,
    val warningColor: CueColor = CueColor.YELLOW,
    val overtimeColor: CueColor = CueColor.RED,
    val countdownColor: CueColor = CueColor.PINK
) {
    /**
     * The color for `remaining` seconds left of `duration`. With no timer set,
     * the time counts up in the normal color.
     */
    fun color(remaining: Int, duration: Int): CueColor = when {
        duration <= 0 -> normalColor
        remaining <= 0 -> overtimeColor
        remaining <= warningSeconds -> warningColor
        else -> normalColor
    }

    companion object {
        val DEFAULT = TimerStyle()
    }
}
