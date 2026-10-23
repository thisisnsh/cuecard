package com.thisisnsh.cuecard.android.services

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.thisisnsh.cuecard.android.BuildConfig
import com.thisisnsh.cuecard.android.models.ScriptFile
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Scripts with images, to and from TextBundle (textbundle.org): a folder with
 * the script as Markdown in `text.md` and its images in `assets/`, each shown
 * with `![](assets/name.jpg)`. Bear, Ulysses and other Markdown apps read and
 * write them. A TextPack is the folder zipped into a single file, which is how
 * a script with images is shared.
 *
 * Cues, card separators and emphasis stay as the script writes them.
 *
 * Everything here reads or writes files, so it's called off the main thread.
 */
object TextPack {
    /**
     * The largest TextPack imported, in bytes. A script's images are kept at a
     * size that leaves this far more than enough.
     */
    const val MAX_FILE_SIZE = 100L * 1024 * 1024

    /** What a TextPack is sent as: there's no type of its own other apps know. */
    const val MIME_TYPE = "application/zip"

    /** The types the document picker offers for a TextPack. */
    val importableMimeTypes = arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")

    /** The folder shared files are written to, which the file provider hands out. */
    fun shareFolder(context: Context): File = File(context.cacheDir, "shared")

    /** Whether the picked file is a TextPack rather than a text file. */
    fun isPackage(context: Context, uri: Uri): Boolean {
        val name = runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
        }.getOrNull() ?: uri.lastPathSegment.orEmpty()
        if (name.lowercase().endsWith(".textpack")) return true
        // Saved by a browser or a chat app, it may have lost its name, but it's still a ZIP.
        val signature = runCatching {
            context.contentResolver.openInputStream(uri)?.use { stream -> ByteArray(4).also { stream.read(it) } }
        }.getOrNull() ?: return false
        return signature.contentEquals(byteArrayOf(0x50, 0x4b, 0x03, 0x04))
    }

    // MARK: - Writing

    /**
     * A script and its images as a TextPack, in a folder of its own in the
     * share folder, named for the script.
     */
    fun write(context: Context, title: String?, content: String): File {
        val name = ScriptFile.suggestedFileName(title, content)
        val bundle = "$name.textbundle/"
        val info = """{"creatorIdentifier":"${BuildConfig.APPLICATION_ID}","transient":false,""" +
            """"type":"net.daringfireball.markdown","version":2}"""

        // An image that's missing keeps its tag, so it's at least still marked.
        val markdown = StringBuilder(TeleprompterParser.normalizingTags(content))
        val assets = sortedMapOf<String, ByteArray>()
        for (match in TeleprompterParser.imageMatches(markdown.toString()).reversed()) {
            val data = assets[match.name] ?: ScriptImages.data(match.name) ?: continue
            assets[match.name] = data
            markdown.replace(match.range.first, match.range.last + 1, "![](assets/${match.name})")
        }

        // Packs shared a day or more ago have long since been sent.
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        shareFolder(context).listFiles().orEmpty()
            .filter { it.lastModified() < cutoff }
            .forEach { it.deleteRecursively() }

        val folder = File(shareFolder(context), UUID.randomUUID().toString()).apply { mkdirs() }
        val file = File(folder, "$name.textpack")
        ZipOutputStream(file.outputStream().buffered()).use { zip ->
            zip.putNextEntry(ZipEntry(bundle))
            zip.closeEntry()
            zip.putNextEntry(ZipEntry(bundle + "info.json"))
            zip.write(info.toByteArray())
            zip.closeEntry()
            zip.putNextEntry(ZipEntry(bundle + "text.md"))
            zip.write(markdown.toString().toByteArray())
            zip.closeEntry()
            if (assets.isNotEmpty()) {
                zip.putNextEntry(ZipEntry(bundle + "assets/"))
                zip.closeEntry()
                for ((asset, data) in assets) {
                    zip.putNextEntry(ZipEntry(bundle + "assets/" + asset))
                    zip.write(data)
                    zip.closeEntry()
                }
            }
        }
        return file
    }

    // MARK: - Reading

    /** Something in the package that couldn't be read as a script. */
    class Unreadable : Exception()

    /**
     * The script in a picked TextPack. Its images are kept in the store and
     * placed with `[image …]` tags; one that can't be found or read is left as
     * the Markdown wrote it. Throws `ScriptFile.FileTooLarge` rather than read
     * a TextPack over `MAX_FILE_SIZE`.
     */
    fun readScript(context: Context, uri: Uri): String {
        val size = runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
            }
        }.getOrNull()
        if (size != null && size > MAX_FILE_SIZE) throw ScriptFile.FileTooLarge(size)

        val files = context.contentResolver.openInputStream(uri)?.use { entries(it) } ?: throw Unreadable()
        val textPath = textPath(files.keys) ?: throw Unreadable()
        val markdown = files.getValue(textPath).toString(Charsets.UTF_8)

        // Images are found from the folder the text is in.
        val root = textPath.substringBeforeLast('/', "").let { if (it.isEmpty()) "" else "$it/" }
        val script = StringBuilder(markdown)
        for (match in markdownImageRegex.findAll(markdown).toList().reversed()) {
            val relative = bundlePath(match.groupValues[1]) ?: continue
            val image = files[root + relative] ?: continue
            val name = ScriptImages.add(image) ?: continue
            script.replace(match.range.first, match.range.last + 1, TeleprompterParser.imageTag(name))
        }
        return script.toString()
    }

    /** `![description](path "title")`, the path in group 1. A path with a space in it is written `<like this>`. */
    private val markdownImageRegex = Regex("""!\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"\n]*")?\s*\)""")

    /**
     * A path written in the Markdown, as one within the bundle. Null for a link
     * elsewhere, or a path that climbs out of the bundle.
     */
    private fun bundlePath(path: String): String? {
        val decoded = runCatching { Uri.decode(path) }.getOrDefault(path)
        if (decoded.contains(':') || decoded.startsWith("/")) return null
        val components = decoded.split("/").filter { it.isNotEmpty() && it != "." }
        if (components.isEmpty() || ".." in components) return null
        return components.joinToString("/")
    }

    /**
     * The script's Markdown: `text.md` or the like, at the top or in the one
     * folder the bundle was zipped as.
     */
    private fun textPath(paths: Set<String>): String? =
        paths.filter { path ->
            val parts = path.split("/")
            parts.size <= 2 && !path.startsWith("__MACOSX/") &&
                parts.last().lowercase() in setOf("text.md", "text.markdown", "text.txt", "text.text")
        }.minByOrNull { it.count { character -> character == '/' } }

    /** The files in a ZIP, by their paths within it, held to `MAX_FILE_SIZE` in all. */
    private fun entries(stream: InputStream): Map<String, ByteArray> {
        val files = mutableMapOf<String, ByteArray>()
        var total = 0L
        ZipInputStream(stream.buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.isDirectory) continue
                val data = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = zip.read(buffer)
                    if (count < 0) break
                    data.write(buffer, 0, count)
                    total += count
                    if (total > MAX_FILE_SIZE) throw ScriptFile.FileTooLarge(total)
                }
                files.putIfAbsent(entry.name, data.toByteArray())
            }
        }
        return files
    }
}
