package com.thisisnsh.cuecard.android.models

import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.AppStrings
import androidx.annotation.StringRes
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.TextUnit
import java.text.BreakIterator
import kotlinx.serialization.Serializable

/**
 * What the editor writes and the Play button opens: a script read as it
 * scrolls, or a deck of cards moved through one at a time.
 *
 * The raw value is persisted with the settings, so it has to stay stable.
 */
@Serializable
enum class ScriptMode(val rawValue: String, @StringRes private val displayNameRes: Int) {
    TELEPROMPTER("teleprompter", R.string.teleprompter),
    CARDS("cards", R.string.cards);

    val displayName: String get() = AppStrings.get(displayNameRes)

    companion object {
        fun fromString(value: String?): ScriptMode =
            entries.find { it.rawValue == value } ?: TELEPROMPTER
    }
}

/** How much of a card shows, and where it runs past its limit. */
data class CardMeasure(
    /**
     * Characters the card shows: its text and cues, without the tag syntax or
     * the blank space around it.
     */
    val length: Int,
    /** From the first character past the limit to the end of the card. */
    val overflow: IntRange?
)

/** A stretch of a card: spoken text, or a cue drawn in the cue color. */
data class CueCardRun(
    val text: String,
    val isCue: Boolean,
    /** Bold or italic, as written in the script. */
    val style: EmphasisStyle = EmphasisStyle.NONE
)

/**
 * The card as one text, cues in their color and set narrower than the script
 * so they never read as part of it. `cueFontSize`, if given, sets them smaller
 * as well.
 */
fun List<CueCardRun>.annotated(primary: Color, cue: Color, cueFontSize: TextUnit = TextUnit.Unspecified): AnnotatedString =
    buildAnnotatedString {
        for (run in this@annotated) {
            pushStyle(
                if (run.isCue) {
                    SpanStyle(color = cue, fontFamily = CueFontFamily, fontSize = cueFontSize)
                } else {
                    run.style.spanStyle().copy(color = primary)
                }
            )
            append(run.text)
            pop()
        }
    }

/**
 * Cards mode's `[separator]` tag, which ends one card and starts the next.
 *
 * The editor shows each card on its own, and the tag is only written where the
 * deck is stored, imported and exported. The teleprompter reads a separator as
 * a line break.
 */
object CueCards {
    const val SEPARATOR_TAG = "[separator]"

    /** Characters a card holds before the editor marks the rest as too long. */
    const val CHARACTER_LIMIT = 280

    private val separatorRegex = Regex("""\[separator\]""", RegexOption.IGNORE_CASE)

    /** Every separator in the text, in order. */
    fun separatorRanges(text: String): List<IntRange> =
        separatorRegex.findAll(text).map { it.range }.toList()

    /** The stretches of text between separators, blank ones included. */
    fun cardRanges(text: String): List<IntRange> {
        val ranges = mutableListOf<IntRange>()
        var start = 0
        for (separator in separatorRanges(text)) {
            ranges.add(start until separator.first)
            start = separator.last + 1
        }
        ranges.add(start until text.length)
        return ranges
    }

    /** The cards of a script, trimmed, with blank ones left out. */
    fun cards(text: String): List<String> {
        val normalized = normalizingLineBreaks(text)
        return cardRanges(normalized)
            .map { normalized.substring(it).trim() }
            .filter { it.isNotEmpty() }
    }

    /** Separators swapped for line breaks, for the teleprompter. */
    fun removingSeparators(text: String): String = separatorRegex.replace(text, "\n")

    /** Every separator written in the canonical lowercase spelling. */
    fun normalizingSeparators(text: String): String = separatorRegex.replace(text, SEPARATOR_TAG)

