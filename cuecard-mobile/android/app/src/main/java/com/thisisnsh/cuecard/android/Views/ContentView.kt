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
import com.thisisnsh.cuecard.android.models.AppVersion
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.RemoteConfigService
import com.thisisnsh.cuecard.android.services.SettingsService
import kotlinx.coroutines.launch

/**
 * The three-way gate the app opens on: an unusable build, a signed-in reader, or
 * the way in.
 */
@Composable
fun ContentView(
    authService: AuthenticationService,
    settingsService: SettingsService,
    remoteConfig: RemoteConfigService
) {
    val isAuthenticated by authService.isAuthenticated.collectAsState()
    val config by remoteConfig.config.collectAsState()
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(Unit) {
        remoteConfig.refresh()
    }

    // Coming back to the app is the natural moment to pick up a new notice. The
    // service throttles itself, so this is cheap.
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                scope.launch { remoteConfig.refresh() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val requiresUpdate = AppVersion.compare(AppVersion.current, config.flags.minSupportedVersion) < 0

    when {
        requiresUpdate -> UpdateRequiredScreen(remoteConfig = remoteConfig)
        isAuthenticated -> HomeView(
            authService = authService,
            settingsService = settingsService,
            remoteConfig = remoteConfig
        )
        else -> LoginView(authService = authService, remoteConfig = remoteConfig)
    }
}
