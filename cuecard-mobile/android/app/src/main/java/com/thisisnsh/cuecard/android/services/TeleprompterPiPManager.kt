package com.thisisnsh.cuecard.android.services

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.os.Build
import android.util.Rational
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.thisisnsh.cuecard.android.models.OverlayAspectRatio
import com.thisisnsh.cuecard.android.models.TeleprompterSettings

/**
 * Manager for Picture-in-Picture teleprompter functionality on Android.
 *
 * Note: Android PiP works differently from iOS - it minimizes the entire activity
 * into a small floating window, rather than creating a separate overlay.
 * The PiP window shows the same content as the main activity.
 */
class TeleprompterPiPManager private constructor() {

    companion object {
        val shared = TeleprompterPiPManager()
    }

    // State
    var isPiPActive by mutableStateOf(false)
        private set

    var isPiPPossible by mutableStateOf(false)
        private set

    var isPlaying = false
    var elapsedTime: Double = 0.0
    var currentWordIndex: Int = 0
    var countdownValue: Int = 0
    var isCountingDown: Boolean = false

    // Content properties
    private var text: String = ""
    private var settings: TeleprompterSettings = TeleprompterSettings.DEFAULT
    private var timerDuration: Int = 0
    private var isDarkMode: Boolean = true
    private var totalWords: Int = 0

    // Callbacks
    var onPiPClosed: (() -> Unit)? = null
    var onPiPRestoreUI: (() -> Unit)? = null

    /**
     * Check if PiP is supported on this device
     */
    fun checkPiPSupport(context: Context): Boolean {
        isPiPPossible = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
        return isPiPPossible
    }

    /**
     * Configure the PiP manager with content
     */
    fun configure(
        text: String,
        settings: TeleprompterSettings,
        timerDuration: Int,
        isDarkMode: Boolean,
        totalWords: Int
    ) {
        this.text = text
        this.settings = settings
        this.timerDuration = timerDuration
        this.isDarkMode = isDarkMode
        this.totalWords = totalWords
        this.elapsedTime = 0.0
        this.currentWordIndex = 0
    }

    /**
     * Update current state from TeleprompterScreen
     */
    fun updateState(
        elapsedTime: Double,
        isPlaying: Boolean,
        currentWordIndex: Int = 0,
        countdownValue: Int = 0,
        isCountingDown: Boolean = false
    ) {
        this.elapsedTime = elapsedTime
        this.isPlaying = isPlaying
        this.currentWordIndex = currentWordIndex
        this.countdownValue = countdownValue
        this.isCountingDown = isCountingDown
    }

    /**
     * Build PiP parameters for the activity
     */
    fun buildPiPParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }

        val aspectRatio = when (settings.overlayAspectRatio) {
            OverlayAspectRatio.RATIO_16X9 -> Rational(16, 9)
            OverlayAspectRatio.RATIO_4X3 -> Rational(4, 3)
            OverlayAspectRatio.RATIO_1X1 -> Rational(1, 1)
        }

        return PictureInPictureParams.Builder()
            .setAspectRatio(aspectRatio)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setAutoEnterEnabled(true)
                    setSeamlessResizeEnabled(true)
                }
            }
            .build()
    }

    /**
     * Enter PiP mode
     */
    fun enterPiP(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        if (!checkPiPSupport(activity)) {
            return false
        }

        val params = buildPiPParams() ?: return false

        return try {
            activity.enterPictureInPictureMode(params)
            isPiPActive = true
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * Called when PiP mode starts
     */
    fun onPiPModeEntered() {
        isPiPActive = true
    }

    /**
     * Called when PiP mode ends
     */
    fun onPiPModeExited() {
        isPiPActive = false
        onPiPClosed?.invoke()
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        isPiPActive = false
        text = ""
        elapsedTime = 0.0
        currentWordIndex = 0
        onPiPClosed = null
        onPiPRestoreUI = null
    }
}
