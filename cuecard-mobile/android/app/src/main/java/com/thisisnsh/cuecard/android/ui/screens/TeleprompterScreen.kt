package com.thisisnsh.cuecard.android.ui.screens

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPicture
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.models.TeleprompterContent
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.models.TeleprompterSettings
import com.thisisnsh.cuecard.android.services.TeleprompterPiPManager
import com.thisisnsh.cuecard.android.ui.components.glassEffect
import com.thisisnsh.cuecard.android.ui.theme.AppColors
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeleprompterScreen(
    content: TeleprompterContent,
    settings: TeleprompterSettings,
    onDismiss: () -> Unit
) {
    val isDark = isSystemInDarkTheme()
    val context = LocalContext.current
    val activity = context as? Activity
    val pipManager = remember { TeleprompterPiPManager.shared }
    val isInPiP = pipManager.isPiPActive

    var isPlaying by remember { mutableStateOf(false) }
    var elapsedTime by remember { mutableDoubleStateOf(0.0) }
    var currentWordIndex by remember { mutableIntStateOf(0) }
    var showControls by remember { mutableStateOf(true) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    var countdownValue by remember { mutableIntStateOf(0) }
    var isCountingDown by remember { mutableStateOf(false) }
    var pipViewportHeightPx by remember { mutableFloatStateOf(0f) }
    var fullViewportHeightPx by remember { mutableFloatStateOf(0f) }

    val scrollState = rememberScrollState()

    // Configure PiP manager
    LaunchedEffect(content, settings) {
        pipManager.configure(
            text = content.fullText,
            settings = settings,
            timerDuration = settings.timerDurationSeconds,
            isDarkMode = isDark,
            totalWords = content.words.size
        )
    }

    // Update PiP state when playback state changes
    LaunchedEffect(isPlaying, elapsedTime, currentWordIndex, countdownValue, isCountingDown) {
        pipManager.updateState(
            elapsedTime = elapsedTime,
            isPlaying = isPlaying,
            currentWordIndex = currentWordIndex,
            countdownValue = countdownValue,
            isCountingDown = isCountingDown
        )
    }

    // Timer properties
    val timerDuration = settings.timerDurationSeconds
    val remainingTime = if (timerDuration > 0) timerDuration - elapsedTime.toInt() else elapsedTime.toInt()
    val isOvertime = timerDuration > 0 && elapsedTime.toInt() > timerDuration

    val timerColor = when {
        isCountingDown -> AppColors.pink(isDark) // Pink during countdown like iOS
        timerDuration <= 0 -> AppColors.textPrimary(isDark)
        else -> AppColors.timerColor(
            remainingSeconds = timerDuration - elapsedTime.toInt(),
            totalSeconds = timerDuration,
            isDark = isDark
        )
    }

    val timeDisplay = when {
        // Show countdown in mm:ss format like iOS
        isCountingDown -> " ${TeleprompterParser.formatTime(countdownValue)} "
        timerDuration > 0 -> " ${TeleprompterParser.formatTime(timerDuration - elapsedTime.toInt())} "
        else -> " ${TeleprompterParser.formatTime(elapsedTime.toInt())} "
    }

    LaunchedEffect(isInPiP) {
        if (isInPiP) {
            showControls = false
        }
    }

    // Log screen view on appear
    LaunchedEffect(Unit) {
        Firebase.analytics.logEvent("teleprompter_started") {
            param("word_count", content.words.size.toLong())
            param("timer_duration", timerDuration.toLong())
        }
    }

    // Timer loop
    LaunchedEffect(isPlaying) {
        if (isPlaying) {
            while (isPlaying) {
                delay(33) // ~30 FPS
                elapsedTime += 0.033

                // Update current word index
                val wordsPerSecond = settings.wordsPerMinute / 60.0
                val newWordIndex = min((elapsedTime * wordsPerSecond).toInt(), content.words.size - 1)
                if (newWordIndex != currentWordIndex && newWordIndex >= 0) {
                    currentWordIndex = newWordIndex
                }
            }
        }
    }

    // Countdown timer
    LaunchedEffect(isCountingDown) {
        if (isCountingDown) {
            while (countdownValue > 0) {
                delay(1000)
                countdownValue--
            }
            isCountingDown = false
            isPlaying = true
            Firebase.analytics.logEvent("teleprompter_play", null)
        }
    }

    // Auto-hide controls after 3 seconds when playing
    LaunchedEffect(isPlaying, showControls) {
        if (isPlaying && showControls) {
            delay(3000)
            showControls = false
        }
    }

    // Cleanup on dismiss
    DisposableEffect(Unit) {
        onDispose {
            pipManager.cleanup()
            Firebase.analytics.logEvent("teleprompter_closed") {
                param("elapsed_time", elapsedTime.toLong())
            }
        }
    }

    // Helper functions
    fun togglePlayPause() {
        if (isPlaying || isCountingDown) {
            // Pause
            if (isCountingDown) {
                isCountingDown = false
                countdownValue = 0
            } else {
                isPlaying = false
                Firebase.analytics.logEvent("teleprompter_pause", null)
            }
        } else {
            // Start countdown then play
            if (settings.countdownSeconds > 0) {
                countdownValue = settings.countdownSeconds
                isCountingDown = true
            } else {
                isPlaying = true
                Firebase.analytics.logEvent("teleprompter_play", null)
            }
        }
        showControls = true
    }

    fun restart() {
        isPlaying = false
        isCountingDown = false
        countdownValue = 0
        elapsedTime = 0.0
        currentWordIndex = 0
        Firebase.analytics.logEvent("teleprompter_restart", null)
    }

    fun seekForward() {
        val wordsPerSecond = settings.wordsPerMinute / 60.0
        val wordsToSkip = (10 * wordsPerSecond).toInt()
        currentWordIndex = min(currentWordIndex + wordsToSkip, content.words.size - 1)
        elapsedTime = currentWordIndex / wordsPerSecond
    }

    fun seekBackward() {
        val wordsPerSecond = settings.wordsPerMinute / 60.0
        val wordsToSkip = (10 * wordsPerSecond).toInt()
        currentWordIndex = max(currentWordIndex - wordsToSkip, 0)
        elapsedTime = currentWordIndex / wordsPerSecond
    }

    val density = LocalDensity.current
    val textFontSize = if (isInPiP) settings.pipFontSize else settings.fontSize
    val textHorizontalPadding = if (isInPiP) 12.dp else 24.dp
    val baseTopPadding = if (isInPiP) 40.dp else 60.dp
    val baseBottomPadding = if (isInPiP) 40.dp else 200.dp
    val fullTopPadding = if (fullViewportHeightPx > 0f) {
        with(density) { (fullViewportHeightPx * 0.4f).toDp() }
    } else {
        baseTopPadding
    }
    val fullBottomPadding = if (fullViewportHeightPx > 0f) {
        with(density) { (fullViewportHeightPx * 0.6f).toDp() }
    } else {
        baseBottomPadding
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.background(isDark))
            .offset { IntOffset(dragOffset.roundToInt(), 0) }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { offset ->
                        // Only respond to swipes starting from left edge
                        if (offset.x > 40.dp.toPx()) {
                            return@detectHorizontalDragGestures
                        }
                    },
                    onDragEnd = {
                        if (dragOffset > 100.dp.toPx()) {
                            onDismiss()
                        } else {
                            dragOffset = 0f
                        }
                    },
                    onDragCancel = {
                        dragOffset = 0f
                    },
                    onHorizontalDrag = { change, dragAmount ->
                        if (change.position.x < 40.dp.toPx() || dragOffset > 0) {
                            dragOffset = max(0f, dragOffset + dragAmount)
                        }
                    }
                )
            }
            .clickable(
                enabled = !isInPiP,
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                showControls = !showControls
            }
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            if (isInPiP) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 6.dp),
                    contentAlignment = Alignment.TopCenter
                ) {
                    Text(
                        text = timeDisplay,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = timerColor,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(AppColors.background(isDark).copy(alpha = 0.8f))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            } else {
                // Top App Bar - matching iOS layout
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            text = "Teleprompter",
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "Close",
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    },
                    actions = {
                        // Timer in top bar like iOS
                        Text(
                            text = timeDisplay,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            color = timerColor,
                            modifier = Modifier.padding(end = 8.dp)
                        )
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.background(isDark)
                    )
                )
            }

            // Content area
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                if (isInPiP) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .onSizeChanged { pipViewportHeightPx = it.height.toFloat() }
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(scrollState)
                        ) {
                            TeleprompterPiPText(
                                content = content,
                                fontSize = textFontSize,
                                currentWordIndex = currentWordIndex,
                                elapsedTime = elapsedTime,
                                wordsPerMinute = settings.wordsPerMinute,
                                autoScroll = settings.autoScroll,
                                isPlaying = isPlaying,
                                isDark = isDark,
                                scrollState = scrollState,
                                viewportHeightPx = pipViewportHeightPx,
                                horizontalPadding = textHorizontalPadding,
                                topPadding = baseTopPadding,
                                bottomPadding = baseBottomPadding
                            )
                        }

                        val bgColor = AppColors.background(isDark)
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(40.dp)
                                .align(Alignment.TopCenter)
                                .padding(horizontal = textHorizontalPadding)
                                .background(
                                    Brush.verticalGradient(
                                        listOf(bgColor, bgColor.copy(alpha = 0f))
                                    )
                                )
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(40.dp)
                                .align(Alignment.BottomCenter)
                                .padding(horizontal = textHorizontalPadding)
                                .background(
                                    Brush.verticalGradient(
                                        listOf(bgColor.copy(alpha = 0f), bgColor)
                                    )
                                )
                        )
                    }
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .onSizeChanged { fullViewportHeightPx = it.height.toFloat() }
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(scrollState)
                        ) {
                            TeleprompterFullText(
                                content = content,
                                fontSize = textFontSize,
                                currentWordIndex = currentWordIndex,
                                elapsedTime = elapsedTime,
                                wordsPerMinute = settings.wordsPerMinute,
                                autoScroll = settings.autoScroll,
                                isPlaying = isPlaying,
                                isDark = isDark,
                                scrollState = scrollState,
                                viewportHeightPx = fullViewportHeightPx,
                                horizontalPadding = textHorizontalPadding,
                                topPadding = fullTopPadding,
                                bottomPadding = fullBottomPadding
                            )
                        }

                        val bgColor = AppColors.background(isDark)
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(80.dp)
                                .align(Alignment.TopCenter)
                                .padding(horizontal = textHorizontalPadding)
                                .background(
                                    Brush.verticalGradient(
                                        listOf(bgColor, bgColor.copy(alpha = 0f))
                                    )
                                )
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(80.dp)
                                .align(Alignment.BottomCenter)
                                .padding(horizontal = textHorizontalPadding)
                                .background(
                                    Brush.verticalGradient(
                                        listOf(bgColor.copy(alpha = 0f), bgColor)
                                    )
                                )
                        )
                    }
                }
            }
        }

        // Controls overlay at bottom
        AnimatedVisibility(
            visible = showControls && !isInPiP,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 48.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Backward button
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .glassEffect(shape = CircleShape, isDark = isDark)
                        .clickable { seekBackward() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.FastRewind,
                        contentDescription = "Backward 10s",
                        modifier = Modifier.size(24.dp),
                        tint = AppColors.textPrimary(isDark)
                    )
                }

                Spacer(modifier = Modifier.width(24.dp))

                // PiP button
                if (pipManager.isPiPPossible) {
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .clip(CircleShape)
                            .glassEffect(shape = CircleShape, isDark = isDark)
                            .clickable {
                                activity?.let { act ->
                                    if (pipManager.enterPiP(act)) {
                                        Firebase.analytics.logEvent("teleprompter_pip_started", null)
                                    }
                                }
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.PictureInPicture,
                            contentDescription = "Picture in Picture",
                            modifier = Modifier.size(20.dp),
                            tint = AppColors.textPrimary(isDark)
                        )
                    }

                    Spacer(modifier = Modifier.width(24.dp))
                }

                // Play/Pause button
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(AppColors.green(isDark))
                        .glassEffect(shape = CircleShape, isDark = isDark)
                        .clickable { togglePlayPause() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isPlaying || isCountingDown) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play",
                        modifier = Modifier.size(28.dp),
                        tint = if (isDark) Color.Black else Color.White
                    )
                }

                Spacer(modifier = Modifier.width(24.dp))

                // Restart button
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .glassEffect(shape = CircleShape, isDark = isDark)
                        .clickable { restart() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = "Restart",
                        modifier = Modifier.size(20.dp),
                        tint = AppColors.textPrimary(isDark)
                    )
                }

                Spacer(modifier = Modifier.width(24.dp))

                // Forward button
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .glassEffect(shape = CircleShape, isDark = isDark)
                        .clickable { seekForward() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.FastForward,
                        contentDescription = "Forward 10s",
                        modifier = Modifier.size(24.dp),
                        tint = AppColors.textPrimary(isDark)
                    )
                }
            }
        }
    }
}

