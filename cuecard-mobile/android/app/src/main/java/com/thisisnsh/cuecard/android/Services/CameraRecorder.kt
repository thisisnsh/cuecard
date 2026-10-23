package com.thisisnsh.cuecard.android.services

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.thisisnsh.cuecard.android.AppStrings
import com.thisisnsh.cuecard.android.R
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/**
 * The camera behind the floating camera window: a preview, and a recording
 * that goes straight into the device's videos, under Movies/CueCard. Lives on
 * the main thread; CameraX does its own work off it.
 */
class CameraRecorder(context: Context) {
    companion object {
        /** What recording needs, and below Android 10 what writing to Movies needs too. */
        val permissions: Array<String>
            get() = buildList {
                add(Manifest.permission.CAMERA)
                add(Manifest.permission.RECORD_AUDIO)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }.toTypedArray()

        /** The furthest zoom offered, as far as a lens is useful for a talking head. */
        private const val MAX_ZOOM = 10.0
    }

    private val context = context.applicationContext

    var isReady by mutableStateOf(false)
        private set
    var isRecording by mutableStateOf(false)
        private set
    var isPaused by mutableStateOf(false)
        private set
    /** Waiting on the camera to start, pause, resume or flip. */
    var isBusy by mutableStateOf(false)
        private set
    /** How long the take has recorded, pauses left out, in seconds. */
    var recordedSeconds by mutableLongStateOf(0L)
        private set
    /** As the Camera app counts it: 1× is the main lens. */
    var zoom by mutableDoubleStateOf(1.0)
        private set
    /** The zoom stops the camera has, smallest first. */
    var zoomSteps by mutableStateOf(listOf(1.0))
        private set
    var message by mutableStateOf<String?>(null)

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private val preview = Preview.Builder().build()
    private val videoCapture = VideoCapture.withOutput(
        Recorder.Builder()
            .setQualitySelector(QualitySelector.from(Quality.FHD, androidx.camera.video.FallbackStrategy.lowerQualityOrHigherThan(Quality.HD)))
            .build()
    )
    private var recording: Recording? = null
    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var owner: LifecycleOwner? = null
    private var scriptId: String? = null
    /** When the take started, for the session it's filed under. */
    private var startedAt = 0L
    private var isVisible = false

    val hasPermissions: Boolean
        get() = permissions.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

    /** Where the picture is shown, and which way up the screen is. */
    private var previewView: PreviewView? = null

    fun attach(view: PreviewView) {
        previewView = view
        preview.surfaceProvider = view.surfaceProvider
    }

    /** Open the camera for `owner`, which closes it whenever it stops. */
    suspend fun prepare(owner: LifecycleOwner, scriptId: String?) {
        isVisible = true
        this.owner = owner
        this.scriptId = scriptId
        if (!hasPermissions) {
            message = AppStrings.get(R.string.camera_access_needed)
            return
        }
        val provider = provider ?: awaitProvider().also { provider = it }
        if (!isVisible) return
        bind(provider, owner)
    }

    private suspend fun awaitProvider(): ProcessCameraProvider = suspendCancellableCoroutine { continuation ->
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({ continuation.resume(future.get()) }, ContextCompat.getMainExecutor(context))
    }

    private fun bind(provider: ProcessCameraProvider, owner: LifecycleOwner) {
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        try {
            provider.unbindAll()
            val camera = provider.bindToLifecycle(owner, selector, preview, videoCapture)
            this.camera = camera
            camera.cameraInfo.zoomState.value?.let { state ->
                val minZoom = state.minZoomRatio.toDouble()
                val maxZoom = minOf(state.maxZoomRatio.toDouble(), MAX_ZOOM)
                // The stops the Camera app offers, rounded the way it labels them.
                zoomSteps = listOf(minZoom, 1.0, 2.0, 5.0)
                    .map { (it * 10).roundToInt() / 10.0 }
                    .filter { it >= minZoom - 0.01 && it <= maxZoom + 0.01 }
                    .distinct()
                    .sorted()
                    .ifEmpty { listOf(1.0) }
            }
            zoom = 1.0
            camera.cameraControl.setZoomRatio(1f)
            isReady = true
            message = null
        } catch (e: Exception) {
            isReady = false
            message = AppStrings.get(R.string.camera_unavailable)
        }
    }

