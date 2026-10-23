package com.thisisnsh.cuecard.android.views

import android.app.Activity
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.services.CameraRecorder
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

/** What the camera's own record, pause and stop buttons were tapped for. */
enum class CameraControl { RECORD, PAUSE, STOP }

/** The long side of the camera window over the short one. */
private const val CAMERA_ASPECT = 16f / 9f
private val CAMERA_MARGIN = 16.dp
private val CAMERA_TOP_MARGIN = 24.dp
private val CAMERA_CORNER_RADIUS = 16.dp

/**
 * Where the floating camera is in the reader: shared by the window, which
 * takes the gestures and draws the controls, and `CameraBackdrop`, which draws
 * the picture under the reader's text. Sizes are in pixels.
 */
@Stable
class CameraWindowPlacement(private val density: androidx.compose.ui.unit.Density) {
    /** The reader's area: where the window settles. */
    var area by mutableStateOf(Size.Zero)
    var isLeading by mutableStateOf(false)
    var isTop by mutableStateOf(true)
    var expanded by mutableStateOf(false)
    /** How far the window has been dragged from its corner. */
    val drag = Animatable(Offset.Zero, Offset.VectorConverter)
    var pinchScale by mutableFloatStateOf(1f)

    private val margin get() = with(density) { CAMERA_MARGIN.toPx() }
    private val topMargin get() = with(density) { CAMERA_TOP_MARGIN.toPx() }

    /**
     * Wide when the app is: the picture stays level, so it's landscape on
     * screen whenever the app is laid out in landscape.
     */
    val isLandscape: Boolean get() = area.width > area.height

    private val small get() = minOf(area.minDimension * 0.36f, with(density) { 180.dp.toPx() })
    private val large get() = minOf(area.minDimension * 0.6f, with(density) { 320.dp.toPx() })

    /** The short side it's settling to, followed live while pinching. */
    val targetShort: Float
        get() = ((if (expanded) large else small) * pinchScale).coerceIn(small * 0.8f, large * 1.1f)

    /**
     * The largest the window gets. The picture is laid out at this size and
     * scaled down to the window, so a resize stays smooth.
     */
    val largestSize: Size get() = size(large * 1.1f)

    fun size(short: Float): Size {
        val height = area.height - topMargin - margin
        val width = area.width - 2 * margin
        val fit = maxOf(1f, if (isLandscape) minOf(height, width / CAMERA_ASPECT) else minOf(width, height / CAMERA_ASPECT))
        val side = minOf(short, fit)
        val long = side * CAMERA_ASPECT
        return if (isLandscape) Size(long, side) else Size(side, long)
    }

    fun origin(isLeading: Boolean, isTop: Boolean, size: Size): Offset = Offset(
        if (isLeading) margin else area.width - size.width - margin,
        if (isTop) topMargin else area.height - size.height - margin
    )

    /** Where the window is drawn, following the finger while dragged. */
    fun frame(short: Float): Rect {
        val size = size(short)
        return Rect(origin(isLeading, isTop, size) + drag.value, size)
    }
}

/**
 * Opens the camera while `isPresented`, asking for the camera and microphone
 * first, and closes it otherwise. The screen stays on while it's up.
 */
@Composable
fun rememberCameraRecorder(isPresented: Boolean, scriptId: String?): CameraRecorder {
    val context = LocalContext.current
    val view = LocalView.current
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val recorder = remember { CameraRecorder(context) }

    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (isPresented) scope.launch { recorder.prepare(owner, scriptId) }
    }

    LaunchedEffect(isPresented) {
        if (isPresented) {
            if (recorder.hasPermissions) {
                recorder.prepare(owner, scriptId)
            } else {
                permissions.launch(CameraRecorder.permissions)
            }
        } else {
            recorder.suspend()
        }
    }

    DisposableEffect(isPresented) {
        val window = (view.context as? Activity)?.window
        if (isPresented) window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            if (isPresented) window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    DisposableEffect(Unit) {
        onDispose { recorder.suspend() }
    }

    return recorder
}

@Composable
fun rememberCameraWindowPlacement(): CameraWindowPlacement {
    val density = LocalDensity.current
    return remember { CameraWindowPlacement(density) }
}

/**
 * The camera's picture, for a reader to draw under its text, so the words
 * stay in view over the camera. Fills the reader's area; the picture sits
 * where the window is.
 */
@Composable
fun CameraBackdrop(recorder: CameraRecorder, placement: CameraWindowPlacement, modifier: Modifier = Modifier) {
    val short by animateFloatAsState(placement.targetShort, cameraSpring(), label = "cameraSize")
    Box(
        modifier = modifier
            .fillMaxSize()
            .onSizeChanged { placement.area = Size(it.width.toFloat(), it.height.toFloat()) }
    ) {
        if (placement.area != Size.Zero) {
            val frame = placement.frame(short)
            CameraPicture(recorder, placement, frame)
        }
    }
}

