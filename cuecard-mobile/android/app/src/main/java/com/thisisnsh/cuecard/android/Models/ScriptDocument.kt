package com.thisisnsh.cuecard.android.models

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * Helpers for moving scripts between the editor and files on disk, through the
 * Storage Access Framework.
 */
object ScriptFile {

    /**
     * Types the importer accepts. Any text subtype covers .txt and .md the way
     * iOS's `.plainText` does; RTF is unwrapped by `markdown(rtf)`.
     */
    val importableMimeTypes = arrayOf("text/*", "application/rtf")

    /**
     * The largest file read as a script, in bytes. Far more than any script runs
     * to, and little enough to read into memory without trouble.
     */
    const val MAX_FILE_SIZE = 10L * 1024 * 1024

    /** A file over `MAX_FILE_SIZE`, which is left unread. */
    class FileTooLarge(val size: Long) : Exception()

    /**
     * Read a picked file as text, in UTF-8 where it decodes and the platform's
     * own charset where it doesn't. Throws when the file can't be read at all,
     * and `FileTooLarge` rather than read a file over `MAX_FILE_SIZE`.
     */
    fun readText(context: Context, uri: Uri): String {
        val size = fileSize(context, uri)
        if (size != null && size > MAX_FILE_SIZE) throw FileTooLarge(size)

        val bytes = context.contentResolver.openInputStream(uri)?.use { readBytes(it) }
            ?: throw IllegalStateException("Could not open $uri")

        val utf8 = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)

        val text = runCatching { utf8.decode(ByteBuffer.wrap(bytes)).toString() }
            .getOrElse { String(bytes) }
        return if (text.trimStart().startsWith("{\\rtf")) markdown(rtf = text) else text
    }

    /**
     * Rich text as the script would be written: bold and italic kept as
     * `*bold*` and `_italic_`, everything else dropped.
     */
    fun markdown(rtf: String): String {
        val pieces = mutableListOf<Pair<StringBuilder, EmphasisStyle>>()
        for ((text, style) in RtfReader(rtf).read()) {
            // A change of color or size alone doesn't split a stretch of one style.
            val last = pieces.lastOrNull()
            if (last != null && last.second == style) last.first.append(text) else pieces += StringBuilder(text) to style
        }

        return pieces.joinToString("") { (builder, style) ->
            val text = builder.toString()
            if (style.isEmpty) return@joinToString text
            val open = (if (style.isBold) EmphasisStyle.BOLD.marker else "") +
                (if (style.isItalic) EmphasisStyle.ITALIC.marker else "")
            val close = open.reversed()
            // Markers go around the words of each line, not the space around them.
            text.split("\n").joinToString("\n") { line ->
                val words = line.trim(' ', '\t')
                if (words.isEmpty()) return@joinToString line
                val start = line.indexOf(words)
                line.replaceRange(start, start + words.length, open + words + close)
            }
        }
    }

    /** A file's size, or null where whatever serves it doesn't say. */
    private fun fileSize(context: Context, uri: Uri): Long? =
        runCatching {
            context.contentResolver
                .query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
                }
        }.getOrNull()

    /**
     * Not every file says how big it is up front, so the limit is held to while
     * reading too.
     */
    private fun readBytes(stream: InputStream): ByteArray {
        val bytes = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            bytes.write(buffer, 0, count)
            if (bytes.size() > MAX_FILE_SIZE) throw FileTooLarge(bytes.size().toLong())
        }
        return bytes.toByteArray()
    }

    /** Title for an imported script, taken from the file name. */
    fun title(context: Context, uri: Uri): String {
        val displayName = context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
            ?: uri.lastPathSegment

        return title(displayName.orEmpty().substringAfterLast('/'))
    }

    /** Title for a script, taken from its file's name. */
    fun title(fileName: String): String {
        val name = (if (fileName.contains('.')) fileName.substringBeforeLast('.') else fileName).trim()
        return name.ifEmpty { "Imported Script" }
    }

    /**
     * File name suggested for a script, preferring the saved note's title and
     * falling back to the script's first line.
     */
    fun suggestedFileName(title: String?, content: String): String {
        val candidates = listOf(title, content.split("\n").firstOrNull())

        for (candidate in candidates) {
            val name = sanitized(candidate ?: "")
            if (name.isNotEmpty()) {
                return name.take(60)
            }
        }

        return "Speech"
    }

    private fun sanitized(name: String): String {
        val illegal = "/\\:?%*|\"<>"
        return name.map { if (illegal.contains(it)) ' ' else it }
            .joinToString("")
            .trim()
    }
}

