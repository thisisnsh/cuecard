package com.thisisnsh.cuecard.mobile

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import java.util.regex.Pattern

/**
 * Segment of teleprompter content with optional timing
 */
data class TeleprompterSegment(
    val text: String,
    val durationSeconds: Int?,
    val startTimeSeconds: Int
)

/**
 * Manages Picture-in-Picture teleprompter display on Android
 * Requires Android 8.0+ (API 26+) for PiP support
 */
@RequiresApi(Build.VERSION_CODES.O)
class TeleprompterPiPManager private constructor(private val activity: Activity) {

    companion object {
        private var instance: TeleprompterPiPManager? = null

        fun getInstance(activity: Activity): TeleprompterPiPManager {
            return instance ?: TeleprompterPiPManager(activity).also { instance = it }
        }

        private const val ACTION_PLAY_PAUSE = "com.thisisnsh.cuecard.mobile.PLAY_PAUSE"
        private const val ACTION_STOP = "com.thisisnsh.cuecard.mobile.STOP"
    }

    // Properties
    private var segments: List<TeleprompterSegment> = emptyList()
    private var currentSegmentIndex: Int = 0
    private var scrollOffset: Float = 0f
    private var startTime: Long = 0
    private var pausedTime: Long = 0
    private var isPaused: Boolean = false

    private var fontSize: Float = 16f
    private var defaultScrollSpeed: Float = 50f // pixels per second
    private var opacity: Float = 1f

    private val pinkColor = Color.parseColor("#FF69B4")
    private val backgroundColor = Color.parseColor("#1A1A1A")
    private val textColor = Color.WHITE
    private val timerColor = Color.parseColor("#808080")

    // Surface for rendering
    private var surfaceView: SurfaceView? = null
    private var renderHandler: Handler? = null
    private var renderRunnable: Runnable? = null

    // PiP receiver
    private var pipReceiver: BroadcastReceiver? = null

    /**
     * Start the teleprompter in PiP mode
     */
    fun startTeleprompter(content: String, fontSize: Float, defaultSpeed: Float, opacity: Float) {
        this.fontSize = fontSize
        this.defaultScrollSpeed = defaultSpeed * 50f
        this.opacity = opacity

        // Parse content into segments
        this.segments = parseContent(content)
        this.currentSegmentIndex = 0
        this.scrollOffset = 0f
        this.isPaused = false
        this.pausedTime = 0

        // Create surface view for rendering
        setupSurfaceView()

        // Register broadcast receiver for PiP controls
        registerPiPReceiver()

        // Start rendering
        startTime = System.currentTimeMillis()
        startRendering()

        // Enter PiP mode
        enterPiP()
    }

    /**
     * Pause the teleprompter
     */
    fun pause() {
        if (!isPaused) {
            isPaused = true
            pausedTime = System.currentTimeMillis() - startTime
        }
    }

    /**
     * Resume the teleprompter
     */
    fun resume() {
        if (isPaused) {
            isPaused = false
            startTime = System.currentTimeMillis() - pausedTime
        }
    }

    /**
     * Stop the teleprompter and exit PiP
     */
    fun stop() {
        renderHandler?.removeCallbacks(renderRunnable ?: return)
        renderHandler = null
        renderRunnable = null

        unregisterPiPReceiver()

        surfaceView?.let {
            (it.parent as? ViewGroup)?.removeView(it)
        }
        surfaceView = null

        // Exit PiP mode if active
        if (activity.isInPictureInPictureMode) {
            activity.moveTaskToBack(false)
        }
    }

    // Content Parsing

    private fun parseContent(content: String): List<TeleprompterSegment> {
        val segments = mutableListOf<TeleprompterSegment>()
        var cumulativeTime = 0

        val timePattern = Pattern.compile("\\[time\\s+(\\d{1,2}):(\\d{2})\\]")
        val matcher = timePattern.matcher(content)

        var lastEnd = 0
        var pendingDuration: Int? = null

        while (matcher.find()) {
            val textBefore = content.substring(lastEnd, matcher.start())
            val cleanedText = cleanTextForDisplay(textBefore)

            if (cleanedText.trim().isNotEmpty()) {
                segments.add(TeleprompterSegment(
                    text = cleanedText,
                    durationSeconds = pendingDuration,
                    startTimeSeconds = cumulativeTime
                ))

                pendingDuration?.let { cumulativeTime += it }
            }

            val minutes = matcher.group(1)?.toIntOrNull() ?: 0
            val seconds = matcher.group(2)?.toIntOrNull() ?: 0
            pendingDuration = minutes * 60 + seconds

            lastEnd = matcher.end()
        }

        // Handle remaining text
        val remainingText = content.substring(lastEnd)
        val cleanedRemaining = cleanTextForDisplay(remainingText)

        if (cleanedRemaining.trim().isNotEmpty()) {
            segments.add(TeleprompterSegment(
                text = cleanedRemaining,
                durationSeconds = pendingDuration,
                startTimeSeconds = cumulativeTime
            ))
        }

        // If no segments, create one with all content
        if (segments.isEmpty() && content.trim().isNotEmpty()) {
            segments.add(TeleprompterSegment(
                text = cleanTextForDisplay(content),
                durationSeconds = null,
                startTimeSeconds = 0
            ))
        }

        return segments
    }

