package com.thisisnsh.cuecard.android.modifiers

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.thisisnsh.cuecard.android.models.AppColors

/** The capsule shape SwiftUI's `Capsule()` draws. */
val Capsule: Shape = RoundedCornerShape(percent = 50)

/**
 * The glass look the app's floating controls sit on, ported from the SwiftUI
 * `Shape.glassed()`.
 *
 * Compose has no backdrop blur — `Modifier.blur` blurs a composable's own content,
 * not what sits behind it — so `.ultraThinMaterial` is approximated by a scrim of
 * the background color. That is the one place the pixel-match is an approximation
 * rather than a copy; the gradient and the stroke are exact.
 */
fun Modifier.glassed(shape: Shape = Capsule, isDark: Boolean): Modifier {
    val primary = AppColors.textPrimary(isDark)

    return this
        .clip(shape)
        // Standing in for `.ultraThinMaterial`.
        .background(AppColors.background(isDark).copy(alpha = 0.6f), shape)
        .background(
            brush = Brush.linearGradient(
                colors = listOf(
                    primary.copy(alpha = 0.08f),
                    primary.copy(alpha = 0.05f),
                    primary.copy(alpha = 0.01f),
                    Color.Transparent,
                    Color.Transparent,
                    Color.Transparent
                ),
                start = Offset.Zero,
                end = Offset.Infinite
            ),
            shape = shape
        )
        .border(width = 0.7.dp, color = primary.copy(alpha = 0.2f), shape = shape)
}

/**
 * Fades a scrolling script into the background at its top and bottom edges, so
 * lines arrive and leave instead of being cut off mid-stroke.
 *
 * The fades are painted in the background color rather than masked, so they cover
 * the text without touching whatever floats above them.
 */
fun Modifier.scriptEdgeFade(isDark: Boolean, top: Dp, bottom: Dp): Modifier =
    drawWithContent {
        drawContent()

        val color = AppColors.background(isDark)
        val topHeight = top.toPx()
        val bottomHeight = bottom.toPx()

        if (topHeight > 0f) {
            drawRect(
                brush = Brush.verticalGradient(
                    0f to color,
                    0.45f to color.copy(alpha = 0.9f),
                    1f to color.copy(alpha = 0f),
                    startY = 0f,
                    endY = topHeight
                ),
                size = Size(size.width, topHeight)
            )
        }

        if (bottomHeight > 0f) {
            drawRect(
                brush = Brush.verticalGradient(
                    0f to color.copy(alpha = 0f),
                    0.55f to color.copy(alpha = 0.9f),
                    1f to color,
                    startY = size.height - bottomHeight,
                    endY = size.height
                ),
                topLeft = Offset(0f, size.height - bottomHeight),
                size = Size(size.width, bottomHeight)
            )
        }
    }