    /** Starts a recording, or resumes a paused one. */
    fun record() {
        if (isRecording) setRecordingPaused(false) else start()
    }

    @SuppressLint("MissingPermission")
    fun start() {
        if (!isReady || isBusy || isRecording) return
        if (!hasPermissions) {
            message = AppStrings.get(R.string.camera_access_needed)
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "CueCard ${System.currentTimeMillis()}")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Movies/CueCard")
            }
        }
        val options = MediaStoreOutputOptions.Builder(context.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            .setContentValues(values)
            .build()

        // Level with the screen as the app is held now.
        videoCapture.targetRotation = previewView?.display?.rotation ?: Surface.ROTATION_0
        message = null
        isBusy = true
        isPaused = false
        recordedSeconds = 0
        recording = try {
            videoCapture.output.prepareRecording(context, options)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(context), ::handle)
        } catch (e: Exception) {
            isBusy = false
            message = AppStrings.get(R.string.camera_not_ready)
            null
        }
    }

    fun togglePause() {
        setRecordingPaused(!isPaused)
    }

    fun setRecordingPaused(paused: Boolean) {
        val recording = recording ?: return
        if (!isRecording || isBusy || paused == isPaused) return
        isBusy = true
        if (paused) recording.pause() else recording.resume()
    }

    fun stop() {
        val recording = recording ?: return
        isBusy = true
        // The camera has stopped; only the file is still being finished.
        message = AppStrings.get(R.string.saving_video)
        recording.stop()
    }

    fun zoomTo(value: Double) {
        val camera = camera ?: return
        if (!isReady) return
        zoom = value.coerceIn(zoomSteps.first(), zoomSteps.last().coerceAtLeast(zoomSteps.first()))
        camera.cameraControl.setZoomRatio(zoom.toFloat())
    }

    fun switchCamera() {
        val provider = provider ?: return
        val owner = owner ?: return
        if (!isReady || isBusy || isRecording) return
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
            CameraSelector.LENS_FACING_BACK
        } else {
            CameraSelector.LENS_FACING_FRONT
        }
        bind(provider, owner)
    }

    /**
     * Close the camera. A take still recording stops and is saved, even once
     * the reader it was recorded over has gone.
     */
    fun suspend() {
        isVisible = false
        previewView = null
        isReady = false
        recording?.stop()
        provider?.unbindAll()
        camera = null
    }

    private fun handle(event: VideoRecordEvent) {
        recordedSeconds = event.recordingStats.recordedDurationNanos / 1_000_000_000
        when (event) {
            is VideoRecordEvent.Start -> {
                startedAt = System.currentTimeMillis()
                isRecording = true
                isBusy = false
            }
            is VideoRecordEvent.Pause -> {
                isPaused = true
                isBusy = false
            }
            is VideoRecordEvent.Resume -> {
                isPaused = false
                isBusy = false
            }
            is VideoRecordEvent.Finalize -> {
                recording = null
                isRecording = false
                isPaused = false
                isBusy = false
                // A camera closed mid-take still leaves its video behind.
                val kept = event.error == VideoRecordEvent.Finalize.ERROR_NONE ||
                    event.error == VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE
                if (kept && event.outputResults.outputUri != android.net.Uri.EMPTY) {
                    scriptId?.let {
                        TakeStore.getInstance(context).recordSession(it, startedAt, System.currentTimeMillis())
                    }
                    if (isVisible) message = AppStrings.get(R.string.video_saved)
                } else if (isVisible) {
                    message = AppStrings.get(R.string.camera_stopped)
                }
            }
            is VideoRecordEvent.Status -> Unit
        }
    }
}
