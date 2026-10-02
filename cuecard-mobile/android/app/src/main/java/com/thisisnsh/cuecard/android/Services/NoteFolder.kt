package com.thisisnsh.cuecard.android.services

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import androidx.core.content.edit
import androidx.core.net.toUri
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.ScriptFile
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.OutputStream

/**
 * A folder the user picked in Files where saved notes are also kept, one text
 * file each. It sits outside the app, so the notes stay if the app is deleted,
 * and edits made to the files outside the app come back in on the next sync.
 *
 * The folder is reached through the Storage Access Framework, so everything
 * here but `isChosen` talks to another process and is called off the main thread.
 */
class NoteFolder(private val context: Context) {
    /**
     * What's needed to match a file to its note, kept in a hidden index in the
     * folder so a reinstalled app can pick the notes back up.
     */
    @Serializable
    private data class Entry(
        val file: String,
        val title: String,
        val mode: String,
        val createdAt: Long,
        /** The note's `updatedAt` when the file was last in step with it. */
        val noteUpdatedAt: Long,
        /** The file's modification date then, to tell when it's been edited. */
        val fileModifiedAt: Long? = null
    )

    /** What a sync found changed in the folder, for the app to take in. */
    data class Changes(
        val updated: List<SavedNote> = emptyList(),
        val deleted: List<String> = emptyList(),
        /** Files over `ScriptFile.MAX_FILE_SIZE`, by name. They're left unread. */
        val tooLarge: List<String> = emptyList()
    )

    /** The folder couldn't be listed or written to when it was picked. */
    class Unusable : Exception()

    /** One thing in the folder, as its listing describes it. */
    private data class Item(
        val uri: Uri,
        val name: String,
        val isDirectory: Boolean,
        val modifiedAt: Long?,
        val size: Long?
    )

