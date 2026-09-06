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
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.thisisnsh.cuecard.android.models.AppColors

/** The capsule shape SwiftUI's `Capsule()` draws. */
val Capsule: Shape = RoundedCornerShape(percent = 50)

/**
 * The look the app's floating controls sit on, ported from the SwiftUI
 * `Shape.glassed()`.
 *
 * Compose has no backdrop blur — `Modifier.blur` blurs a composable's own content,
 * not what sits behind it — so there is nothing here for a scrim of the page color
 * to frost. Painting one only tinted the page with itself and left the controls
 * reading as flat outlines. Instead the surface is the page lifted toward the text
 * color: an opaque fill that stands off the page the way the material does on iOS.
 *
 * `tint` gives a control its own fill — the green play buttons — and then nothing
 * is painted over it, so the color stays the color it was asked for. The gradient
 * and the stroke are the SwiftUI ones either way.
 */
fun Modifier.glassed(
    shape: Shape = Capsule,
    isDark: Boolean,
    tint: Color? = null
): Modifier {
    val primary = AppColors.textPrimary(isDark)
    val surface = tint ?: primary
        .copy(alpha = if (isDark) 0.16f else 0.10f)
        .compositeOver(AppColors.background(isDark))

    return this
        .clip(shape)
        .background(surface, shape)
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
