package com.thisisnsh.cuecard.android.services

import android.Manifest
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.IntentSender
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A video on the device that was being recorded, for any part of it, while
 * the teleprompter or a deck was open on a script.
 */
data class Take(
    /** The video's MediaStore ID. */
    val id: String,
    val uri: Uri,
    /** 1 for the script's first take, counting up. */
    val number: Int,
    /** When it started recording, in milliseconds. */
    val recordedAt: Long,
    /** In milliseconds. */
    val duration: Long,
    /** Marked as a favorite in the gallery. */
    val isFavorite: Boolean
)

/** Whether CueCard can look through the device's videos. */
enum class VideoAccess {
    /** Never asked, or asked and can be asked again. */
    NOT_DETERMINED,
    DENIED,
    /** Only the videos the user picked. */
    LIMITED,
    AUTHORIZED;

    val canRead: Boolean get() = this == LIMITED || this == AUTHORIZED
}

/**
 * The takes of one script, found among the device's videos by when they were
 * recorded, and kept current as videos come and go.
 */
class TakesLibrary(context: Context) {
    companion object {
        /**
         * The longest a recording is taken to run. A video started further back
         * than this before the teleprompter opened isn't looked at.
         */
        private const val LONGEST_RECORDING = 6 * 60 * 60 * 1000L

        private const val PREFS = "takes"
        private const val ASKED_KEY = "asked_for_videos"

        /** The permissions to ask for, to read the device's videos. */
        val permissions: Array<String>
            get() = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
                )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
                else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            }

        /** Favorites are kept on a video from Android 11. */
        val canFavorite: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    }

    private val context = context.applicationContext
    private val takeStore = TakeStore.getInstance(context)
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _status = MutableStateFlow(VideoAccess.NOT_DETERMINED)
    val status: StateFlow<VideoAccess> = _status.asStateFlow()

    /** Oldest first. */
    private val _takes = MutableStateFlow<List<Take>>(emptyList())
    val takes: StateFlow<List<Take>> = _takes.asStateFlow()

    /** The teleprompter or a deck has been open on the script, so it may have takes. */
    private val _hasSessions = MutableStateFlow(false)
    val hasSessions: StateFlow<Boolean> = _hasSessions.asStateFlow()

    /** The tags and notes of each take, by take ID. */
    private val _details = MutableStateFlow<Map<String, TakeDetails>>(emptyMap())
    val details: StateFlow<Map<String, TakeDetails>> = _details.asStateFlow()

    private var scriptId: String? = null
    /** Whether Android will still show the request, as the screen last found. */
    private var canAskAgain = true
    private var pendingReload: Job? = null

    /** Changes come in bursts, a video being saved, so a burst is looked at once it settles. */
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            pendingReload?.cancel()
            pendingReload = scope.launch {
                delay(300)
                reload()
            }
        }
    }
    private var isObserving = false

    /** Stop following the video library. */
    fun close() {
        if (isObserving) context.contentResolver.unregisterContentObserver(observer)
        isObserving = false
        scope.cancel()
    }

    fun load(scriptId: String) {
        this.scriptId = scriptId
        scope.launch { reload() }
    }

    /**
     * What the system says about reading videos. `canAskAgain` is false once
     * Android won't show the request any more.
     */
    fun updateStatus(canAskAgain: Boolean = this.canAskAgain) {
        this.canAskAgain = canAskAgain
        fun granted(permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        _status.value = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && granted(Manifest.permission.READ_MEDIA_VIDEO) ->
                VideoAccess.AUTHORIZED
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> VideoAccess.LIMITED
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && granted(Manifest.permission.READ_EXTERNAL_STORAGE) ->
                VideoAccess.AUTHORIZED
            !prefs.getBoolean(ASKED_KEY, false) || canAskAgain -> VideoAccess.NOT_DETERMINED
            else -> VideoAccess.DENIED
        }
    }

    /** The request was shown; from now on a refusal can mean it won't be shown again. */
    fun markAsked() {
        prefs.edit { putBoolean(ASKED_KEY, true) }
    }

    /** Look again, for a session just ended or a video just recorded. */
    suspend fun reload() {
        updateStatus()
        val scriptId = scriptId ?: return
        val sessions = takeStore.sessions(scriptId)
        _hasSessions.value = sessions.isNotEmpty()
        _details.value = takeStore.details(scriptId)
        if (!_status.value.canRead || sessions.isEmpty()) {
            _takes.value = emptyList()
            return
        }

        if (!isObserving) {
            isObserving = true
            context.contentResolver.registerContentObserver(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true, observer
            )
        }
        _takes.value = withContext(Dispatchers.IO) { videos(sessions) }
            .mapIndexed { index, take -> take.copy(number = index + 1) }
    }

    fun details(take: Take): TakeDetails = _details.value[take.id] ?: TakeDetails()

    fun setDetails(details: TakeDetails, take: Take) {
        val scriptId = scriptId ?: return
        if (details == details(take)) return
        _details.value = if (details.isEmpty) _details.value - take.id else _details.value + (take.id to details)
        takeStore.setDetails(details, take.id, scriptId)
    }

    /** Tags already given to the script's takes, the most used first. */
    val usedTags: List<String>
        get() = _details.value.values.flatMap { it.tags }
            .groupingBy { it }.eachCount()
            .entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }

    /**
     * Mark the take as a favorite, or take the mark off. A video CueCard didn't
     * record needs the user to agree, so that comes back as a request to show.
     */
    suspend fun setFavorite(isFavorite: Boolean, take: Take): IntentSender? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_FAVORITE, if (isFavorite) 1 else 0) }
        val updated = withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.update(take.uri, values, null, null) > 0 }.getOrDefault(false)
        }
        if (updated) {
            reload()
            return null
        }
        return MediaStore.createFavoriteRequest(context.contentResolver, listOf(take.uri), isFavorite).intentSender
    }

    /**
     * Delete the take's video. Android asks the user first, so this hands back
     * the request to show, and `forget` follows once it's agreed to. Null when
     * it was deleted straight away, or couldn't be.
     */
    suspend fun delete(take: Take): IntentSender? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return MediaStore.createDeleteRequest(context.contentResolver, listOf(take.uri)).intentSender
        }
        val request = withContext(Dispatchers.IO) {
            try {
                if (context.contentResolver.delete(take.uri, null, null) > 0) forget(take)
                null
            } catch (e: SecurityException) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                    e.userAction.actionIntent.intentSender
                } else {
                    null
                }
            }
        }
        if (request == null) reload()
        return request
    }

    /** The take's video is gone: let its tags and notes go too. */
    suspend fun forget(take: Take) {
        withContext(Dispatchers.Main) {
            setDetails(TakeDetails(), take)
            reload()
        }
    }

    /** The video's first frame, or as near as the device has, `width` by `height` pixels. */
    suspend fun thumbnail(take: Take, width: Int, height: Int): Bitmap? = withContext(Dispatchers.IO) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.loadThumbnail(take.uri, Size(width, height), null)
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Video.Thumbnails.getThumbnail(
                    context.contentResolver, take.id.toLong(), MediaStore.Video.Thumbnails.MINI_KIND, null
                )
            }
        }.getOrNull()
    }

    /** Videos whose recording overlaps a session, oldest first. */
    private fun videos(sessions: List<TeleprompterSession>): List<Take> {
        // A recording that overlaps a session started before it ended, and no
        // longer than the longest recording before it began. Overlapping
        // stretches are merged to keep the query short.
        val windows = mutableListOf<Pair<Long, Long>>()
        for (session in sessions.sortedBy { it.start }) {
            val start = session.start - LONGEST_RECORDING
            val last = windows.lastOrNull()
            if (last != null && start <= last.second) {
                windows[windows.size - 1] = last.first to maxOf(last.second, session.end)
            } else {
                windows.add(start to session.end)
            }
        }
        if (windows.isEmpty()) return emptyList()

        // Not every video carries when it was taken, so one that doesn't is
        // found by when it was added: the moment it finished recording.
        val selection = windows.joinToString(" OR ") {
            "(${MediaStore.Video.Media.DATE_TAKEN} BETWEEN ? AND ? OR ${MediaStore.Video.Media.DATE_ADDED} BETWEEN ? AND ?)"
        }
        val arguments = windows.flatMap { (start, end) ->
            listOf(start, end, start / 1000, (end + LONGEST_RECORDING) / 1000).map { it.toString() }
        }.toTypedArray()
        val projection = buildList {
            add(MediaStore.Video.Media._ID)
            add(MediaStore.Video.Media.DATE_TAKEN)
            add(MediaStore.Video.Media.DATE_ADDED)
            add(MediaStore.Video.Media.DURATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) add(MediaStore.MediaColumns.IS_FAVORITE)
        }.toTypedArray()

        val videos = mutableListOf<Take>()
        runCatching {
            context.contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, projection, selection, arguments, null
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val takenColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_TAKEN)
                val addedColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val favoriteColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.IS_FAVORITE)
                } else {
                    -1
                }
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val duration = cursor.getLong(durationColumn).coerceAtLeast(0)
                    val taken = cursor.getLong(takenColumn)
                    val start = if (taken > 0) taken else cursor.getLong(addedColumn) * 1000 - duration
                    val end = start + duration
                    if (sessions.none { it.overlaps(start, end) }) continue
                    videos.add(
                        Take(
                            id = id.toString(),
                            uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id),
                            number = 0,
                            recordedAt = start,
                            duration = duration,
                            isFavorite = favoriteColumn >= 0 && cursor.getInt(favoriteColumn) == 1
                        )
                    )
                }
            }
        }
        return videos.sortedBy { it.recordedAt }
    }
}