    /** The folder open for one piece of work, with its listing kept in step. */
    private inner class Folder(val tree: Uri, val items: MutableMap<String, Item>) {
        val root: Uri = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

        fun file(name: String): Item? = items[name]?.takeIf { !it.isDirectory }

        /** Write `text` to the file called `name`, making the file if it isn't there. */
        fun write(name: String, text: String, mimeType: String): Item? = runCatching {
            val uri = file(name)?.uri
                ?: DocumentsContract.createDocument(resolver, root, mimeType, name)
                ?: return null
            output(uri)?.use { it.write(text.toByteArray()) } ?: return null
            // Asked for again, since the folder may have named the file its own way.
            describe(uri)?.also { items[it.name] = it }
        }.getOrNull()

        /** Open a file to write over what it holds, for folders that only know how to write. */
        private fun output(uri: Uri): OutputStream? =
            runCatching { resolver.openOutputStream(uri, "wt") }.getOrNull()
                ?: resolver.openOutputStream(uri, "w")

        fun rename(item: Item, name: String): Item? = runCatching {
            val uri = DocumentsContract.renameDocument(resolver, item.uri, name) ?: return null
            describe(uri)?.also {
                items.remove(item.name)
                items[it.name] = it
            }
        }.getOrNull()

        fun delete(name: String) {
            val item = file(name) ?: return
            if (runCatching { DocumentsContract.deleteDocument(resolver, item.uri) }.getOrDefault(false)) {
                items.remove(name)
            }
        }
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val resolver = context.contentResolver
    private val json = Json { ignoreUnknownKeys = true }

    val isChosen: Boolean
        get() = prefs.contains(FOLDER_KEY)

    /** The folder's name, or null if there's none or it can't be reached. */
    val name: String?
        get() {
            val tree = resolve() ?: return null
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            return describe(root)?.name
        }

    /**
     * Start keeping notes in `uri`, a folder picked with the document picker.
     * Throws `Unusable` for one that notes can't be kept in.
     */
    fun choose(uri: Uri) {
        val previous = prefs.getString(FOLDER_KEY, null)?.toUri()
        runCatching { resolver.takePersistableUriPermission(uri, PERMISSIONS) }

        // Notes are matched to their files through the index, so a folder that
        // can't hold one would be filled with new copies on every sync.
        val folder = open(uri)
        if (folder == null || (folder.file(INDEX_NAME) == null && !writeIndex(emptyMap(), folder))) {
            if (uri != previous) release(uri)
            throw Unusable()
        }

        prefs.edit { putString(FOLDER_KEY, uri.toString()) }
        if (previous != null && previous != uri) release(previous)
    }

    /** Stop using the folder. The files in it are left alone. */
    fun forget() {
        prefs.getString(FOLDER_KEY, null)?.toUri()?.let(::release)
        prefs.edit { remove(FOLDER_KEY) }
    }

    /** Write a note to its file, renaming the file if the title changed. */
    fun write(note: SavedNote) {
        withFolder { folder ->
            val index = readIndex(folder) ?: return@withFolder
            write(note, index, folder)
            writeIndex(index, folder)
        }
    }

    fun remove(id: String) {
        withFolder { folder ->
            val index = readIndex(folder) ?: return@withFolder
            val entry = index.remove(id) ?: return@withFolder
            folder.delete(entry.file)
            writeIndex(index, folder)
        }
    }

    /** Delete every file CueCard wrote. Anything else in the folder stays. */
    fun removeAll() {
        withFolder { folder ->
            val index = readIndex(folder) ?: return@withFolder
            index.values.forEach { folder.delete(it.file) }
            writeIndex(emptyMap(), folder)
        }
    }

    /**
     * Bring the folder and the app's notes in step: files edited, added, renamed
     * or deleted outside the app come back as `Changes`, and notes the folder
     * doesn't have yet are written to it. Whichever side changed last wins.
     */
    fun sync(notes: List<SavedNote>): Changes =
        withFolder { folder -> sync(notes, folder) } ?: Changes()

    // MARK: - Syncing

    private fun sync(notes: List<SavedNote>, folder: Folder): Changes {
        // Nothing is written before the folder is known to hold an index, and
        // if the index can't be read, nothing can be told about the folder, so
        // nothing is changed on either side.
        if (folder.file(INDEX_NAME) == null && !writeIndex(emptyMap(), folder)) return Changes()
        val index = readIndex(folder) ?: return Changes()

        val updated = mutableListOf<SavedNote>()
        val deleted = mutableListOf<String>()
        val originalIndex = index.toMap()
        val appNotes = notes.associateBy { it.id }
        val files = folder.items.values
            .filter { !it.isDirectory && !it.name.startsWith(".") && fileExtension(it.name) in TEXT_EXTENSIONS }
            .map { it.name }
            .toSet()
        // Reading one of these fails, which leaves it and its note as they are.
        val tooLarge = files
            .filter { (folder.file(it)?.size ?: 0) > ScriptFile.MAX_FILE_SIZE }
            .sorted()

        val claimed = mutableSetOf<String>()
        val missing = mutableListOf<String>()

        for ((id, entry) in originalIndex) {
            val item = if (entry.file in files) folder.file(entry.file) else null
            if (item == null) {
                missing.add(id)
                continue
            }
            claimed.add(entry.file)

            val modified = item.modifiedAt
            val fileChanged = modified != entry.fileModifiedAt
            val app = appNotes[id]

            if (app != null && app.updatedAt > entry.noteUpdatedAt &&
                (!fileChanged || app.updatedAt >= (modified ?: Long.MIN_VALUE))
            ) {
                write(app, index, folder)
            } else if (fileChanged || app == null) {
                // Edited outside the app, or a note this install doesn't have
                // yet, as after the app is reinstalled.
                val content = readContent(item) ?: continue
                val note = SavedNote(
                    id = id,
                    title = entry.title,
                    content = content,
                    mode = ScriptMode.fromString(entry.mode),
                    createdAt = entry.createdAt,
                    updatedAt = if (fileChanged) modified ?: System.currentTimeMillis() else entry.noteUpdatedAt
                )
                if (app != note) updated.add(note)
                index[id] = entry.copy(noteUpdatedAt = note.updatedAt, fileModifiedAt = modified)
            }
        }

        val unknown = (files - claimed).toSortedSet()

        // Every file gone at once is more likely a folder that hasn't loaded
        // than one the user emptied, so notes are only let go of while some
        // of their files are still there.
        if (missing.isNotEmpty() && claimed.isNotEmpty()) {
            for (id in missing) {
                val entry = index[id] ?: continue
                // A file renamed outside the app still holds the same text.
                val app = appNotes[id]
                val renamed = app?.let { note ->
                    unknown.firstOrNull { name -> folder.file(name)?.let(::readContent) == note.content }
                }
                if (app != null && renamed != null) {
                    unknown.remove(renamed)
                    val note = app.copy(title = ScriptFile.title(renamed))
                    updated.add(note)
                    index[id] = Entry(
                        file = renamed,
                        title = note.title,
                        mode = entry.mode,
                        createdAt = entry.createdAt,
                        noteUpdatedAt = note.updatedAt,
                        fileModifiedAt = folder.file(renamed)?.modifiedAt
                    )
                } else {
                    index.remove(id)
                    if (app != null) deleted.add(id)
                }
            }
        }

        // Files added outside the app become new notes.
        for (name in unknown) {
            val item = folder.file(name) ?: continue
            val content = readContent(item) ?: continue
            val modified = item.modifiedAt ?: System.currentTimeMillis()
            val mode = if (CueCards.separatorRanges(content).isEmpty()) ScriptMode.TELEPROMPTER else ScriptMode.CARDS
            val note = SavedNote(
                title = ScriptFile.title(name),
                content = content,
                mode = mode,
                createdAt = modified,
                updatedAt = modified
            )
            updated.add(note)
            index[note.id] = Entry(
                file = name,
                title = note.title,
                mode = mode.rawValue,
                createdAt = modified,
                noteUpdatedAt = modified,
                fileModifiedAt = item.modifiedAt
            )
        }

        // Notes the folder doesn't have yet, as when it's first chosen.
        for (note in notes) {
            if (index[note.id] == null && note.id !in deleted) write(note, index, folder)
        }

        if (index != originalIndex) writeIndex(index, folder)
        return Changes(updated, deleted, tooLarge)
    }

    // MARK: - Files

    private fun write(note: SavedNote, index: MutableMap<String, Entry>, folder: Folder) {
        val existing = index[note.id]
        var file = existing?.file
        val current = file?.let(folder::file)
        if (current != null && existing?.title != note.title) {
            // Renamed in the app, so the file follows, keeping its extension.
            val taken = takenNames(folder, index) - current.name.lowercase()
            val renamed = uniqueName(note, fileExtension(current.name), taken)
            if (renamed != current.name) {
                folder.rename(current, renamed)?.let { file = it.name }
            }
        }
        val name = file ?: uniqueName(note, "txt", takenNames(folder, index))
        val written = folder.write(name, note.content, TEXT_MIME_TYPE) ?: return
        index[note.id] = Entry(
            file = written.name,
            title = note.title,
            mode = note.mode.rawValue,
            createdAt = note.createdAt,
            noteUpdatedAt = note.updatedAt,
            fileModifiedAt = written.modifiedAt
        )
    }

    private fun takenNames(folder: Folder, index: Map<String, Entry>): Set<String> =
        (folder.items.keys.map { it.lowercase() } + index.values.map { it.file.lowercase() }).toSet()

    /** The note's title as a file name, numbered if another file has it. */
    private fun uniqueName(note: SavedNote, extension: String, taken: Set<String>): String {
        val base = ScriptFile.suggestedFileName(note.title, note.content)
        var name = "$base.$extension"
        var number = 2
        while (name.lowercase() in taken) {
            name = "$base $number.$extension"
            number += 1
        }
        return name
    }

    private fun readContent(item: Item): String? =
        runCatching { TeleprompterParser.normalizingTags(ScriptFile.readText(context, item.uri)) }.getOrNull()

    private fun fileExtension(name: String): String =
        name.substringAfterLast('.', "").lowercase()

    /** What the folder says about one of its files, or null if it's gone. */
    private fun describe(uri: Uri): Item? = runCatching {
        resolver.query(uri, COLUMNS, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) item(cursor, uri) else null
        }
    }.getOrNull()