@Composable
private fun TeleprompterFullText(
    content: TeleprompterContent,
    fontSize: Int,
    currentWordIndex: Int,
    elapsedTime: Double,
    wordsPerMinute: Int,
    autoScroll: Boolean,
    isPlaying: Boolean,
    isDark: Boolean,
    scrollState: ScrollState,
    viewportHeightPx: Float,
    horizontalPadding: Dp,
    topPadding: Dp,
    bottomPadding: Dp
) {
    val textColor = AppColors.textPrimary(isDark)
    val pinkColor = AppColors.pink(isDark)
    val displayResult = remember(content.fullText) {
        TeleprompterParser.buildDisplayText(content.fullText)
    }
    val displayText = displayResult.text
    val noteRanges = displayResult.noteRanges
    val wordsPerSecond = wordsPerMinute / 60.0
    val highlightProgress = if (autoScroll) {
        if (elapsedTime == 0.0 && !isPlaying) -1_000_000.0 else elapsedTime * wordsPerSecond
    } else {
        Double.MAX_VALUE
    }
    val progressBucket = if (autoScroll) (highlightProgress * 10).roundToInt() else 0
    val lineHeight = (fontSize * 1.18f).sp
    var textLayoutResult by remember { mutableStateOf<TextLayoutResult?>(null) }
    val density = LocalDensity.current
    val topPaddingPx = with(density) { topPadding.toPx() }
    val noteStyle = remember(fontSize, pinkColor) {
        SpanStyle(
            color = pinkColor,
            fontSize = (fontSize * 0.72f).sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (fontSize * 0.05f).sp,
            fontFamily = FontFamily.SansSerif
        )
    }

    fun smoothstep(edge0: Double, edge1: Double, x: Double): Double {
        val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    fun highlightAlpha(index: Int): Float {
        val distance = highlightProgress - index.toDouble()
        val blend = smoothstep(-2.0, 0.0, distance)
        return (0.3f + blend.toFloat() * 0.7f)
    }

    val annotatedText = remember(displayText, fontSize, textColor, noteStyle, progressBucket, autoScroll, noteRanges) {
        buildAnnotatedString {
            append(displayText)
            noteRanges.forEach { range ->
                if (range.first < range.last + 1) {
                    addStyle(noteStyle, range.first, range.last + 1)
                }
            }
            content.words.forEachIndexed { index, word ->
                if (word.startIndex >= displayText.length) return@forEachIndexed
                val start = word.startIndex.coerceAtLeast(0)
                val end = word.endIndex.coerceAtMost(displayText.length)
                if (start >= end) return@forEachIndexed

                val isNote = noteRanges.any { range ->
                    range.contains(start) && range.contains(end - 1)
                }
                if (!isNote) {
                    addStyle(
                        SpanStyle(
                            color = textColor.copy(alpha = highlightAlpha(index)),
                            fontSize = fontSize.sp,
                            fontWeight = FontWeight.Medium,
                            fontFamily = FontFamily.SansSerif
                        ),
                        start,
                        end
                    )
                }
            }
        }
    }

    LaunchedEffect(currentWordIndex, textLayoutResult, autoScroll, viewportHeightPx, scrollState.maxValue) {
        val layout = textLayoutResult ?: return@LaunchedEffect
        if (!autoScroll) return@LaunchedEffect
        if (viewportHeightPx <= 0f) return@LaunchedEffect
        val word = content.words.getOrNull(currentWordIndex) ?: return@LaunchedEffect
        if (displayText.isEmpty() || word.startIndex >= displayText.length) return@LaunchedEffect

        val rect = layout.getBoundingBox(word.startIndex)
        val target = rect.top + topPaddingPx - (viewportHeightPx / 3f)
        val maxScroll = scrollState.maxValue.toFloat()
        val clamped = target.coerceIn(0f, maxScroll)
        scrollState.animateScrollTo(clamped.roundToInt())
    }

    Text(
        text = annotatedText,
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = horizontalPadding,
                end = horizontalPadding,
                top = topPadding,
                bottom = bottomPadding
            ),
        color = textColor,
        style = TextStyle(
            lineHeight = lineHeight,
            fontFamily = FontFamily.SansSerif
        ),
        onTextLayout = { textLayoutResult = it }
    )
}

