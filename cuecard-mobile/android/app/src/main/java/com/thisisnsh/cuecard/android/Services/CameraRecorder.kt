package com.thisisnsh.cuecard.android.services

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.view.Surface
import android.util.Range
import androidx.camera.core.Camera
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.DynamicRange
import androidx.camera.core.MirrorMode
import androidx.camera.core.Preview
import androidx.camera.video.FallbackStrategy
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
import androidx.core.content.edit
import androidx.lifecycle.LifecycleOwner
import com.thisisnsh.cuecard.android.AppStrings
import com.thisisnsh.cuecard.android.R
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/**
 * How the camera records, as in a camera app's video settings. Chosen in
 * Settings, for both modes. Each camera records the nearest it can. Nothing
 * here changes the picture's look.
 */
@Serializable
data class CameraSettings(
    val resolution: Resolution = Resolution.HD1080,
    val frameRate: Int = 30,
    val dynamicRange: Dynamic = Dynamic.SDR,
    val stabilization: Stabilization = Stabilization.OFF,
    /** Records the front camera as the preview shows it, like a mirror. */
    val mirrorsFrontCamera: Boolean = false
) {
    enum class Resolution(val label: String) {
        HD720("720p"), HD1080("1080p"), UHD4K("4K");

        val quality: Quality
            get() = when (this) {
                HD720 -> Quality.HD
                HD1080 -> Quality.FHD
                UHD4K -> Quality.UHD
            }

        companion object {
            fun of(quality: Quality): Resolution? = entries.firstOrNull { it.quality == quality }
        }
    }

    enum class Dynamic(val label: String) {
        SDR("SDR"), HDR("HDR");

        val range: DynamicRange get() = if (this == HDR) DynamicRange.HLG_10_BIT else DynamicRange.SDR
    }

    enum class Stabilization { OFF, STANDARD }

    companion object {
        /** The frame rates offered, where the camera has them. */
        val FRAME_RATES = listOf(24, 25, 30, 60)

        private const val PREFS = "camera"
        private const val KEY = "camera_settings"
        private val json = Json { ignoreUnknownKeys = true }

        fun saved(context: Context): CameraSettings =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
                ?.let { runCatching { json.decodeFromString<CameraSettings>(it) }.getOrNull() }
                ?: CameraSettings()
    }

    fun save(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { putString(KEY, json.encodeToString(this@CameraSettings)) }
    }
}

/** The settings a camera can record with, given the rest. */
data class CameraOptions(
    val resolutions: List<CameraSettings.Resolution> = listOf(CameraSettings.Resolution.HD1080),
    val frameRates: List<Int> = listOf(30),
    val dynamicRanges: List<CameraSettings.Dynamic> = listOf(CameraSettings.Dynamic.SDR),
    val stabilizations: List<CameraSettings.Stabilization> = listOf(CameraSettings.Stabilization.OFF),
    val isFrontCamera: Boolean = true
)

/** Working out what the device's cameras record with, without opening one. */
object CameraCapabilities {
    /**
     * What this device's cameras can record with, for Settings, where no camera
     * is on: every choice either camera has, given the rest, with the reader's
     * choices moved to the nearest of those. Each camera then records the nearest it can.
     */
    suspend fun offered(context: Context, preferred: CameraSettings): Pair<CameraSettings, CameraOptions> {
        val provider = runCatching { awaitProvider(context) }.getOrNull()
            ?: return preferred to CameraOptions(isFrontCamera = false)
        val cameras = runCatching { provider.availableCameraInfos }.getOrDefault(emptyList())
            .filter { it.lensFacing == CameraSelector.LENS_FACING_FRONT || it.lensFacing == CameraSelector.LENS_FACING_BACK }
        if (cameras.isEmpty()) return preferred to CameraOptions(isFrontCamera = false)

        val resolutions = mutableSetOf<CameraSettings.Resolution>()
        val rates = mutableSetOf<Int>()
        val ranges = mutableSetOf<CameraSettings.Dynamic>()
        val stabilizations = mutableSetOf(CameraSettings.Stabilization.OFF)
        for (camera in cameras) {
            val own = options(camera, preferred)
            resolutions += own.resolutions
            rates += own.frameRates
            ranges += own.dynamicRanges
            stabilizations += own.stabilizations
        }
        val options = CameraOptions(
            resolutions = CameraSettings.Resolution.entries.filter { it in resolutions }.ifEmpty { listOf(CameraSettings.Resolution.HD1080) },
            frameRates = CameraSettings.FRAME_RATES.filter { it in rates }.ifEmpty { listOf(30) },
            dynamicRanges = CameraSettings.Dynamic.entries.filter { it in ranges }.ifEmpty { listOf(CameraSettings.Dynamic.SDR) },
            stabilizations = CameraSettings.Stabilization.entries.filter { it in stabilizations },
            isFrontCamera = cameras.any { it.lensFacing == CameraSelector.LENS_FACING_FRONT }
        )
        return nearest(preferred, options) to options
    }

