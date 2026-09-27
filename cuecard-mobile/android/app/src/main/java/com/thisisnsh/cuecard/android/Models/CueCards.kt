package com.thisisnsh.cuecard.android.models

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import java.text.BreakIterator
import kotlinx.serialization.Serializable

/**
 * What the editor writes and the Play button opens: a script read as it
 * scrolls, or a deck of cards moved through one at a time.
 *
 * The raw value is persisted with the settings, so it has to stay stable.
 */
@Serializable
enum class ScriptMode(val rawValue: String, val displayName: String) {
    TELEPROMPTER("teleprompter", "Teleprompter"),
    CARDS("cards", "Cards");

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
data class CueCardRun(val text: String, val isCue: Boolean)

/** The card as one text, cues in their color. */
fun List<CueCardRun>.annotated(primary: Color, cue: Color): AnnotatedString =
    buildAnnotatedString {
        for (run in this@annotated) {
            pushStyle(SpanStyle(color = if (run.isCue) cue else primary))
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
     * `]` around it don't, and neither does blank space at either end.
     */
    fun measure(card: IntRange, text: String, cues: List<CueMatch>, limit: Int): CardMeasure {
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
            if (isTagSyntax) continue

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
    fun measure(card: String, limit: Int): CardMeasure =
        measure(card.indices, card, TeleprompterParser.cueMatches(card), limit)

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

        fun append(text: String, isCue: Boolean) {
            if (text.isEmpty()) return
            val last = runs.lastOrNull()
            if (last != null && last.isCue == isCue) {
                runs[runs.size - 1] = last.copy(text = last.text + text)
            } else {
                runs.add(CueCardRun(text, isCue))
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
                        append(segment.text, isCue = false)
                    }
                    is CueSegment.Cue -> {
                        val cue = segment.text.trim(' ', '\t')
                        if (cue.isEmpty()) continue
                        if (!isFirst) append(" ", isCue = false)
                        append(cue, isCue = true)
                    }
                }
                isFirst = false
            }
        }
        return runs
    }

    private fun normalizingLineBreaks(text: String): String =
        text.replace("\r\n", "\n").replace("\r", "\n")
}