    /**
     * Count what a card shows against `limit`. Cue text counts, the `[cue` and
     * `]` around it don't, nor do emphasis `markers`, and neither does blank
     * space at either end. An image doesn't count, and nor does an `[anchor]`.
     */
    fun measure(
        card: IntRange,
        text: String,
        cues: List<CueMatch>,
        markers: List<IntRange> = emptyList(),
        images: List<IntRange> = emptyList(),
        anchors: List<IntRange> = emptyList(),
        limit: Int
    ): CardMeasure {
        var count = 0
        var solidCount = 0
        var overflowStart: Int? = null

        val characters = BreakIterator.getCharacterInstance()
        characters.setText(text)
        var start = card.first
        while (start <= card.last) {
            val end = characters.following(start).let { if (it == BreakIterator.DONE) text.length else it }
                .coerceAtMost(card.last + 1)
            val character = text.substring(start, end)
            val location = start
            start = end

            val isTagSyntax = cues.any { location in it.range && location !in it.contentRange }
            if (isTagSyntax || markers.any { location in it } || images.any { location in it } ||
                anchors.any { location in it }
            ) continue

            val isBlank = character.isBlank()
            if (isBlank && count == 0) continue
            count += 1
            if (isBlank) continue
            solidCount = count
            if (count > limit && overflowStart == null) {
                overflowStart = location
            }
        }

        return CardMeasure(length = solidCount, overflow = overflowStart?.let { it..card.last })
    }

    /** How much of a single card shows against `limit`. */
    fun measure(card: String, limit: Int): CardMeasure {
        val cues = TeleprompterParser.cueMatches(card)
        return measure(
            card.indices, card, cues,
            markers = RichText.markerRanges(card, skipping = cues.map { it.range }),
            images = TeleprompterParser.imageMatches(card).map { it.range },
            anchors = TeleprompterParser.anchorRanges(card),
            limit = limit
        )
    }

    /**
     * The cards as the editor shows them: blank ones kept, so a card just added
     * stays put, and the line breaks around each separator left out.
     */
    fun editableCards(text: String): List<String> {
        val normalized = normalizingLineBreaks(text)
        return cardRanges(normalized).map { normalized.substring(it).trim('\n') }
    }

    /**
     * The script for a deck, a separator on its own line between each card. A
     * single blank card is no script at all.
     */
    fun script(cards: List<String>): String {
        if (cards.size == 1 && cards[0].isBlank()) return ""
        return cards.joinToString("\n$SEPARATOR_TAG\n")
    }

    /** A card as runs of text and cue, the way the app draws it. */
    fun runs(card: String): List<CueCardRun> {
        val runs = mutableListOf<CueCardRun>()

        fun append(text: String, isCue: Boolean, style: EmphasisStyle = EmphasisStyle.NONE) {
            if (text.isEmpty()) return
            val last = runs.lastOrNull()
            if (last != null && last.isCue == isCue && last.style == style) {
                runs[runs.size - 1] = last.copy(text = last.text + text)
            } else {
                runs.add(CueCardRun(text, isCue, style))
            }
        }

        card.split("\n").forEachIndexed { lineIndex, line ->
            if (lineIndex > 0) append("\n", isCue = false)

            var isFirst = true
            for (segment in TeleprompterParser.segments(line)) {
                when (segment) {
                    is CueSegment.Text -> {
                        if (segment.text.isEmpty()) continue
                        if (!isFirst) append(" ", isCue = false)
                        for (run in RichText.styled(segment.text).runs) {
                            append(run.text, isCue = false, style = run.style)
                        }
                    }
                    is CueSegment.Cue -> {
                        val cue = segment.text.trim(' ', '\t')
                        if (cue.isEmpty()) continue
                        if (!isFirst) append(" ", isCue = false)
                        append(cue, isCue = true)
                    }
                    // Drawn as a block of its own; see `CardBlock`.
                    is CueSegment.Image -> continue
                    // Cards are turned, not jumped through.
                    CueSegment.Anchor -> continue
                }
                isFirst = false
            }
        }
        return runs
    }

    private fun normalizingLineBreaks(text: String): String =
        text.replace("\r\n", "\n").replace("\r", "\n")
}

/** One stretch of a card as the app draws it: words, or an image. */
sealed class CardBlock {
    data class Text(val runs: List<CueCardRun>) : CardBlock()
    /** `name` is the image's file name. */
    data class Image(val name: String) : CardBlock()

    companion object {
        /**
         * A card's words broken around its images, each image a block of its
         * own however it was written.
         */
        fun blocks(card: String): List<CardBlock> {
            val blocks = mutableListOf<CardBlock>()
            var start = 0

            fun appendText(end: Int) {
                val text = card.substring(start, end).trim()
                if (text.isNotEmpty()) blocks.add(Text(CueCards.runs(text)))
            }

            for (match in TeleprompterParser.imageMatches(card)) {
                appendText(match.range.first)
                blocks.add(Image(match.name))
                start = match.range.last + 1
            }
            appendText(card.length)
            return blocks
        }
    }
}