@Composable
private fun TeleprompterPiPText(
    content: TeleprompterContent,
    fontSize: Int,
    currentWordIndex: Int,
    elapsedTime: Double,
    wordsPerMinute: Int,
    autoScroll: Boolean,
    isPlaying: Boolean,
    isDark: Boolean,
    scrollState: ScrollState,
    viewportHeightPx: Float,
    horizontalPadding: Dp,
    topPadding: Dp,
    bottomPadding: Dp
) {
    val textColor = AppColors.textPrimary(isDark)
    val pinkColor = AppColors.pink(isDark)
    val displayResult = remember(content.fullText) {
        TeleprompterParser.buildDisplayText(content.fullText)
    }
    val displayText = displayResult.text
    val noteRanges = displayResult.noteRanges
    val wordsPerSecond = wordsPerMinute / 60.0
    val highlightProgress = if (autoScroll) {
        if (elapsedTime == 0.0 && !isPlaying) -1_000_000.0 else elapsedTime * wordsPerSecond
    } else {
        Double.MAX_VALUE
    }
    val progressBucket = if (autoScroll) (highlightProgress * 10).roundToInt() else 0
    val lineHeight = (fontSize * 1.0f).sp
    var textLayoutResult by remember { mutableStateOf<TextLayoutResult?>(null) }
    val density = LocalDensity.current
    val topPaddingPx = with(density) { topPadding.toPx() }
    val noteStyle = remember(fontSize, pinkColor) {
        SpanStyle(
            color = pinkColor,
            fontSize = (fontSize * 0.72f).sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-fontSize * 0.01f).sp,
            fontFamily = FontFamily.SansSerif
        )
    }

    fun smoothstep(edge0: Double, edge1: Double, x: Double): Double {
        val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    fun highlightAlpha(index: Int): Float {
        val distance = highlightProgress - index.toDouble()
        val blend = smoothstep(-2.0, 0.0, distance)
        return (0.3f + blend.toFloat() * 0.7f)
    }

    val annotatedText = remember(displayText, fontSize, textColor, noteStyle, progressBucket, autoScroll, noteRanges) {
        buildAnnotatedString {
            append(displayText)
            noteRanges.forEach { range ->
                if (range.first < range.last + 1) {
                    addStyle(noteStyle, range.first, range.last + 1)
                }
            }
            content.words.forEachIndexed { index, word ->
                if (word.startIndex >= displayText.length) return@forEachIndexed
                val start = word.startIndex.coerceAtLeast(0)
                val end = word.endIndex.coerceAtMost(displayText.length)
                if (start >= end) return@forEachIndexed

                val isNote = noteRanges.any { range ->
                    range.contains(start) && range.contains(end - 1)
                }
                if (!isNote) {
                    addStyle(
                        SpanStyle(
                            color = textColor.copy(alpha = highlightAlpha(index)),
                            fontSize = fontSize.sp,
                            fontWeight = FontWeight.Medium,
                            fontFamily = FontFamily.SansSerif
                        ),
                        start,
                        end
                    )
                }
            }
        }
    }

    LaunchedEffect(currentWordIndex, textLayoutResult, autoScroll, viewportHeightPx, scrollState.maxValue) {
        val layout = textLayoutResult ?: return@LaunchedEffect
        if (!autoScroll) return@LaunchedEffect
        if (viewportHeightPx <= 0f) return@LaunchedEffect
        val word = content.words.getOrNull(currentWordIndex) ?: return@LaunchedEffect
        if (displayText.isEmpty() || word.startIndex >= displayText.length) return@LaunchedEffect

        val rect = layout.getBoundingBox(word.startIndex)
        val target = rect.top + topPaddingPx - (viewportHeightPx / 3f)
        val maxScroll = scrollState.maxValue.toFloat()
        val clamped = target.coerceIn(0f, maxScroll)
        scrollState.animateScrollTo(clamped.roundToInt())
    }

    Text(
        text = annotatedText,
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = horizontalPadding,
                end = horizontalPadding,
                top = topPadding,
                bottom = bottomPadding
            ),
        color = textColor,
        style = TextStyle(
            lineHeight = lineHeight,
            lineHeightStyle = LineHeightStyle(
                alignment = LineHeightStyle.Alignment.Center,
                trim = LineHeightStyle.Trim.Both
            ),
            platformStyle = PlatformTextStyle(includeFontPadding = false),
            fontFamily = FontFamily.SansSerif
        ),
        onTextLayout = { textLayoutResult = it }
    )
}