    /** What one camera offers, given the dynamic range asked for. */
    fun options(camera: CameraInfo, preferred: CameraSettings): CameraOptions {
        val capabilities = runCatching { Recorder.getVideoCapabilities(camera) }.getOrNull()
            ?: return CameraOptions(isFrontCamera = camera.lensFacing == CameraSelector.LENS_FACING_FRONT)
        val ranges = CameraSettings.Dynamic.entries.filter { it.range in capabilities.supportedDynamicRanges }
            .ifEmpty { listOf(CameraSettings.Dynamic.SDR) }
        val range = if (preferred.dynamicRange in ranges) preferred.dynamicRange else ranges.first()
        val resolutions = capabilities.getSupportedQualities(range.range).mapNotNull(CameraSettings.Resolution::of)
        val frameRanges = runCatching { camera.supportedFrameRateRanges }.getOrDefault(emptySet())
        val rates = CameraSettings.FRAME_RATES.filter { rate -> frameRanges.any { it.upper == rate } }
        return CameraOptions(
            resolutions = CameraSettings.Resolution.entries.filter { it in resolutions },
            frameRates = rates.ifEmpty { listOf(30) },
            dynamicRanges = ranges,
            stabilizations = if (capabilities.isStabilizationSupported) {
                CameraSettings.Stabilization.entries.toList()
            } else {
                listOf(CameraSettings.Stabilization.OFF)
            },
            isFrontCamera = camera.lensFacing == CameraSelector.LENS_FACING_FRONT
        )
    }

    /** The reader's choices moved to the nearest of `options`: the next one down, or else the lowest. */
    fun nearest(preferred: CameraSettings, options: CameraOptions): CameraSettings = preferred.copy(
        resolution = nearest(preferred.resolution, options.resolutions, CameraSettings.Resolution.entries),
        frameRate = if (preferred.frameRate in options.frameRates) {
            preferred.frameRate
        } else {
            options.frameRates.lastOrNull { it <= preferred.frameRate } ?: options.frameRates.first()
        },
        dynamicRange = if (preferred.dynamicRange in options.dynamicRanges) preferred.dynamicRange else options.dynamicRanges.first(),
        stabilization = nearest(preferred.stabilization, options.stabilizations, CameraSettings.Stabilization.entries)
    )

    private fun <T> nearest(value: T, available: List<T>, all: List<T>): T {
        if (value in available || available.isEmpty()) return value
        val index = all.indexOf(value)
        return available.lastOrNull { all.indexOf(it) < index } ?: available.first()
    }

    suspend fun awaitProvider(context: Context): ProcessCameraProvider = suspendCancellableCoroutine { continuation ->
        val future = ProcessCameraProvider.getInstance(context.applicationContext)
        future.addListener({ continuation.resume(future.get()) }, ContextCompat.getMainExecutor(context))
    }
}

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
    /** Made again each time a camera opens, with the settings it records with. */
    private var videoCapture: VideoCapture<Recorder> = videoCapture(null, CameraSettings())
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
        val provider = provider ?: CameraCapabilities.awaitProvider(context).also { provider = it }
        if (!isVisible) return
        bind(provider, owner)
    }

    /**
     * Recording at the nearest `camera` has to the settings saved in Settings.
     * Without a camera, the defaults.
     */
    private fun videoCapture(camera: CameraInfo?, saved: CameraSettings): VideoCapture<Recorder> {
        val settings = camera?.let { CameraCapabilities.nearest(saved, CameraCapabilities.options(it, saved)) } ?: saved
        val recorder = Recorder.Builder()
            .setQualitySelector(
                QualitySelector.from(settings.resolution.quality, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD))
            )
            .build()
        return VideoCapture.Builder(recorder).apply {
            if (camera != null) {
                setDynamicRange(settings.dynamicRange.range)
                setTargetFrameRate(Range(settings.frameRate, settings.frameRate))
                setVideoStabilizationEnabled(settings.stabilization == CameraSettings.Stabilization.STANDARD)
            }
            setMirrorMode(if (settings.mirrorsFrontCamera) MirrorMode.MIRROR_MODE_ON_FRONT_ONLY else MirrorMode.MIRROR_MODE_OFF)
        }.build()
    }

    private fun bind(provider: ProcessCameraProvider, owner: LifecycleOwner) {
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val info = runCatching { provider.availableCameraInfos.firstOrNull { it.lensFacing == lensFacing } }.getOrNull()
        // Settings may have changed since the camera was last on.
        val saved = CameraSettings.saved(context)
        try {
            provider.unbindAll()
            val camera = try {
                videoCapture = videoCapture(info, saved)
                provider.bindToLifecycle(owner, selector, preview, videoCapture)
            } catch (e: Exception) {
                // A combination this camera turned down: record as it would by default.
                provider.unbindAll()
                videoCapture = videoCapture(null, CameraSettings(mirrorsFrontCamera = saved.mirrorsFrontCamera))
                provider.bindToLifecycle(owner, selector, preview, videoCapture)
            }
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