    private fun cleanTextForDisplay(text: String): String {
        val timePattern = Pattern.compile("\\[time\\s+\\d{1,2}:\\d{2}\\]")
        return timePattern.matcher(text).replaceAll("").trim()
    }

    // Surface Setup

    private fun setupSurfaceView() {
        surfaceView = SurfaceView(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            visibility = View.VISIBLE
        }

        // Add to activity's content view
        val contentView = activity.window.decorView.findViewById<ViewGroup>(android.R.id.content)
        contentView.addView(surfaceView)

        surfaceView?.holder?.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                // Surface ready for rendering
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                // Handle size changes
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                // Surface destroyed
            }
        })
    }

    // PiP Mode

    private fun enterPiP() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .setActions(createPiPActions())
                .build()

            activity.enterPictureInPictureMode(params)
        }
    }

    private fun createPiPActions(): List<RemoteAction> {
        val actions = mutableListOf<RemoteAction>()

        // Play/Pause action
        val playPauseIntent = PendingIntent.getBroadcast(
            activity,
            0,
            Intent(ACTION_PLAY_PAUSE),
            PendingIntent.FLAG_IMMUTABLE
        )

        val playPauseIcon = if (isPaused) {
            Icon.createWithResource(activity, android.R.drawable.ic_media_play)
        } else {
            Icon.createWithResource(activity, android.R.drawable.ic_media_pause)
        }

        actions.add(RemoteAction(
            playPauseIcon,
            if (isPaused) "Play" else "Pause",
            "Toggle playback",
            playPauseIntent
        ))

        // Stop action
        val stopIntent = PendingIntent.getBroadcast(
            activity,
            1,
            Intent(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE
        )

        actions.add(RemoteAction(
            Icon.createWithResource(activity, android.R.drawable.ic_menu_close_clear_cancel),
            "Stop",
            "Stop teleprompter",
            stopIntent
        ))

        return actions
    }

    @Suppress("UnspecifiedRegisterReceiverFlag")
    private fun registerPiPReceiver() {
        pipReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    ACTION_PLAY_PAUSE -> {
                        if (isPaused) resume() else pause()
                        updatePiPParams()
                    }
                    ACTION_STOP -> stop()
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY_PAUSE)
            addAction(ACTION_STOP)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(pipReceiver, filter)
        }
    }

    private fun unregisterPiPReceiver() {
        pipReceiver?.let {
            try {
                activity.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Receiver not registered
            }
        }
        pipReceiver = null
    }

    private fun updatePiPParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity.isInPictureInPictureMode) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .setActions(createPiPActions())
                .build()

            activity.setPictureInPictureParams(params)
        }
    }

    // Rendering

    private fun startRendering() {
        renderHandler = Handler(Looper.getMainLooper())
        renderRunnable = object : Runnable {
            override fun run() {
                if (!isPaused) {
                    renderFrame()
                }
                renderHandler?.postDelayed(this, 33) // ~30 FPS
            }
        }
        renderHandler?.post(renderRunnable!!)
    }

    private fun renderFrame() {
        val holder = surfaceView?.holder ?: return
        val canvas = holder.lockCanvas() ?: return

        try {
            val elapsedTime = (System.currentTimeMillis() - startTime) / 1000f

            // Calculate current segment and scroll offset
            var currentSegment: TeleprompterSegment? = null
            var segmentElapsedTime = 0f
            var accumulatedTime = 0f

            for ((index, segment) in segments.withIndex()) {
                val segmentDuration = (segment.durationSeconds ?: estimateSegmentDuration(segment)).toFloat()

                if (accumulatedTime + segmentDuration > elapsedTime) {
                    currentSegment = segment
                    currentSegmentIndex = index
                    segmentElapsedTime = elapsedTime - accumulatedTime
                    break
                }

                accumulatedTime += segmentDuration
            }

            // If we've passed all segments, use the last one
            if (currentSegment == null && segments.isNotEmpty()) {
                currentSegment = segments.last()
                currentSegmentIndex = segments.size - 1
            }

            // Render frame
            currentSegment?.let {
                renderTeleprompterFrame(canvas, it, segmentElapsedTime)
            }
        } finally {
            holder.unlockCanvasAndPost(canvas)
        }
    }

    private fun estimateSegmentDuration(segment: TeleprompterSegment): Int {
        val lineCount = segment.text.split("\n").size
        val estimatedHeight = lineCount * fontSize * 1.5f
        return (estimatedHeight / defaultScrollSpeed).toInt().coerceAtLeast(1)
    }

    private fun renderTeleprompterFrame(canvas: Canvas, segment: TeleprompterSegment, segmentElapsedTime: Float) {
        val width = canvas.width.toFloat()
        val height = canvas.height.toFloat()

        // Background
        canvas.drawColor(backgroundColor)

        // Calculate scroll speed for this segment
        val scrollSpeed: Float = if (segment.durationSeconds != null && segment.durationSeconds > 0) {
            val estimatedHeight = estimateTextHeight(segment.text, width - 32)
            estimatedHeight / segment.durationSeconds
        } else {
            defaultScrollSpeed
        }

        val scrollOffset = segmentElapsedTime * scrollSpeed

        // Render text with scroll offset
        val yOffset = height / 2 - scrollOffset
        renderSegmentText(canvas, segment.text, 16f, yOffset, width - 32)

        // Render timer (fixed at top-left)
        segment.durationSeconds?.let { duration ->
            val remaining = maxOf(0, duration - segmentElapsedTime.toInt())
            val minutes = remaining / 60
            val seconds = remaining % 60
            val timerText = String.format("[%02d:%02d]", minutes, seconds)

            val timerPaint = Paint().apply {
                color = timerColor
                textSize = 14f * activity.resources.displayMetrics.density
                typeface = Typeface.MONOSPACE
                isAntiAlias = true
            }

            // Timer background
            val bgPaint = Paint().apply {
                color = Color.argb(153, 0, 0, 0) // 60% opacity black
            }

            val timerWidth = timerPaint.measureText(timerText)
            canvas.drawRoundRect(
                RectF(12f, 12f, 24f + timerWidth, 40f),
                4f, 4f,
                bgPaint
            )

            canvas.drawText(timerText, 16f, 32f, timerPaint)
        }
    }

    private fun renderSegmentText(canvas: Canvas, text: String, x: Float, y: Float, maxWidth: Float) {
        val notePattern = Pattern.compile("\\[note\\s+([^\\]]+)\\]")

        val textPaint = Paint().apply {
            color = textColor
            textSize = fontSize * activity.resources.displayMetrics.density
            isAntiAlias = true
        }

        val pinkPaint = Paint().apply {
            color = pinkColor
            textSize = fontSize * activity.resources.displayMetrics.density * 0.8f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isAntiAlias = true
        }

        // Split into lines and render
        val lines = text.split("\n")
        var currentY = y
        val lineHeight = textPaint.fontSpacing

        for (line in lines) {
            // Check for [note ...] tags and render with pink
            val matcher = notePattern.matcher(line)
            var lastEnd = 0
            var currentX = x

            while (matcher.find()) {
                // Draw text before the note
                val textBefore = line.substring(lastEnd, matcher.start())
                canvas.drawText(textBefore, currentX, currentY, textPaint)
                currentX += textPaint.measureText(textBefore)

                // Draw the note in pink
                val noteContent = "[${matcher.group(1)}]"
                canvas.drawText(noteContent, currentX, currentY, pinkPaint)
                currentX += pinkPaint.measureText(noteContent)

                lastEnd = matcher.end()
            }

            // Draw remaining text
            if (lastEnd < line.length) {
                val remainingText = line.substring(lastEnd)
                canvas.drawText(remainingText, currentX, currentY, textPaint)
            } else if (lastEnd == 0) {
                // No notes found, draw whole line
                canvas.drawText(line, x, currentY, textPaint)
            }

            currentY += lineHeight
        }
    }

    private fun estimateTextHeight(text: String, maxWidth: Float): Float {
        val textPaint = Paint().apply {
            textSize = fontSize * activity.resources.displayMetrics.density
        }

        val lines = text.split("\n").size
        return lines * textPaint.fontSpacing
    }
}
