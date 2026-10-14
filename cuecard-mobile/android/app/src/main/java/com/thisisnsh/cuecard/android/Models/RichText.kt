package com.thisisnsh.cuecard.android.models

/** How a stretch of script is set: bold, italic, both, or neither. */
data class EmphasisStyle(val isBold: Boolean = false, val isItalic: Boolean = false) {
    val isEmpty: Boolean get() = !isBold && !isItalic

    fun union(other: EmphasisStyle): EmphasisStyle =
        EmphasisStyle(isBold || other.isBold, isItalic || other.isItalic)

    /** The marker that writes this style: `*bold*` or `_italic_`. */
    val marker: String get() = if (this == BOLD) "*" else "_"

    companion object {
        val NONE = EmphasisStyle()
        val BOLD = EmphasisStyle(isBold = true)
        val ITALIC = EmphasisStyle(isItalic = true)
    }
}

/** A run of emphasis written in Markdown. */
data class Emphasis(
    val style: EmphasisStyle,
    /** The marker that opens it, `*` or `_`. */
    val open: IntRange,
    /**
     * The marker that closes it. Null while it is still being typed, in which
     * case it runs to the end of the line, or to a cue.
     */
    val close: IntRange?,
    /** What it styles, between the markers. */
    val content: IntRange
) {
    val isClosed: Boolean get() = close != null

    /** Markers and content together. */
    val range: IntRange get() = open.first..maxOf(close?.last ?: content.last, open.last)
}

/**
 * The plain text of some script with its emphasis markers taken out, and the
 * styles that were written with them.
 */
data class StyledText(val runs: List<Run>) {
    data class Run(val text: String, val style: EmphasisStyle)

    val plain: String get() = runs.joinToString("") { it.text }
}

/**
 * Emphasis in a script, written the way chat apps write it:
 *
 * - `*bold*`
 * - `_italic_`
 *
 * Doubled markers — Markdown's `**bold**` and `__italic__` — read the same,
 * so a script brought in from elsewhere keeps its emphasis.
 *
 * Like cues, emphasis doesn't run across lines, and none is read inside a cue.
 * A marker only opens against a word and only closes after one, so `5 * 3`
 * and a `* ` bullet stay as they are; an `_` inside a word, as in
 * `snake_case`, is left alone too.
 */
object RichText {
    private const val STAR = '*'
    private const val UNDERSCORE = '_'

    private data class Opener(val marker: Char, val location: Int, val length: Int)

    /**
     * Every emphasis in the text, closed ones and — at the end of a line — the
     * ones still waiting to be closed. `skipping` are ranges nothing is read
     * inside, such as the cue tags.
     */
    fun emphases(text: String, skipping: List<IntRange> = emptyList()): List<Emphasis> {
        val result = mutableListOf<Emphasis>()
        var lineStart = 0
        while (lineStart <= text.length) {
            val newline = text.indexOf('\n', lineStart)
            val lineEnd = if (newline < 0) text.length else newline
            result += emphasesInLine(text, lineStart, lineEnd, skipping)
            if (newline < 0) break
            lineStart = newline + 1
        }
        return result
    }

