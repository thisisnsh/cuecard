package com.thisisnsh.cuecard.android.views

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingsService
import kotlinx.coroutines.launch

/** The screen the app opens on. */
@Composable
fun ContentView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService
) {
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(Unit) {
        notifications.refresh()
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

    HomeView(
        settingsService = settingsService,
        notifications = notifications
    )
}