/**
 * The picture, laid out at the window's largest and scaled down to it, so a
 * resize stays smooth instead of the preview catching up a frame behind.
 */
@Composable
private fun CameraPicture(recorder: CameraRecorder, placement: CameraWindowPlacement, frame: Rect) {
    val density = LocalDensity.current
    val largest = placement.largestSize
    val scale = if (largest.width > 0) frame.width / largest.width else 1f
    val shape = RoundedCornerShape(CAMERA_CORNER_RADIUS)
    Box(
        modifier = Modifier
            .offset { IntOffset(frame.left.roundToInt(), frame.top.roundToInt()) }
            .size(with(density) { frame.width.toDp() }, with(density) { frame.height.toDp() })
            .shadow(14.dp, shape)
            .clip(shape)
            .background(Color.Black)
    ) {
        AndroidView(
            factory = { context ->
                PreviewView(context).apply {
                    // A texture, so the reader's words can draw over it.
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    recorder.attach(this)
                }
            },
            modifier = Modifier
                .size(with(density) { largest.width.toDp() }, with(density) { largest.height.toDp() })
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0f)
                }
        )
    }
}

private fun <T> cameraSpring() = spring<T>(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow)

/**
 * The camera's controls over its picture. Drag it anywhere and it springs back
 * into the nearest corner of the reader's area; pinch or double-tap to change
 * its size; tap to show or hide the controls.
 *
 * With `drawsPicture`, it draws the picture too, for a reader that floats the
 * camera over itself rather than under its words.
 */
@Composable
fun BoxScope.FloatingCameraWindow(
    recorder: CameraRecorder,
    placement: CameraWindowPlacement,
    drawsPicture: Boolean,
    onControl: (CameraControl) -> Unit,
    onClose: () -> Unit
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    var showsControls by remember { mutableStateOf(true) }
    val short by animateFloatAsState(placement.targetShort, cameraSpring(), label = "cameraSize")

    if (drawsPicture) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .onSizeChanged { placement.area = Size(it.width.toFloat(), it.height.toFloat()) }
        )
    }
    if (placement.area == Size.Zero) return

    val frame = placement.frame(short)
    if (drawsPicture) CameraPicture(recorder, placement, frame)

    val compact = with(density) { frame.minDimension.toDp() } < 220.dp
    val shape = RoundedCornerShape(CAMERA_CORNER_RADIUS)
    val smaller = stringResource(R.string.make_camera_smaller)
    val larger = stringResource(R.string.make_camera_larger)
    val cameraLabel = stringResource(R.string.camera)

    /** Settle in the corner the window is heading for. */
    fun settle() {
        val size = placement.size(short)
        val current = placement.origin(placement.isLeading, placement.isTop, size) + placement.drag.value
        val center = current + Offset(size.width / 2, size.height / 2)
        placement.isLeading = center.x < placement.area.width / 2
        placement.isTop = center.y < placement.area.height / 2
        val target = placement.origin(placement.isLeading, placement.isTop, size)
        scope.launch {
            placement.drag.snapTo(current - target)
            placement.drag.animateTo(Offset.Zero, cameraSpring())
        }
    }

    Box(
        modifier = Modifier
            .offset { IntOffset(frame.left.roundToInt(), frame.top.roundToInt()) }
            .size(with(density) { frame.width.toDp() }, with(density) { frame.height.toDp() })
            .clip(shape)
            .border(0.5.dp, Color.White.copy(alpha = 0.15f), shape)
            .semantics {
                contentDescription = cameraLabel
                customActions = listOf(
                    CustomAccessibilityAction(if (placement.expanded) smaller else larger) {
                        placement.expanded = !placement.expanded
                        true
                    }
                )
            }
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { showsControls = !showsControls },
                    onDoubleTap = { placement.expanded = !placement.expanded }
                )
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    var moved = false
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.isConsumed }) break
                        val zoom = event.calculateZoom()
                        val pan = event.calculatePan()
                        if (zoom != 1f) {
                            placement.pinchScale *= zoom
                            moved = true
                        }
                        if (pan != Offset.Zero && (moved || pan.getDistance() > 0.5f)) {
                            scope.launch { placement.drag.snapTo(placement.drag.value + pan) }
                            moved = true
                        }
                        if (moved) event.changes.forEach { it.consume() }
                    } while (event.changes.any { it.pressed })
                    if (moved) {
                        if (placement.pinchScale > 1.1f) placement.expanded = true
                        else if (placement.pinchScale < 0.9f) placement.expanded = false
                        placement.pinchScale = 1f
                        settle()
                    }
                }
            }
    ) {
        AnimatedVisibility(visible = showsControls, enter = fadeIn(), exit = fadeOut()) {
            CameraControls(recorder, compact, onControl, onClose)
        }
        if (!showsControls && recorder.isRecording) {
            RecordingDuration(recorder, compact, modifier = Modifier.padding(8.dp).align(Alignment.TopCenter))
        }
    }
}