/**
 * Reads the text of an RTF document and the bold and italic it's set in — as
 * much of RTF as a script needs. Groups, paragraph breaks, escaped and Unicode
 * characters are read; tables of fonts and colors, pictures, and anything else
 * that isn't the document's text are skipped.
 */
private class RtfReader(private val rtf: String) {
    private data class State(
        val bold: Boolean = false,
        val italic: Boolean = false,
        /** Inside a group whose content isn't text, such as the font table. */
        val skips: Boolean = false,
        /** How many characters stand in for each `\u` character, for readers without Unicode. */
        val unicodeFallback: Int = 1
    )

    private val skippedDestinations = setOf(
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "headerl", "headerr", "headerf",
        "footer", "footerl", "footerr", "footerf", "footnote", "object", "fldinst", "themedata",
        "colorschememapping", "datastore", "latentstyles", "listtable", "listoverridetable", "rsidtbl",
        "generator", "xmlnstbl", "mmathPr", "filetbl", "revtbl", "expandedcolortbl"
    )

    private val windows1252 = java.nio.charset.Charset.forName("windows-1252")
    private var index = 0
    private var state = State()
    private val stack = ArrayDeque<State>()
    private val output = mutableListOf<Pair<String, EmphasisStyle>>()

    fun read(): List<Pair<String, EmphasisStyle>> {
        while (index < rtf.length) {
            val character = rtf[index]
            index += 1
            when (character) {
                '{' -> stack.addLast(state)
                '}' -> state = stack.removeLastOrNull() ?: state
                '\\' -> readControl()
                '\r', '\n' -> Unit
                else -> emit(character.toString())
            }
        }
        return output
    }

    private fun emit(text: String) {
        if (state.skips || text.isEmpty()) return
        output += text to EmphasisStyle(state.bold, state.italic)
    }

    private fun readControl() {
        val symbol = rtf.getOrNull(index) ?: return
        if (!symbol.isLetter()) {
            index += 1
            when (symbol) {
                '\\', '{', '}' -> emit(symbol.toString())
                '\'' -> {
                    val hex = rtf.substring(index, minOf(index + 2, rtf.length))
                    index += hex.length
                    hex.toIntOrNull(16)?.let { emit(String(byteArrayOf(it.toByte()), windows1252)) }
                }
                '*' -> state = state.copy(skips = true)
                '~' -> emit("\u00A0")
                '_' -> emit("\u2011")
                '\r', '\n' -> emit("\n")
            }
            return
        }

        val wordStart = index
        while (index < rtf.length && rtf[index].isLetter()) index += 1
        val word = rtf.substring(wordStart, index)
        val parameterStart = index
        if (index < rtf.length && rtf[index] == '-') index += 1
        while (index < rtf.length && rtf[index].isDigit()) index += 1
        val parameter = rtf.substring(parameterStart, index).toIntOrNull()
        // A space after a control word only ends it.
        if (index < rtf.length && rtf[index] == ' ') index += 1

        when (word) {
            "b" -> state = state.copy(bold = parameter != 0)
            "i" -> state = state.copy(italic = parameter != 0)
            "plain" -> state = state.copy(bold = false, italic = false)
            "par", "line", "sect", "page" -> emit("\n")
            "tab" -> emit("\t")
            "emdash" -> emit("\u2014")
            "endash" -> emit("\u2013")
            "bullet" -> emit("\u2022")
            "lquote" -> emit("\u2018")
            "rquote" -> emit("\u2019")
            "ldblquote" -> emit("\u201C")
            "rdblquote" -> emit("\u201D")
            "uc" -> state = state.copy(unicodeFallback = parameter ?: 1)
            "u" -> {
                val code = parameter ?: return
                emit((if (code < 0) code + 65536 else code).toChar().toString())
                skipFallback()
            }
            else -> if (word in skippedDestinations) state = state.copy(skips = true)
        }
    }

    /** Skip the characters written after a `\u` for readers that can't show it. */
    private fun skipFallback() {
        var remaining = state.unicodeFallback
        while (remaining > 0 && index < rtf.length) {
            when (rtf[index]) {
                '{', '}' -> return
                '\\' -> {
                    if (rtf.getOrNull(index + 1) == '\'') index += 4 else return
                }
                else -> index += 1
            }
            remaining -= 1
        }
    }
}
