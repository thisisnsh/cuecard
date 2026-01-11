package com.thisisnsh.cuecard.android.models

import java.util.regex.Pattern
import kotlin.math.abs
import kotlin.math.min

/**
 * Parser for teleprompter notes with [note content] tags
 */
object TeleprompterParser {

    private val NOTE_PATTERN: Pattern = Pattern.compile("\\[note\\s+([^\\]]+)\\]")

    data class DisplayTextResult(
        val text: String,
        val noteRanges: List<IntRange>
    )

    /**
     * Build display text with [note] tags replaced by their content.
     * Returns the display text and note ranges in display text indices.
     */
    fun buildDisplayText(text: String): DisplayTextResult {
        val matcher = NOTE_PATTERN.matcher(text)
        val builder = StringBuilder()
        val ranges = mutableListOf<IntRange>()
        var lastIndex = 0

        while (matcher.find()) {
            builder.append(text.substring(lastIndex, matcher.start()))
            val content = matcher.group(1) ?: ""
            val start = builder.length
            builder.append(content)
            val end = builder.length
            if (start < end) {
                ranges.add(start until end)
            }
            lastIndex = matcher.end()
        }

        builder.append(text.substring(lastIndex))
        return DisplayTextResult(builder.toString(), ranges)
    }

    /**
     * Parse notes content for teleprompter display
     * Only supports [note content] tags for delivery cues
     */
    fun parseNotes(notes: String): TeleprompterContent {
        val cleanedNotes = cleanText(notes)
        val noteRanges = findNoteRanges(cleanedNotes)
        val displayResult = buildDisplayText(cleanedNotes)
        val words = extractWords(displayResult.text, displayResult.noteRanges)

        return TeleprompterContent(
            fullText = cleanedNotes,
            words = words,
            noteRanges = noteRanges
        )
    }

    /**
     * Clean text for display
     */
    private fun cleanText(text: String): String {
        return text
            .replace("\r\n", "\n")
            .replace("\r", "\n")
            .trim()
    }

    /**
     * Find all [note content] markers in text
     */
    fun findNoteRanges(text: String): List<NoteRange> {
        val ranges = mutableListOf<NoteRange>()
        val matcher = NOTE_PATTERN.matcher(text)

        while (matcher.find()) {
            ranges.add(
                NoteRange(
                    fullStartIndex = matcher.start(),
                    fullEndIndex = matcher.end(),
                    contentStartIndex = matcher.start(1),
                    contentEndIndex = matcher.end(1),
                    content = matcher.group(1) ?: ""
                )
            )
        }

        return ranges
    }

    /**
     * Extract words from text, marking which ones are inside [note] tags
     */
    private fun extractWords(displayText: String, noteRanges: List<IntRange>): List<WordInfo> {
        val words = mutableListOf<WordInfo>()

        // Extract words from display text
        val wordPattern = Pattern.compile("\\S+")
        val matcher = wordPattern.matcher(displayText)

        while (matcher.find()) {
            val word = matcher.group()
            val wordStart = matcher.start()
            val wordEnd = matcher.end()
            val isNote = noteRanges.any { range ->
                range.contains(wordStart) && range.contains(wordEnd - 1)
            }

            words.add(
                WordInfo(
                    text = word,
                    startIndex = wordStart,
                    endIndex = wordEnd,
                    isNote = isNote
                )
            )
        }

        return words
    }

    /**
     * Get display text with [note] tags replaced by just their content
     */
    fun getDisplayText(text: String): String {
        return buildDisplayText(text).text
    }

    /**
     * Format time as mm:ss string
     */
    fun formatTime(seconds: Int): String {
        val isNegative = seconds < 0
        val absSeconds = abs(seconds)
        val minutes = absSeconds / 60
        val secs = absSeconds % 60
        val formatted = String.format("%02d:%02d", minutes, secs)
        return if (isNegative) "-$formatted" else formatted
    }

    /**
     * Calculate word index based on elapsed time and words per minute
     */
    fun calculateCurrentWordIndex(
        elapsedTime: Double,
        totalWords: Int,
        wordsPerMinute: Double
    ): Int {
        val wordsPerSecond = wordsPerMinute / 60.0
        val wordIndex = (elapsedTime * wordsPerSecond).toInt()
        return min(wordIndex, totalWords - 1)
    }

    /**
     * Calculate line index based on elapsed time and lines per minute
     */
    fun calculateCurrentLineIndex(
        elapsedTime: Double,
        totalLines: Int,
        linesPerMinute: Double
    ): Int {
        val linesPerSecond = linesPerMinute / 60.0
        val lineIndex = (elapsedTime * linesPerSecond).toInt()
        return min(lineIndex, totalLines - 1)
    }

    /**
     * Extract note content from a line containing [note ...]
     */
    fun extractNoteContent(line: String): String {
        val matcher = NOTE_PATTERN.matcher(line)
        return if (matcher.find()) {
            matcher.group(1) ?: line
        } else {
            line
        }
    }
}
