package com.thisisnsh.cuecard.android.views

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPicture
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.CueSegment
import com.thisisnsh.cuecard.android.models.TeleprompterContent
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.scriptEdgeFade
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.services.ReviewPromptService
import com.thisisnsh.cuecard.android.services.TeleprompterPiPManager
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlin.math.abs
import kotlin.math.exp

/**
 * How far the script fades into the background at each end. The reading line
 * sits clear of both.
 */
private val TOP_FADE = 96.dp
private val BOTTOM_FADE = 140.dp

/**
 * Where on screen the line being read sits, as a fraction of the view height.
 * Just above centre: high enough to leave the next few lines in view, low enough
 * to read as the middle of the screen rather than the top of it.
 *
 * It doubles as the script's top inset, so the first line starts on the reading
 * line and a line's scroll target is its own position in the text.
 */
private const val READING_LINE_FRACTION = 0.45f

/**
 * How fast the script closes on where it should be. Playback moves the target in
 * small steps and the easing is invisible; a restart or a drag moves it a long
 * way and the same easing carries the script there smoothly.
 */
private const val EASE_TIME_CONSTANT = 0.12

/**
 * How long the script takes to arrive after the overlay has gone. The reader is
 * handed a blank page for that moment and the script comes up onto it, rather
 * than the overlay lifting off a screen that was finished all along.
 */
private const val SCRIPT_FADE_IN_MILLIS = 350