@Composable
private fun TeleprompterText(
    content: TeleprompterContent,
    fontSize: Int,
    currentWordIndex: Int,
    elapsedTime: Double,
    wordsPerMinute: Int,
    autoScroll: Boolean,
    isPlaying: Boolean,
    isDark: Boolean
) {
    val textColor = AppColors.textPrimary(isDark)
    val pinkColor = AppColors.pink(isDark)
    val wordsPerSecond = wordsPerMinute / 60.0
    val highlightProgress = if (autoScroll) {
        if (elapsedTime == 0.0 && !isPlaying) -Double.MAX_VALUE else elapsedTime * wordsPerSecond
    } else {
        Double.MAX_VALUE
    }
    val fadeRange = 2.0

    // Smoothstep function for easing
    fun smoothstep(edge0: Double, edge1: Double, x: Double): Double {
        val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    fun highlightAlpha(index: Int): Float {
        val distance = highlightProgress - index.toDouble()
        val blend = smoothstep(-fadeRange, 0.0, distance)
        return (0.3f + blend.toFloat() * 0.7f)
    }

    // Build the text content
    val paragraphs = content.fullText.split("\n\n")
    var globalWordIndex = 0

    Column {
        paragraphs.forEachIndexed { paragraphIndex, paragraph ->
            if (paragraphIndex > 0) {
                Spacer(modifier = Modifier.padding(vertical = (fontSize * 0.45f / 2).dp))
            }

            val lines = paragraph.split("\n")

            lines.forEachIndexed { lineIndex, line ->
                if (line.isEmpty()) return@forEachIndexed

                if (line.contains("[note")) {
                    // Note line - render in pink
                    val noteContent = TeleprompterParser.extractNoteContent(line)
                    val noteWords = noteContent.split(" ").filter { it.isNotBlank() }

                    Text(
                        text = buildAnnotatedString {
                            noteWords.forEachIndexed { wordIndex, word ->
                                if (wordIndex > 0) append(" ")
                                withStyle(
                                    SpanStyle(
                                        color = pinkColor,
                                        fontSize = (fontSize * 0.72f).sp,
                                        fontWeight = FontWeight.SemiBold,
                                        letterSpacing = (fontSize * 0.05f).sp,
                                        fontFamily = FontFamily.SansSerif
                                    )
                                ) {
                                    append(word)
                                }
                                globalWordIndex++
                            }
                        },
                        lineHeight = (fontSize * 1.18f).sp,
                        modifier = Modifier.padding(vertical = (fontSize * 0.18f / 2).dp)
                    )
                } else {
                    // Regular text with word highlighting
                    val words = line.split(" ").filter { it.isNotBlank() }

                    Text(
                        text = buildAnnotatedString {
                            words.forEachIndexed { wordIndex, word ->
                                if (wordIndex > 0) append(" ")
                                val alpha = highlightAlpha(globalWordIndex)
                                withStyle(
                                    SpanStyle(
                                        color = textColor.copy(alpha = alpha),
                                        fontSize = fontSize.sp,
                                        fontWeight = FontWeight.Medium,
                                        fontFamily = FontFamily.SansSerif
                                    )
                                ) {
                                    append(word)
                                }
                                globalWordIndex++
                            }
                        },
                        lineHeight = (fontSize * 1.18f).sp,
                        modifier = Modifier.padding(vertical = (fontSize * 0.18f / 2).dp)
                    )
                }
            }
        }
    }
}