    private fun item(cursor: Cursor, uri: Uri): Item? {
        val name = cursor.getString(1) ?: return null
        return Item(
            uri = uri,
            name = name,
            isDirectory = cursor.getString(2) == Document.MIME_TYPE_DIR,
            // A folder that doesn't keep dates reports none, or zero.
            modifiedAt = if (cursor.isNull(3)) null else cursor.getLong(3).takeIf { it > 0 },
            size = if (cursor.isNull(4)) null else cursor.getLong(4)
        )
    }

    // MARK: - Index and access

    /**
     * The index, or null if the folder has none yet or it can't be read just
     * now. Without one, files can't be matched to notes, so nothing is written.
     */
    private fun readIndex(folder: Folder): MutableMap<String, Entry>? {
        val item = folder.file(INDEX_NAME) ?: return null
        val text = runCatching { ScriptFile.readText(context, item.uri) }.getOrNull() ?: return null
        val index = runCatching { json.decodeFromString<Map<String, Entry>>(text) }.getOrNull().orEmpty()
        // The index sits in the folder, where anything else with access can
        // rewrite it. An entry naming a path rather than a file in the folder,
        // or filed under something other than a note's ID, is dropped.
        return index
            .filter { (id, entry) -> SavedNote.isValidId(id) && isPlainFileName(entry.file) }
            .toMutableMap()
    }

