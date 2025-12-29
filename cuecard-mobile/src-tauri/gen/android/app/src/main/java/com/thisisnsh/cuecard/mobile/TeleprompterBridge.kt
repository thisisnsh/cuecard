package com.thisisnsh.cuecard.mobile

import android.app.Activity
import android.os.Build

/**
 * JNI Bridge for Teleprompter PiP
 * This class is called from Rust via JNI to control the teleprompter
 */
object TeleprompterBridge {

    private var activityRef: Activity? = null

    /**
     * Initialize the bridge with the main activity
     * Call this from MainActivity.onCreate()
     */
    @JvmStatic
    fun initialize(activity: Activity) {
        activityRef = activity
    }

    /**
     * Start the teleprompter PiP
     * Called from Rust via JNI
     */
    @JvmStatic
    fun startTeleprompter(content: String, fontSize: Int, defaultSpeed: Float, opacity: Float) {
        activityRef?.let { activity ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.runOnUiThread {
                    TeleprompterPiPManager.getInstance(activity)
                        .startTeleprompter(content, fontSize.toFloat(), defaultSpeed, opacity)
                }
            }
        }
    }

    /**
     * Pause the teleprompter
     * Called from Rust via JNI
     */
    @JvmStatic
    fun pauseTeleprompter() {
        activityRef?.let { activity ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.runOnUiThread {
                    TeleprompterPiPManager.getInstance(activity).pause()
                }
            }
        }
    }

    /**
     * Resume the teleprompter
     * Called from Rust via JNI
     */
    @JvmStatic
    fun resumeTeleprompter() {
        activityRef?.let { activity ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.runOnUiThread {
                    TeleprompterPiPManager.getInstance(activity).resume()
                }
            }
        }
    }

    /**
     * Stop the teleprompter
     * Called from Rust via JNI
     */
    @JvmStatic
    fun stopTeleprompter() {
        activityRef?.let { activity ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.runOnUiThread {
                    TeleprompterPiPManager.getInstance(activity).stop()
                }
            }
        }
    }

    /**
     * Check if PiP is supported on this device
     * Called from Rust via JNI
     */
    @JvmStatic
    fun isPiPSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    }
}
