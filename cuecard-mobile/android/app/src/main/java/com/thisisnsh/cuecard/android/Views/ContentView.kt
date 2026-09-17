package com.thisisnsh.cuecard.android.views

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.thisisnsh.cuecard.android.services.OnboardingService
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.WhatsNewService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The screen the app opens on: the welcome, on a fresh install, or the script. */
@Composable
fun ContentView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    onboarding: OnboardingService,
    whatsNew: WhatsNewService
) {
    val hasSeenWelcome by onboarding.hasSeenWelcome.collectAsState()
    val showingWhatsNew by whatsNew.isPresented.collectAsState()
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(Unit) {
        notifications.refresh()
    }

    // Once the welcome flag is known, float this version's features over the
    // first screen, after letting it settle.
    LaunchedEffect(hasSeenWelcome) {
        val seen = hasSeenWelcome ?: return@LaunchedEffect
        delay(500)
        whatsNew.presentIfUnseen(hasSeenWelcome = seen)
    }

    // Coming back to the app is the natural moment to pick up a new notice. The
    // service throttles itself, so this is cheap.
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                scope.launch { notifications.refresh() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    when (hasSeenWelcome) {
        // Still reading the flag. The window is already painted in the app's
        // background, so waiting shows nothing rather than the wrong screen.
        null -> Unit

        false -> WelcomeView(
            onGetStarted = {
                scope.launch {
                    onboarding.markWelcomeSeen()
                    settingsService.addSampleTextIfEmpty()
                }
            }
        )

        true -> HomeView(
            settingsService = settingsService,
            notifications = notifications
        )
    }

    val release = whatsNew.release
    if (showingWhatsNew && release != null) {
        WhatsNewDialog(release = release, version = whatsNew.version, onDismiss = whatsNew::dismiss)
    }
}