@Composable
private fun CameraControls(
    recorder: CameraRecorder,
    compact: Boolean,
    onControl: (CameraControl) -> Unit,
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            // A light scrim, like a system player's, keeps white glyphs
            // readable over a bright picture.
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color.Black.copy(alpha = 0.45f),
                        Color.Black.copy(alpha = 0.1f),
                        Color.Black.copy(alpha = 0.1f),
                        Color.Black.copy(alpha = 0.5f)
                    )
                )
            )
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CircledIcon(Icons.Filled.Close, stringResource(R.string.close_camera), 32.dp, onClick = onClose)
            Spacer(modifier = Modifier.weight(1f))
            if (recorder.isRecording) RecordingDuration(recorder, compact)
            Spacer(modifier = Modifier.weight(1f))
            ZoomButton(recorder)
        }

        Spacer(modifier = Modifier.weight(1f))

        recorder.message?.let { message ->
            Text(
                text = message,
                fontSize = 11.sp,
                color = Color.White,
                textAlign = TextAlign.Center,
                maxLines = if (compact) 4 else 6,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.5f))
                    .padding(6.dp)
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            CircledIcon(
                Icons.Filled.Cameraswitch,
                stringResource(R.string.flip_camera),
                36.dp,
                enabled = recorder.isReady && !recorder.isBusy && !recorder.isRecording,
                onClick = recorder::switchCamera
            )
            Spacer(modifier = Modifier.weight(1f))
            RecordButton(recorder, diameter = if (compact) 44.dp else 56.dp, onControl = onControl)
            Spacer(modifier = Modifier.weight(1f))
            CircledIcon(
                Icons.Filled.Stop,
                stringResource(R.string.stop_recording),
                36.dp,
                enabled = recorder.isRecording && !recorder.isBusy
            ) {
                recorder.stop()
                onControl(CameraControl.STOP)
            }
        }
    }
}

/** A glyph on a dark disc, so it stays readable over a bright picture. */
@Composable
private fun CircledIcon(
    icon: ImageVector,
    description: String,
    size: Dp,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(size)
            .alpha(if (enabled) 1f else 0.4f)
            .clickableWithoutRipple { if (enabled) onClick() },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(size - 4.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(imageVector = icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(size * 0.5f))
        }
    }
}

@Composable
private fun RecordButton(recorder: CameraRecorder, diameter: Dp, onControl: (CameraControl) -> Unit) {
    val isRunning = recorder.isRecording && !recorder.isPaused
    val enabled = !recorder.isBusy && (recorder.isRecording || recorder.isReady)
    val description = when {
        !recorder.isRecording -> stringResource(R.string.record_video)
        recorder.isPaused -> stringResource(R.string.resume_recording)
        else -> stringResource(R.string.pause_recording)
    }
    Box(
        modifier = Modifier
            .size(diameter + 6.dp)
            .alpha(if (enabled) 1f else 0.6f)
            .border(2.dp, Color.White, CircleShape)
            .padding(3.dp)
            .clip(CircleShape)
            .background(Color.Red)
            .clickableWithoutRipple {
                if (!enabled) return@clickableWithoutRipple
                val control = if (isRunning) CameraControl.PAUSE else CameraControl.RECORD
                if (recorder.isRecording) recorder.togglePause() else recorder.start()
                onControl(control)
            }
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        if (recorder.isBusy) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(diameter * 0.4f))
        } else {
            Icon(
                imageVector = if (isRunning) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(diameter * 0.45f)
            )
        }
    }
}

@Composable
private fun RecordingDuration(recorder: CameraRecorder, compact: Boolean, modifier: Modifier = Modifier) {
    val description = stringResource(if (recorder.isPaused) R.string.recording_paused else R.string.recording_duration)
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(Color.Black.copy(alpha = 0.5f))
            .padding(horizontal = 6.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(if (recorder.isPaused) Color.Yellow else Color.Red)
        )
        Text(
            text = TeleprompterParser.formatTime(recorder.recordedSeconds.toInt()),
            fontSize = if (compact) 11.sp else 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
            color = Color.White
        )
    }
}

/** Steps through the zoom stops this camera has, such as 0.5×, 1×, 2× and 5×. */
@Composable
private fun ZoomButton(recorder: CameraRecorder) {
    val steps = recorder.zoomSteps
    val next = steps.firstOrNull { it > recorder.zoom + 0.05 } ?: steps.first()
    val label = String.format(Locale.getDefault(), if (recorder.zoom % 1.0 == 0.0) "%.0f×" else "%.1f×", recorder.zoom)
    val description = stringResource(R.string.camera_zoom)
    Box(
        modifier = Modifier
            .size(32.dp)
            .alpha(if (steps.size > 1) 1f else 0f)
            .clickableWithoutRipple { if (recorder.isReady && steps.size > 1) recorder.zoomTo(next) }
            .semantics { contentDescription = "$description, $label" },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            Text(text = label, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}
