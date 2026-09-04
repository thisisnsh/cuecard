package com.thisisnsh.cuecard.android.services

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.thisisnsh.cuecard.android.R
import java.lang.ref.WeakReference

/**
 * Drives the floating overlay, which on Android is the activity itself in
 * picture-in-picture.
 *
 * iOS renders a second copy of the script into an AVKit window; here the same
 * window shrinks, so the teleprompter simply draws its overlay form while this
 * says the overlay is live. What the two share is the contract: the same clock,
 * the same duration, and play/pause and restart reaching the same handlers.
 */
class TeleprompterPiPManager private constructor() {

    companion object {
        val shared = TeleprompterPiPManager()

        private const val ACTION_CONTROL = "com.thisisnsh.cuecard.android.PIP_CONTROL"
        private const val EXTRA_CONTROL = "control"
        private const val CONTROL_PLAY_PAUSE = "play_pause"
        private const val CONTROL_RESTART = "restart"
        private const val REQUEST_PLAY_PAUSE = 1
        private const val REQUEST_RESTART = 2
    }

    // State
    var isPiPActive by mutableStateOf(false)
        private set

    var isPiPPossible by mutableStateOf(false)
        private set

    var isPlaying = false
    var elapsedTime: Double = 0.0
    var countdownValue: Int = 0
    var isCountingDown: Boolean = false

    /**
     * How long the whole script takes at the current speed, measured on the full
     * screen. The overlay wraps the same text into more lines than the full
     * screen does, so it covers its own content over this duration rather than
     * counting its own lines — that is what keeps the two on the same word.
     */
    var scriptDuration: Double = 0.0

    // Content properties
    var settings: TeleprompterSettings = TeleprompterSettings.DEFAULT
        private set
    var timerDuration: Int = 0
        private set

    // Callbacks
    var onPiPClosed: (() -> Unit)? = null
    var onPiPRestoreUI: (() -> Unit)? = null
    var onPlayPauseFromPiP: ((Boolean) -> Unit)? = null
    var onRestartFromPiP: (() -> Unit)? = null

    private var activityRef: WeakReference<Activity>? = null
    private var isConfigured = false
    private var controlReceiver: BroadcastReceiver? = null

    /**
     * Check if PiP is supported on this device
     */
    fun checkPiPSupport(context: Context): Boolean {
        isPiPPossible = context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        return isPiPPossible
    }

    /**
     * The remote kill switch. Nothing offers the overlay, and the auto-enter on
     * leaving the app stays quiet too.
     */
    fun disable() {
        isPiPPossible = false
        isConfigured = false
        applyParams()
    }

    /** The activity the overlay shrinks, held weakly. */
    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
        registerControlReceiver(activity)
    }

    fun detach(activity: Activity) {
        controlReceiver?.let {
            runCatching { activity.unregisterReceiver(it) }
            controlReceiver = null
        }
        if (activityRef?.get() === activity) {
            activityRef = null
        }
    }

    /**
     * Configure the manager for a run of the teleprompter.
     */
    fun configure(settings: TeleprompterSettings, timerDuration: Int) {
        this.settings = settings
        this.timerDuration = timerDuration
        this.elapsedTime = 0.0
        this.isConfigured = true
        applyParams()
    }

    /**
     * Update current state from the teleprompter
     */
    fun updateState(
        elapsedTime: Double,
        isPlaying: Boolean,
        countdownValue: Int = 0,
        isCountingDown: Boolean = false
    ) {
        val playingChanged = this.isPlaying != isPlaying
        this.elapsedTime = elapsedTime
        this.isPlaying = isPlaying
        this.countdownValue = countdownValue
        this.isCountingDown = isCountingDown

        // The overlay's own play/pause button has to show what the app is doing.
        if (playingChanged && isPiPActive) {
            applyParams()
        }
    }

    /**
     * Build PiP parameters for the activity
     */
    private fun buildPiPParams(activity: Activity): PictureInPictureParams {
        val aspectRatio = when (settings.overlayAspectRatio) {
            OverlayAspectRatio.RATIO_16X9 -> Rational(16, 9)
            OverlayAspectRatio.RATIO_4X3 -> Rational(4, 3)
            OverlayAspectRatio.RATIO_1X1 -> Rational(1, 1)
        }

        return PictureInPictureParams.Builder()
            .setAspectRatio(aspectRatio)
            .setActions(remoteActions(activity))
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Leaving the app during a run opens the overlay, the way
                    // backgrounding does on iOS.
                    setAutoEnterEnabled(isPiPPossible && isConfigured)
                    setSeamlessResizeEnabled(true)
                }
            }
            .build()
    }

    /** Play/pause and restart, as the buttons inside the overlay window. */
    private fun remoteActions(activity: Activity): List<RemoteAction> {
        val playPauseTitle = if (isPlaying) "Pause" else "Play"
        val playPauseIcon = if (isPlaying) R.drawable.ic_pip_pause else R.drawable.ic_pip_play

        return listOf(
            RemoteAction(
                Icon.createWithResource(activity, playPauseIcon),
                playPauseTitle,
                playPauseTitle,
                controlIntent(activity, CONTROL_PLAY_PAUSE, REQUEST_PLAY_PAUSE)
            ),
            RemoteAction(
                Icon.createWithResource(activity, R.drawable.ic_pip_restart),
                "Restart",
                "Restart",
                controlIntent(activity, CONTROL_RESTART, REQUEST_RESTART)
            )
        )
    }

    private fun controlIntent(context: Context, control: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(ACTION_CONTROL)
                .setPackage(context.packageName)
                .putExtra(EXTRA_CONTROL, control),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun registerControlReceiver(activity: Activity) {
        if (controlReceiver != null) return

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.getStringExtra(EXTRA_CONTROL)) {
                    CONTROL_PLAY_PAUSE -> onPlayPauseFromPiP?.invoke(!isPlaying)
                    CONTROL_RESTART -> onRestartFromPiP?.invoke()
                }
            }
        }

        ContextCompat.registerReceiver(
            activity,
            receiver,
            IntentFilter(ACTION_CONTROL),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        controlReceiver = receiver
    }

    /** Push the current parameters at the activity, if there is one to push at. */
    private fun applyParams() {
        val activity = activityRef?.get() ?: return
        runCatching { activity.setPictureInPictureParams(buildPiPParams(activity)) }
    }

    /**
     * Enter PiP mode
     */
    fun enterPiP(): Boolean {
        if (!isPiPPossible || !isConfigured) return false

        val activity = activityRef?.get() ?: return false

        return try {
            activity.enterPictureInPictureMode(buildPiPParams(activity))
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /** Bring the app back out of the overlay. */
    fun stopPiP() {
        val activity = activityRef?.get() ?: return
        // Relaunching the activity on top of itself is what takes an Android
        // window out of picture-in-picture.
        activity.startActivity(
            Intent(activity, activity.javaClass)
                .setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
    }

    /**
     * Called when PiP mode starts
     */
    fun onPiPModeEntered() {
        isPiPActive = true
        applyParams()
    }

    /**
     * Called when PiP mode ends
     */
    fun onPiPModeExited() {
        isPiPActive = false
        onPiPRestoreUI?.invoke()
        onPiPClosed?.invoke()
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        isPiPActive = false
        isConfigured = false
        elapsedTime = 0.0
        isPlaying = false
        scriptDuration = 0.0
        onPiPClosed = null
        onPiPRestoreUI = null
        onPlayPauseFromPiP = null
        onRestartFromPiP = null
        applyParams()
    }
}