    private fun isPlainFileName(name: String): Boolean =
        name.isNotEmpty() && name != "." && name != ".." && !name.contains("/")

    private fun writeIndex(index: Map<String, Entry>, folder: Folder): Boolean {
        val written = folder.write(INDEX_NAME, json.encodeToString(index), INDEX_MIME_TYPE) ?: return false
        if (written.name == INDEX_NAME) return true
        // Kept under another name, where it would never be found again.
        folder.delete(written.name)
        return false
    }

    private fun release(uri: Uri) {
        runCatching { resolver.releasePersistableUriPermission(uri, PERMISSIONS) }
    }

    private fun resolve(): Uri? = prefs.getString(FOLDER_KEY, null)?.toUri()

    /** The folder and what's in it, or null if it can't be listed. */
    private fun open(tree: Uri): Folder? = runCatching {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        resolver.query(children, COLUMNS, null, null, null)?.use { cursor ->
            val items = mutableMapOf<String, Item>()
            while (cursor.moveToNext()) {
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0) ?: continue)
                val item = item(cursor, uri) ?: continue
                items.putIfAbsent(item.name, item)
            }
            Folder(tree, items)
        }
    }.getOrNull()

    /** Run `body` with the folder open, if there is one and it can be reached. */
    private fun <T> withFolder(body: (Folder) -> T): T? {
        val folder = resolve()?.let(::open) ?: return null
        return body(folder)
    }

    private companion object {
        const val PREFS_NAME = "cuecard_notes_folder"
        const val FOLDER_KEY = "cuecard_notes_folder_uri"
        const val INDEX_NAME = ".cuecard.json"
        const val TEXT_MIME_TYPE = "text/plain"

        /** A type no folder ties to an extension, so the index keeps its name. */
        const val INDEX_MIME_TYPE = "application/octet-stream"
        const val PERMISSIONS = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val TEXT_EXTENSIONS = setOf("txt", "md")
        val COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_SIZE
        )
    }
}
