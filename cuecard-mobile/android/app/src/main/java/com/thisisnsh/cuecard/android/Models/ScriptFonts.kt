package com.thisisnsh.cuecard.android.models

import android.graphics.Typeface
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight

/** A cue's face: condensed, so it never reads as part of the script. */
val CueFontFamily: FontFamily = FontFamily(Typeface.create("sans-serif-condensed", Typeface.NORMAL))

/**
 * The script's face for `style`, heavier for bold and slanted for italic.
 * Neither leaves the weight and slant the text is already set in.
 */
fun EmphasisStyle.spanStyle(): SpanStyle = SpanStyle(
    fontWeight = if (isBold) FontWeight.ExtraBold else null,
    fontStyle = if (isItalic) FontStyle.Italic else null
)

/**
 * Chinese, Japanese and Korean, whose glyphs fill the whole em box, so lines
 * set at the usual height crowd together and need more room between them.
 */
object WideScript {
    /** Room between lines in a wide script, where they're set by spacing. */
    fun lineSpacing(size: Float): Float = size * 0.35f

    /** The least a line in a wide script takes up, where it's set by height. */
    fun lineHeight(size: Float): Float = kotlin.math.ceil(size * 1.5f)
}

/** Whether any of it is in a wide script. */
val String.hasWideScript: Boolean
    get() = codePoints().anyMatch { point ->
        Character.isIdeographic(point) ||
            point in 0x3040..0x30FF || // Hiragana, Katakana
            point in 0xAC00..0xD7AF // Hangul
    }
