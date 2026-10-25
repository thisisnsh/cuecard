package com.thisisnsh.cuecard.android.services

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * A stretch of time the teleprompter or a deck was open on a script: playing,
 * paused, restarted or floating over another app. A video recorded during any
 * part of one is a take of that script. Times are in milliseconds.
 */
@Serializable
data class TeleprompterSession(val start: Long, val end: Long) {
    /** Whether any of `start..end` falls inside this session. */
    fun overlaps(start: Long, end: Long): Boolean = start <= this.end && this.start <= end
}

/** What the user has said about a take. */
@Serializable
data class TakeDetails(val tags: List<String> = emptyList(), val note: String = "") {
    val isEmpty: Boolean get() = tags.isEmpty() && note.isEmpty()
}

/**
 * When the teleprompter or a deck was open on each script, and what's been
 * said about its takes, kept in the app's own storage on this device, a folder
 * for each script. A script is filed under its saved note's ID, or the ID it
 * will be saved under.
 *
 * Only touched from the main thread; the files are small.
 */
class TakeStore private constructor(context: Context) {
    companion object {
        /**
         * How often the open session's end is moved up to now. If the app is
         * killed with the teleprompter up, the session loses no more than this.
         */
        private const val HEARTBEAT_MILLIS = 2_000L

        /**
         * A heartbeat this late means the app wasn't running in between. That
         * time isn't counted, and a new session starts from now.
         */
        private const val MAX_GAP_MILLIS = 10_000L

        @Volatile
        private var instance: TakeStore? = null

        fun getInstance(context: Context): TakeStore =
            instance ?: synchronized(this) {
                instance ?: TakeStore(context.applicationContext).also { instance = it }
            }
    }

    private val root = File(context.filesDir, "Takes")
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** The script that's open, and its sessions so far, the last one still going. */
    private var openScriptId: String? = null
    private var openSessions: List<TeleprompterSession> = emptyList()
    private var heartbeat: Job? = null

    /** Every session the teleprompter or a deck was open on a script, oldest first. */
    fun sessions(scriptId: String): List<TeleprompterSession> {
        if (openScriptId == scriptId) return openSessions
        val file = sessionsFile(scriptId) ?: return emptyList()
        return runCatching { json.decodeFromString<List<TeleprompterSession>>(file.readText()) }.getOrDefault(emptyList())
    }

    /** The tags and notes of a script's takes, by take ID. */
    fun details(scriptId: String): Map<String, TakeDetails> {
        val file = detailsFile(scriptId) ?: return emptyMap()
        return runCatching { json.decodeFromString<Map<String, TakeDetails>>(file.readText()) }.getOrDefault(emptyMap())
    }

    /** Keep what's been said about a take. Saying nothing forgets it. */
    fun setDetails(details: TakeDetails, takeId: String, scriptId: String) {
        val all = details(scriptId).toMutableMap()
        if (details.isEmpty) all.remove(takeId) else all[takeId] = details
        detailsFile(scriptId)?.let { write(it, json.encodeToString(all)) }
    }

    /** Start counting `scriptId` as open. */
    fun begin(scriptId: String) {
        end()
        val now = System.currentTimeMillis()
        // Read from disk before marking this script open. Otherwise sessions()
        // returns the empty in-memory list and older takes disappear on reopen.
        openSessions = sessions(scriptId) + TeleprompterSession(now, now)
        openScriptId = scriptId
        writeOpenSessions()

        heartbeat = scope.launch {
            while (isActive) {
                delay(HEARTBEAT_MILLIS)
                beat(startingOver = true)
            }
        }
    }

    /**
     * A take recorded in CueCard belongs to its script or deck, even if it's
     * saved after the reader closes.
     */
    fun recordSession(scriptId: String, start: Long, end: Long) {
        val recorded = TeleprompterSession(start, end)
        if (openScriptId == scriptId) {
            openSessions = openSessions + recorded
            writeOpenSessions()
            return
        }
        sessionsFile(scriptId)?.let { write(it, json.encodeToString(sessions(scriptId) + recorded)) }
    }

    /** The reader closed. Nothing happens if it wasn't open. */
    fun end() {
        heartbeat?.cancel()
        heartbeat = null
        if (openScriptId == null) return
        beat(startingOver = false)
        openScriptId = null
        openSessions = emptyList()
    }

    /** Move the open session's end up to now, or, after a gap, leave it and start another. */
    private fun beat(startingOver: Boolean) {
        val last = openSessions.lastOrNull() ?: return
        val now = System.currentTimeMillis()
        openSessions = if (now - last.end > MAX_GAP_MILLIS) {
            if (!startingOver) return
            openSessions + TeleprompterSession(now, now)
        } else {
            openSessions.dropLast(1) + last.copy(end = now)
        }
        writeOpenSessions()
    }

    fun remove(scriptId: String) {
        folder(scriptId)?.deleteRecursively()
    }

    fun removeAll() {
        root.deleteRecursively()
    }

    // MARK: - Files

    /** IDs are UUIDs, so a folder name never leaves `root`. */
    private fun folder(scriptId: String): File? =
        if (SavedNote.isValidId(scriptId)) File(root, scriptId) else null

    private fun sessionsFile(scriptId: String): File? = folder(scriptId)?.let { File(it, "sessions.json") }

    private fun detailsFile(scriptId: String): File? = folder(scriptId)?.let { File(it, "details.json") }

    private fun writeOpenSessions() {
        val id = openScriptId ?: return
        sessionsFile(id)?.let { write(it, json.encodeToString(openSessions)) }
    }

    private fun write(file: File, text: String) {
        runCatching {
            file.parentFile?.mkdirs()
            val temporary = File(file.parentFile, file.name + ".tmp")
            temporary.writeText(text)
            if (!temporary.renameTo(file)) {
                file.writeText(text)
                temporary.delete()
            }
        }
    }
}