    private fun emphasesInLine(text: String, lineStart: Int, end: Int, skipping: List<IntRange>): List<Emphasis> {
        val found = mutableListOf<Emphasis>()
        val stack = mutableListOf<Opener>()
        var index = lineStart

        fun isSkipped(location: Int) = skipping.any { location in it }

        fun character(location: Int): Char? =
            if (location < lineStart || location >= end || isSkipped(location)) null else text[location]

        // What's still open where a cue or the line ends never closed; the
        // editor shows it styled so far, as it's being typed.
        fun endOpeners(location: Int) {
            for (opener in stack) {
                val open = opener.location until opener.location + opener.length
                found += Emphasis(
                    style = style(opener.marker),
                    open = open,
                    close = null,
                    content = open.last + 1 until location
                )
            }
            stack.clear()
        }

        while (index < end) {
            // Emphasis doesn't run into a cue, which is drawn apart from the script.
            if (isSkipped(index)) {
                endOpeners(index)
                index += 1
                continue
            }

            val marker = text[index]
            if (marker != STAR && marker != UNDERSCORE) {
                index += 1
                continue
            }

            var runEnd = index
            while (runEnd < end && text[runEnd] == marker && !isSkipped(runEnd)) runEnd += 1
            val runLength = runEnd - index

            val previous = character(index - 1)
            val next = character(runEnd)
            var canOpen = next?.let { !it.isWhitespace() } ?: false
            var canClose = previous?.let { !it.isWhitespace() } ?: false
            if (marker == UNDERSCORE) {
                canOpen = canOpen && previous?.isLetterOrDigit() != true
                canClose = canClose && next?.isLetterOrDigit() != true
            }

            var used = 0
            if (canClose) {
                // Inner markers close first, so `**_both_**` closes its `_`
                // and then its `**`.
                while (used < runLength) {
                    val openerIndex = stack.indexOfLast { it.marker == marker }
                    if (openerIndex < 0 || stack[openerIndex].length > runLength - used) break
                    val opener = stack[openerIndex]
                    val open = opener.location until opener.location + opener.length
                    val close = index + used until index + used + opener.length
                    found += Emphasis(
                        style = style(marker),
                        open = open,
                        close = close,
                        content = open.last + 1 until close.first
                    )
                    // Anything opened inside it and never closed was never emphasis.
                    while (stack.size > openerIndex) stack.removeAt(stack.size - 1)
                    used += opener.length
                }
            }

            if (canOpen) {
                // `***` opens as `**` then `*`, each closed in turn.
                var location = index + used
                while (location < runEnd) {
                    val length = minOf(2, runEnd - location)
                    stack += Opener(marker, location, length)
                    location += length
                }
            }

            index = runEnd
        }

        endOpeners(end)
        return found
    }

    private fun style(marker: Char): EmphasisStyle =
        if (marker == STAR) EmphasisStyle.BOLD else EmphasisStyle.ITALIC

    /**
     * The text as it reads, closed markers taken out and each stretch carrying
     * its style. A marker never closed is left in as written.
     */
    fun styled(text: String): StyledText {
        val closed = emphases(text).filter { it.isClosed }
        if (closed.isEmpty()) {
            return StyledText(if (text.isEmpty()) emptyList() else listOf(StyledText.Run(text, EmphasisStyle.NONE)))
        }

        val markers = BooleanArray(text.length)
        for (emphasis in closed) {
            for (i in emphasis.open) markers[i] = true
            emphasis.close?.let { for (i in it) markers[i] = true }
        }

        val runs = mutableListOf<StyledText.Run>()
        var start = 0
        var current = EmphasisStyle.NONE
        fun flush(location: Int) {
            if (location <= start) return
            val piece = StringBuilder()
            for (i in start until location) if (!markers[i]) piece.append(text[i])
            if (piece.isNotEmpty()) {
                val last = runs.lastOrNull()
                if (last != null && last.style == current) {
                    runs[runs.size - 1] = last.copy(text = last.text + piece)
                } else {
                    runs += StyledText.Run(piece.toString(), current)
                }
            }
            start = location
        }

        // Styles only change where a marker starts or ends.
        val boundaries = sortedSetOf<Int>()
        for (emphasis in closed) {
            boundaries += emphasis.content.first
            boundaries += emphasis.content.last + 1
        }
        for (boundary in boundaries) {
            flush(boundary)
            current = closed
                .filter { boundary in it.content }
                .fold(EmphasisStyle.NONE) { style, emphasis -> style.union(emphasis.style) }
        }
        flush(text.length)
        return StyledText(runs)
    }

    /** Where the markers of closed emphasis are, which don't show once read. */
    fun markerRanges(text: String, skipping: List<IntRange> = emptyList()): List<IntRange> =
        emphases(text, skipping).flatMap { emphasis ->
            emphasis.close?.let { listOf(emphasis.open, it) } ?: emptyList()
        }

    /** The text with its emphasis markers taken out. */
    fun plain(text: String): String = styled(text).plain
}