/** How long the controls take to arrive and to leave. */
private const val CONTROLS_FADE_MILLIS = 200

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeleprompterView(
    content: TeleprompterContent,
    settings: TeleprompterSettings,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val density = LocalDensity.current
    val pipManager = TeleprompterPiPManager.shared

    var isPlaying by remember { mutableStateOf(false) }
    /**
     * The clock, read by the frame loop rather than by the layout — writing it
     * sixty times a second shouldn't recompose anything. The readout follows
     * `elapsedSeconds`, which only moves once a second.
     */
    val clock = remember { mutableDoubleStateOf(0.0) }
    var elapsedSeconds by remember { mutableIntStateOf(0) }
    var showControls by remember { mutableStateOf(true) }
    var countdownValue by remember { mutableIntStateOf(0) }
    var isCountingDown by remember { mutableStateOf(false) }
    /**
     * Whether playback has begun since the last restart. The countdown only runs
     * on the first play; resuming from a pause starts right away.
     */
    var hasStarted by remember { mutableStateOf(false) }
    /**
     * How far the script has arrived. One at all times except across a return
     * from the overlay, where it is taken away as the overlay closes and brought
     * back once the overlay has gone — so the reader is handed a blank page for
     * that moment and the script comes up onto it, rather than the overlay
     * lifting off a screen that was finished all along.
     */
    var scriptVisible by remember { mutableStateOf(true) }
    val scriptAlpha by animateFloatAsState(
        targetValue = if (scriptVisible) 1f else 0f,
        animationSpec = tween(durationMillis = SCRIPT_FADE_IN_MILLIS, easing = LinearOutSlowInEasing),
        label = "scriptAlpha"
    )

    // Nothing but the script for as long as the prompter is up: the gesture bar
    // goes with the rest of it, the way `persistentSystemOverlays(.hidden)` takes
    // the home indicator away on iOS. A swipe from the edge still brings it back.
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.navigationBars())
        }
        onDispose { controller?.show(WindowInsetsCompat.Type.navigationBars()) }
    }

    // Android reports the overlay closing once, where iOS has a will-end and a
    // did-end, so the blanking hangs off the overlay's own state rather than off
    // a pair of callbacks.
    LaunchedEffect(pipManager.isPiPActive) {
        scriptVisible = !pipManager.isPiPActive
    }

    // The scroll offsets that put each rendered line on the reading line, and
    // where the script actually is right now.
    var lineOffsets by remember { mutableStateOf(FloatArray(0)) }
    var scrollPx by remember { mutableFloatStateOf(0f) }
    var contentHeightPx by remember { mutableFloatStateOf(0f) }
    var viewportHeightPx by remember { mutableFloatStateOf(0f) }
    var isUserScrolling by remember { mutableStateOf(false) }
    /** Set when the script should arrive at its target without easing. */
    var settleNext by remember { mutableStateOf(true) }

    val timerDuration = settings.timerDurationSeconds

    /**
     * How long the whole script takes at the current speed: the time for the last
     * line to reach the reading line. Zero until the script has laid out.
     */
    fun scriptDuration(): Double {
        val lines = lineOffsets.size
        return if (lines > 1 && settings.linesPerMinute > 0) {
            (lines - 1) * 60.0 / settings.linesPerMinute
        } else {
            0.0
        }
    }

    LaunchedEffect(lineOffsets.size) {
        pipManager.scriptDuration = scriptDuration()
    }

    // MARK: - Timer readout

    val timerColor = when {
        isCountingDown -> AppColors.pink(isDark)
        timerDuration <= 0 -> AppColors.textPrimary(isDark)
        else -> AppColors.timerColor(
            remainingSeconds = timerDuration - elapsedSeconds,
            totalSeconds = timerDuration,
            isDark = isDark
        )
    }

    val timeDisplay = when {
        isCountingDown -> " ${TeleprompterParser.formatTime(countdownValue)} "
        timerDuration > 0 -> " ${TeleprompterParser.formatTime(timerDuration - elapsedSeconds)} "
        else -> " ${TeleprompterParser.formatTime(elapsedSeconds)} "
    }

    // MARK: - Playback

    fun updatePiP() {
        pipManager.updateState(
            elapsedTime = clock.doubleValue,
            isPlaying = isPlaying,
            countdownValue = countdownValue,
            isCountingDown = isCountingDown
        )
    }

    fun play() {
        isPlaying = true
        hasStarted = true
        updatePiP()
        AnalyticsEvents.logEvent("teleprompter_play")
    }

    fun pause() {
        if (isCountingDown) {
            isCountingDown = false
            countdownValue = 0
            updatePiP()
            return
        }
        isPlaying = false
        updatePiP()
        AnalyticsEvents.logEvent("teleprompter_pause")
    }

    fun startCountdownThenPlay() {
        // Only count down from the top of the script — a resume plays immediately.
        if (settings.countdownSeconds <= 0 || hasStarted) {
            play()
            return
        }

        countdownValue = settings.countdownSeconds
        isCountingDown = true
        updatePiP()
    }

    fun togglePlayPause() {
        if (isPlaying || isCountingDown) pause() else startCountdownThenPlay()
        showControls = true
    }

    /** Back to the first line, which the script scrolls up to rather than snapping. */
    fun restart() {
        isCountingDown = false
        countdownValue = 0
        clock.doubleValue = 0.0
        elapsedSeconds = 0
        isPlaying = false
        hasStarted = false
        updatePiP()
        AnalyticsEvents.logEvent("teleprompter_restart")
    }

    fun stopAndDismiss() {
        isPlaying = false
        isCountingDown = false
        pipManager.cleanup()
        AnalyticsEvents.logEvent(
            "teleprompter_closed",
            mapOf("elapsed_time" to clock.doubleValue.toInt())
        )
        ReviewPromptService.getInstance(context).recordCompletedSession()
        onDismiss()
    }

    // MARK: - The overlay

    DisposableEffect(Unit) {
        pipManager.configure(settings = settings, timerDuration = timerDuration)

        pipManager.onPlayPauseFromPiP = { playing ->
            if (playing) {
                isPlaying = true
                hasStarted = true
            } else {
                isPlaying = false
            }
        }

        pipManager.onRestartFromPiP = {
            isCountingDown = false
            countdownValue = 0
            clock.doubleValue = 0.0
            elapsedSeconds = 0
            isPlaying = false
            hasStarted = false
        }

        // Coming back from the overlay, the script is already where the overlay
        // left it, so it settles rather than scrolling there.
        pipManager.onPiPRestoreUI = { settleNext = true }

        AnalyticsEvents.logEvent(
            "teleprompter_started",
            mapOf(
                "word_count" to content.words.size,
                "timer_duration" to timerDuration
            )
        )

        onDispose {
            pipManager.onPlayPauseFromPiP = null
            pipManager.onRestartFromPiP = null
            pipManager.onPiPRestoreUI = null
        }
    }

    // MARK: - The clock and the scroll

    fun maxScroll(): Float = (contentHeightPx - viewportHeightPx).coerceAtLeast(0f)

    /** Where the script should be, in pixels, for the time on the clock. */
    fun targetOffset(): Float {
        if (lineOffsets.size < 2) return 0f

        val position = (clock.doubleValue * settings.linesPerMinute / 60.0)
            .coerceIn(0.0, (lineOffsets.size - 1).toDouble())
        val line = position.toInt().coerceAtMost(lineOffsets.size - 2)
        val fraction = (position - line).toFloat()
        val target = lineOffsets[line] + (lineOffsets[line + 1] - lineOffsets[line]) * fraction

        return target.coerceIn(0f, maxScroll())
    }

    /**
     * The inverse of the line-to-offset map: which line, fractionally, sits on
     * the reading line at this scroll offset.
     */
    fun linePosition(offset: Float): Double {
        val offsets = lineOffsets
        if (offsets.size < 2) return 0.0
        if (offset <= offsets[0]) return 0.0
        if (offset >= offsets[offsets.size - 1]) return (offsets.size - 1).toDouble()

        var low = 0
        var high = offsets.size - 1
        while (low + 1 < high) {
            val mid = (low + high) / 2
            if (offsets[mid] <= offset) low = mid else high = mid
        }

        val span = offsets[low + 1] - offsets[low]
        if (span <= 0f) return low.toDouble()
        return low + ((offset - offsets[low]) / span).toDouble()
    }

    /**
     * Pick up from wherever the reader dragged the script to. The line they left
     * on the reading line is the line the clock now reads from, so playback
     * carries on from there instead of snapping back.
     */
    fun handOffScroll() {
        val duration = scriptDuration()
        val end = if (duration > 0) duration else Double.MAX_VALUE
        val target = (linePosition(scrollPx) * 60.0 / settings.linesPerMinute).coerceIn(0.0, end)
        if (abs(target - clock.doubleValue) <= 0.001) return
        clock.doubleValue = target
        elapsedSeconds = target.toInt()
        updatePiP()
    }

    val scrollableState = rememberScrollableState { delta ->
        isUserScrolling = true
        val previous = scrollPx
        scrollPx = (scrollPx - delta).coerceIn(0f, maxScroll())
        previous - scrollPx
    }

    LaunchedEffect(scrollableState.isScrollInProgress) {
        if (!scrollableState.isScrollInProgress && isUserScrolling) {
            isUserScrolling = false
            handOffScroll()
        }
    }

    // One loop drives everything that moves: the clock, the countdown, the
    // easing, and the auto-hiding controls.
    LaunchedEffect(Unit) {
        var lastFrame = 0L
        var lastCountdownTick = 0L
        var controlsShownAt = 0L

        while (true) {
            withFrameNanos { now ->
                val delta = if (lastFrame == 0L) 0.0 else (now - lastFrame) / 1_000_000_000.0
                lastFrame = now

                if (isCountingDown) {
                    if (lastCountdownTick == 0L) lastCountdownTick = now
                    if (now - lastCountdownTick >= 1_000_000_000L) {
                        lastCountdownTick = now
                        countdownValue -= 1
                        if (countdownValue <= 0) {
                            isCountingDown = false
                            countdownValue = 0
                            isPlaying = true
                            hasStarted = true
                            AnalyticsEvents.logEvent("teleprompter_play")
                        }
                        updatePiP()
                    }
                } else {
                    lastCountdownTick = 0L
                }

                if (isPlaying && delta > 0) {
                    clock.doubleValue += delta
                    val seconds = clock.doubleValue.toInt()
                    if (seconds != elapsedSeconds) elapsedSeconds = seconds
                    updatePiP()
                }

                // The script closes on its target unless the reader has hold of it.
                if (!isUserScrolling) {
                    val target = targetOffset()
                    if (settleNext) {
                        scrollPx = target
                        settleNext = false
                    } else {
                        val distance = target - scrollPx
                        if (abs(distance) > 0.05f) {
                            scrollPx += (distance * (1 - exp(-delta / EASE_TIME_CONSTANT))).toFloat()
                        } else {
                            scrollPx = target
                        }
                    }
                }

                // Controls auto-hide after three seconds of playback.
                if (showControls) {
                    if (controlsShownAt == 0L) controlsShownAt = now
                    if (isPlaying && now - controlsShownAt >= 3_000_000_000L) {
                        showControls = false
                        controlsShownAt = 0L
                    }
                    if (!isPlaying) controlsShownAt = now
                } else {
                    controlsShownAt = 0L
                }
            }
        }
    }

    val script = remember(content.fullText, settings.cueColor, settings.fontSize, isDark) {
        buildScript(content, settings.cueColor, settings.fontSize.toFloat(), isDark)
    }

    if (pipManager.isPiPActive) {
        TeleprompterOverlay(
            script = remember(content.fullText, settings.cueColor, settings.pipFontSize, isDark) {
                buildScript(content, settings.cueColor, settings.pipFontSize.toFloat(), isDark)
            },
            elapsedTime = { clock.doubleValue },
            scriptDuration = { scriptDuration() },
            timeDisplay = timeDisplay,
            timerColor = timerColor,
            isDark = isDark
        )
        return
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Teleprompter",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                },
                navigationIcon = {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close",
                        tint = AppColors.textPrimary(isDark),
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .size(14.dp)
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("close", "teleprompter")
                                stopAndDismiss()
                            }
                    )
                },
                actions = {
                    Text(
                        text = timeDisplay,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = timerColor,
                        modifier = Modifier.padding(end = 16.dp)
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.background(isDark)
                )
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(AppColors.background(isDark))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clipToBounds()
                    .onSizeChanged { size ->
                        if (size.height.toFloat() != viewportHeightPx) {
                            viewportHeightPx = size.height.toFloat()
                            settleNext = true
                        }
                    }
                    .scrollable(state = scrollableState, orientation = Orientation.Vertical)
                    .pointerInput(Unit) {
                        detectTapGestures { showControls = !showControls }
                    }
                    .scriptEdgeFade(isDark = isDark, top = TOP_FADE, bottom = BOTTOM_FADE)
                    // Held back while the overlay is closing, so the script
                    // arrives on the blank page rather than being there waiting
                    // behind it. See `scriptVisible`.
                    .graphicsLayer { alpha = scriptAlpha }
            ) {
                val topPadding = with(density) { (viewportHeightPx * READING_LINE_FRACTION).toDp() }
                val bottomPadding =
                    with(density) { (viewportHeightPx * (1 - READING_LINE_FRACTION)).toDp() }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .wrapContentHeight(align = Alignment.Top, unbounded = true)
                        .graphicsLayer { translationY = -scrollPx }
                        .onSizeChanged { contentHeightPx = it.height.toFloat() }
                ) {
                    Spacer(modifier = Modifier.height(topPadding))

                    Text(
                        text = script,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp),
                        onTextLayout = { layout ->
                            val offsets = FloatArray(layout.lineCount) { layout.getLineTop(it) }
                            if (!offsets.contentEquals(lineOffsets)) {
                                lineOffsets = offsets
                                settleNext = true
                            }
                        }
                    )

                    Spacer(modifier = Modifier.height(bottomPadding))
                }
            }

            AnimatedVisibility(
                visible = showControls,
                modifier = Modifier.align(Alignment.BottomCenter),
                enter = fadeIn(tween(CONTROLS_FADE_MILLIS)),
                exit = fadeOut(tween(CONTROLS_FADE_MILLIS))
            ) {
                Row(
                    modifier = Modifier.padding(bottom = 48.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (pipManager.isPiPPossible) {
                        Box(
                            modifier = Modifier
                                .size(52.dp)
                                .glassed(CircleShape, isDark)
                                .clickableWithoutRipple {
                                    AnalyticsEvents.logButtonClick(
                                        if (pipManager.isPiPActive) "pip_exit" else "pip_enter",
                                        "teleprompter"
                                    )
                                    if (pipManager.isPiPActive) {
                                        pipManager.stopPiP()
                                        AnalyticsEvents.logEvent("teleprompter_pip_stopped")
                                    } else if (pipManager.enterPiP()) {
                                        AnalyticsEvents.logEvent("teleprompter_pip_started")
                                    }
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = if (pipManager.isPiPActive) {
                                    Icons.Filled.PictureInPictureAlt
                                } else {
                                    Icons.Filled.PictureInPicture
                                },
                                contentDescription = if (pipManager.isPiPActive) {
                                    "Close Overlay"
                                } else {
                                    "Start Overlay"
                                },
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .size(72.dp)
                            .background(AppColors.green(isDark), CircleShape)
                            .glassed(CircleShape, isDark)
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick(
                                    if (isPlaying || isCountingDown) "pause" else "play",
                                    "teleprompter"
                                )
                                togglePlayPause()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = if (isPlaying || isCountingDown) {
                                Icons.Filled.Pause
                            } else {
                                Icons.Filled.PlayArrow
                            },
                            contentDescription = if (isPlaying || isCountingDown) "Pause" else "Play",
                            tint = if (isDark) Color.Black else Color.White,
                            modifier = Modifier.size(28.dp)
                        )
                    }

                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .glassed(CircleShape, isDark)
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("restart", "teleprompter")
                                restart()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Refresh,
                            contentDescription = "Restart",
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }
    }
}

/**
 * The overlay form of the same screen: the timer above the script, and nothing
 * else. The window is small, so everything in it is smaller.
 *
 * The script scrolls as a fraction of its own total scroll range over the
 * duration the full screen measured. The overlay wraps the same text into more
 * lines than the full screen does; covering its own content over the same
 * duration is what keeps the two on the same word.
 */
@Composable
private fun TeleprompterOverlay(
    script: AnnotatedString,
    elapsedTime: () -> Double,
    scriptDuration: () -> Double,
    timeDisplay: String,
    timerColor: Color,
    isDark: Boolean
) {
    var contentHeightPx by remember { mutableFloatStateOf(0f) }
    var viewportHeightPx by remember { mutableFloatStateOf(0f) }
    var scrollPx by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        var lastFrame = 0L
        while (true) {
            withFrameNanos { now ->
                val delta = if (lastFrame == 0L) 0.0 else (now - lastFrame) / 1_000_000_000.0
                lastFrame = now

                // A resize keeps the reader at the same fraction of the script,
                // because the fraction is all the overlay ever tracks.
                val maxScroll = (contentHeightPx - viewportHeightPx).coerceAtLeast(0f)
                val duration = scriptDuration()
                val fraction = if (duration > 0) {
                    (elapsedTime() / duration).coerceIn(0.0, 1.0).toFloat()
                } else {
                    0f
                }
                val target = fraction * maxScroll

                val distance = target - scrollPx
                if (abs(distance) > 0.05f) {
                    scrollPx += (distance * (1 - exp(-delta / EASE_TIME_CONSTANT))).toFloat()
                } else {
                    scrollPx = target
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.background(isDark))
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .widthIn(min = 50.dp)
                    .height(24.dp)
                    .background(
                        AppColors.background(isDark).copy(alpha = 0.8f),
                        RoundedCornerShape(6.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = timeDisplay,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = timerColor,
                    textAlign = TextAlign.Center
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 8.dp)
                .clipToBounds()
                .onSizeChanged { viewportHeightPx = it.height.toFloat() }
                .scriptEdgeFade(isDark = isDark, top = 40.dp, bottom = 40.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .wrapContentHeight(align = Alignment.Top, unbounded = true)
                    .graphicsLayer { translationY = -scrollPx }
                    .onSizeChanged { contentHeightPx = it.height.toFloat() }
                    .padding(start = 12.dp, top = 40.dp, end = 12.dp, bottom = 40.dp)
            ) {
                Text(text = script, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

/**
 * The script as one continuous block at one brightness — position on screen is
 * what says where the reader is, so nothing highlights.
 */
private fun buildScript(
    content: TeleprompterContent,
    cueColor: CueColor,
    fontSize: Float,
    isDark: Boolean
): AnnotatedString {
    val textStyle = SpanStyle(
        fontSize = fontSize.sp,
        fontWeight = FontWeight.Medium,
        color = AppColors.textPrimary(isDark)
    )
    val cueStyle = SpanStyle(
        fontSize = (fontSize * 0.72f).sp,
        fontWeight = FontWeight.SemiBold,
        color = cueColor.color(isDark),
        letterSpacing = 0.05.em
    )
    val bodyParagraph = ParagraphStyle(lineHeight = (fontSize * 1.18f).sp)
    // The gap between paragraphs, as its own short line — the nearest Compose has
    // to the paragraph spacing the iOS layout applies.
    val gapParagraph = ParagraphStyle(lineHeight = (fontSize * 0.45f).sp)

    return buildAnnotatedString {
        val paragraphs = content.fullText.split("\n\n")

        paragraphs.forEachIndexed { paragraphIndex, paragraph ->
            if (paragraphIndex > 0) {
                withStyle(gapParagraph) { append("\n") }
            }

            withStyle(bodyParagraph) {
                val lines = paragraph.split("\n")

                lines.forEachIndexed { lineIndex, line ->
                    if (lineIndex > 0) append("\n")
                    if (line.isEmpty()) return@forEachIndexed

                    TeleprompterParser.segments(line).forEachIndexed { segmentIndex, segment ->
                        if (segmentIndex > 0) withStyle(textStyle) { append(" ") }

                        when (segment) {
                            is CueSegment.Cue -> withStyle(cueStyle) { append(segment.text) }
                            is CueSegment.Text -> withStyle(textStyle) { append(segment.text) }
                        }
                    }
                }
            }
        }
    }
}
