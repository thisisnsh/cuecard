package com.thisisnsh.cuecard.android.models

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
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

    /** What an exported script is written as. */
    const val EXPORT_MIME_TYPE = "text/plain"

    /**
     * Read a picked file as text, in UTF-8 where it decodes and the platform's
     * own charset where it doesn't. Throws when the file can't be read at all.
     */
    fun readText(context: Context, uri: Uri): String {
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Could not open $uri")

        val utf8 = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)

        return runCatching { utf8.decode(ByteBuffer.wrap(bytes)).toString() }
            .getOrElse { String(bytes) }
    }

    /** Title for an imported script, taken from the file name. */
    fun title(context: Context, uri: Uri): String {
        val displayName = context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
            ?: uri.lastPathSegment

        val name = displayName.orEmpty().substringAfterLast('/').substringBeforeLast('.').trim()
        return name.ifEmpty { "Imported Script" }
    }

    /**
     * File name suggested when exporting, preferring the saved note's title and
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
