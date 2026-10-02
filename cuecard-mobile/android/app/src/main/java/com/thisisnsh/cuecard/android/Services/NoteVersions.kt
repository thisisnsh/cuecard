package com.thisisnsh.cuecard.android.services

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * One saved state of a note. Written once and never changed: every save of a
 * note adds a new version, and restoring an old one adds a copy of it on top.
 */
@Serializable
data class NoteVersion(
    /** 1 for the first save, counting up from there. */
    val number: Int,
    val content: String,
    val createdAt: Long,
    /** The version this one brought back, if it came from a restore. */
    val restoredFrom: Int? = null
)

/**
 * Every version of every saved note, one file each, kept in the app's own
 * storage on this device. The notes folder only ever gets the newest.
 *
 * Everything here reads or writes files, so it's called off the main thread.
 */
class NoteVersions(context: Context) {
    private val root = File(context.filesDir, "NoteVersions")
    private val json = Json { ignoreUnknownKeys = true }

    /** A note's versions, oldest first. */
    fun versions(id: String): List<NoteVersion> =
        numbers(id).mapNotNull { read(it, id) }

    /** How many versions each note has, for notes that have any. */
    fun counts(): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        for (folder in root.listFiles().orEmpty()) {
            if (!folder.isDirectory || !SavedNote.isValidId(folder.name)) continue
            val count = numbers(folder.name).size
            if (count > 0) counts[folder.name] = count
        }
        return counts
    }

    /**
     * Keep `note`'s text as its newest version, unless it already is.
     * `previous` is the note as it was saved before, so a note saved before
     * versions existed starts its history with what it held then.
     * Returns how many versions the note has now.
     */
    fun record(note: SavedNote, previous: SavedNote? = null, restoredFrom: Int? = null): Int {
        var numbers = numbers(note.id)
        if (numbers.isEmpty() && previous != null && previous.content != note.content) {
            if (write(NoteVersion(1, previous.content, previous.updatedAt), note.id)) {
                numbers = listOf(1)
            }
        }
        val last = numbers.lastOrNull()
        if (last != null && read(last, note.id)?.content == note.content) {
            return numbers.size
        }
        val version = NoteVersion((last ?: 0) + 1, note.content, note.updatedAt, restoredFrom)
        return if (write(version, note.id)) numbers.size + 1 else numbers.size
    }

    fun remove(id: String) {
        folder(id)?.deleteRecursively()
    }

    fun removeAll() {
        root.deleteRecursively()
    }

    // MARK: - Files

    /**
     * A note's ID names its folder, and IDs can come in from the notes folder's
     * index, so anything that isn't one is turned away rather than used as a path.
     */
    private fun folder(id: String): File? =
        if (SavedNote.isValidId(id)) File(root, id) else null

    private fun file(number: Int, id: String): File? =
        folder(id)?.let { File(it, "$number.json") }

    /** The version numbers a note has on disk, in order. */
    private fun numbers(id: String): List<Int> =
        folder(id)?.list().orEmpty()
            .mapNotNull { name -> if (name.endsWith(".json")) name.removeSuffix(".json").toIntOrNull() else null }
            .sorted()

    private fun read(number: Int, id: String): NoteVersion? {
        val file = file(number, id) ?: return null
        return runCatching { json.decodeFromString<NoteVersion>(file.readText()) }.getOrNull()
    }

    /** Write a new version's file. An existing file is never written over. */
    private fun write(version: NoteVersion, id: String): Boolean {
        val folder = folder(id) ?: return false
        val file = file(version.number, id) ?: return false
        return try {
            folder.mkdirs()
            if (!file.createNewFile()) return false
            file.writeText(json.encodeToString(version))
            true
        } catch (e: Exception) {
            file.delete()
            false
        }
    }
}
