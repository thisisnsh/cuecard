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
     * iOS's `.plainText` does; RTF is read as plain text, since there is no
     * `NSAttributedString` here to unwrap it with.
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

        return runCatching { utf8.decode(ByteBuffer.wrap(bytes)).toString() }
            .getOrElse { String(bytes) }
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
