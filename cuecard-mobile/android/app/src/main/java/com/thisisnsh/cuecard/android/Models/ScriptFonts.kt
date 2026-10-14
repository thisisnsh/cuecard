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
