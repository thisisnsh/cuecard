package com.thisisnsh.cuecard.android

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TeleprompterPiPManager
import com.thisisnsh.cuecard.android.views.ContentView

class MainActivity : ComponentActivity() {

    private val pipManager = TeleprompterPiPManager.shared

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        pipManager.checkPiPSupport(this)
        pipManager.attach(this)

        setContent {
            val context = LocalContext.current
            val authService = remember { AuthenticationService(context) }
            val settingsService = remember { SettingsService.getInstance(context) }
            val notifications = remember { RemoteNotificationService.getInstance(context) }
            val settings by settingsService.settings.collectAsState()

            LaunchedEffect(Unit) {
                settingsService.loadSettings()
            }

            CueCardTheme(themePreference = settings.themePreference) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = AppColors.background(LocalIsDarkTheme.current)
                ) {
                    ContentView(
                        authService = authService,
                        settingsService = settingsService,
                        notifications = notifications
                    )
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Below API 31 there is no auto-enter, so leaving the app during a run
        // opens the overlay from here instead.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            pipManager.isPiPPossible &&
            pipManager.isPlaying
        ) {
            pipManager.enterPiP()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)

        if (isInPictureInPictureMode) {
            pipManager.onPiPModeEntered()
        } else {
            pipManager.onPiPModeExited()
        }
    }

    override fun onDestroy() {
        pipManager.detach(this)
        super.onDestroy()
    }
}
