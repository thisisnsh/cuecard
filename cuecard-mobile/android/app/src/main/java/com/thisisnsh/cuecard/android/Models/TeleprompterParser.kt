package com.thisisnsh.cuecard.android.models

import java.util.Locale

/**
 * Represents the teleprompter content
 * Text is displayed as a continuous flow, with cues styled where they fall
 */
data class TeleprompterContent(
    /** The full text content (with [cue] tags for styling) */
    val fullText: String,
    /** All words, in reading order (cue words included) */
    val words: List<WordInfo>,
    /** Every cue tag found in the text, for styling */
    val cues: List<CueMatch>
)

/** Information about a single word */
data class WordInfo(
    val text: String,
    /** Whether the word belongs to a cue rather than the spoken script */
    val isCue: Boolean
)

/** A `[cue …]` tag located in a piece of text */
data class CueMatch(
    /** The whole tag, brackets included */
    val range: IntRange,
    /** Just the cue text inside the tag; empty for a cue with nothing written in it yet */
    val contentRange: IntRange,
    val content: String
)

/** A run of a single line: either spoken text or a delivery cue */
sealed class CueSegment {
    data class Text(val text: String) : CueSegment()
    data class Cue(val text: String) : CueSegment()
}

/**
 * Parser for teleprompter scripts with `[cue …]` delivery cues
 *
 * `[cue smile]` is the form to write. `[note smile]` is the older spelling and
 * means exactly the same thing, so scripts written before the rename keep
 * working; importing or exporting rewrites them to `[cue …]`.
 *
 * A tag only counts once its closing bracket is there — `[cue smi` is still
 * plain text, so nothing changes under the user mid-word. Cues can't span lines
 * for the same reason: a stray `[` shouldn't swallow the paragraphs after it.
 *
 * Every cue is drawn in the one color from Settings. An older `[cue:green …]`
 * still parses, but the color name is ignored and dropped on the next import
 * or export.
 */
object TeleprompterParser {

    /** `[cue]` / `[note]`, an optional legacy `:color`, then the cue text */
    private val cueRegex = Regex("""\[(?:cue|note)(?::[A-Za-z]+)?(?:[ \t]+([^\]\n]*))?\]""")

    /**
     * What an empty cue opens with, and closes with. Typing `[` writes both at
     * once, leaving the caret between them.
     */
    const val CUE_TAG_PREFIX = "[cue "
    const val CUE_TAG_SUFFIX = "]"

    /** The tag inserted for a cue that hasn't been written yet. */
    const val EMPTY_CUE_TAG = CUE_TAG_PREFIX + CUE_TAG_SUFFIX

    /** Build the tag for a cue. */
    fun cueTag(text: String): String = CUE_TAG_PREFIX + text.trim() + CUE_TAG_SUFFIX

    /** Parse script content for teleprompter display */
    fun parseNotes(notes: String): TeleprompterContent {
        val cleanedNotes = cleanText(notes)

        return TeleprompterContent(
            fullText = cleanedNotes,
            words = extractWords(cleanedNotes),
            cues = cueMatches(cleanedNotes)
        )
    }

    /** Clean text for display */
    private fun cleanText(text: String): String =
        text.replace("\r\n", "\n").replace("\r", "\n").trim()

    /**
     * Rewrite every cue tag into the canonical `[cue …]` spelling.
     *
     * Used at the file boundary, so a script that leaves the app carries the
     * current syntax and one that arrives is brought up to it.
     */
    fun normalizingTags(text: String): String {
        val result = StringBuilder(text)

        // Back to front, so replacing a tag doesn't shift the ones still to come.
        for (match in cueMatches(text).reversed()) {
            result.replace(match.range.first, match.range.last + 1, cueTag(match.content))
        }

        return result.toString()
    }

    /** Find every cue tag in the text, in order */
    fun cueMatches(text: String): List<CueMatch> =
        cueRegex.findAll(text).map { match ->
            // `[cue]` carries no text group at all; treat it as an empty cue
            // sitting just inside the closing bracket.
            val group = match.groups[1]
            val contentRange = group?.range ?: (match.range.last until match.range.last)

            CueMatch(
                range = match.range,
                contentRange = contentRange,
                content = group?.value ?: ""
            )
        }.toList()

    /**
     * The cue tag the caret is sitting inside, if it is inside one.
     *
     * A caret resting against either bracket counts as outside: that's a spot a
     * new cue can legitimately go, and cues don't nest.
     */
    fun cueTagContaining(location: Int, text: String): CueMatch? =
        cueMatches(text).firstOrNull {
            it.range.first < location && location < it.range.last + 1
        }

    /**
     * Split a single line into spoken text and cue runs.
     *
     * Shared by the teleprompter and the overlay so both render cues identically.
     */
    fun segments(line: String): List<CueSegment> {
        val matches = cueMatches(line)

        if (matches.isEmpty()) {
            return listOf(CueSegment.Text(line))
        }

        val segments = mutableListOf<CueSegment>()
        var lastEnd = 0

        for (match in matches) {
            // Text before the cue
            if (match.range.first > lastEnd) {
                val before = line.substring(lastEnd, match.range.first).trim { it == ' ' || it == '\t' }
                if (before.isNotEmpty()) {
                    segments.add(CueSegment.Text(before))
                }
            }

            segments.add(CueSegment.Cue(match.content))
            lastEnd = match.range.last + 1
        }

        // Text after the last cue
        if (lastEnd < line.length) {
            val after = line.substring(lastEnd).trim { it == ' ' || it == '\t' }
            if (after.isNotEmpty()) {
                segments.add(CueSegment.Text(after))
            }
        }

        return segments
    }

    /**
     * Extract words in reading order, tagging the ones that belong to a cue.
     *
     * Cue words are counted too, matching what the teleprompter lays out.
     */
    private fun extractWords(text: String): List<WordInfo> {
        val words = mutableListOf<WordInfo>()

        for (line in text.split("\n")) {
            if (line.isEmpty()) continue

            for (segment in segments(line)) {
                when (segment) {
                    is CueSegment.Cue ->
                        segment.text.split(Regex("\\s+")).filter { it.isNotEmpty() }.forEach {
                            words.add(WordInfo(text = it, isCue = true))
                        }
                    is CueSegment.Text ->
                        segment.text.split(Regex("\\s+")).filter { it.isNotEmpty() }.forEach {
                            words.add(WordInfo(text = it, isCue = false))
                        }
                }
            }
        }

        return words
    }

    /** Format time as mm:ss string */
    fun formatTime(seconds: Int): String {
        val isNegative = seconds < 0
        val absSeconds = kotlin.math.abs(seconds)
        val minutes = absSeconds / 60
        val secs = absSeconds % 60
        val formatted = String.format(Locale.US, "%02d:%02d", minutes, secs)
        return if (isNegative) "-$formatted" else formatted
    }

    /** Calculate word index based on elapsed time and words per minute */
    fun calculateCurrentWordIndex(
        elapsedTime: Double,
        totalWords: Int,
        wordsPerMinute: Double
    ): Int {
        val wordsPerSecond = wordsPerMinute / 60.0
        val wordIndex = (elapsedTime * wordsPerSecond).toInt()
        return minOf(wordIndex, totalWords - 1)
    }

    /** Calculate line index based on elapsed time and lines per minute */
    fun calculateCurrentLineIndex(
        elapsedTime: Double,
        totalLines: Int,
        linesPerMinute: Double
    ): Int {
        val linesPerSecond = linesPerMinute / 60.0
        val lineIndex = (elapsedTime * linesPerSecond).toInt()
        return minOf(lineIndex, totalLines - 1)
    }
}
