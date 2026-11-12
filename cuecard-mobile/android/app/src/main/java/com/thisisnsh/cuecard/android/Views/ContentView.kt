package com.thisisnsh.cuecard.android.views

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.edit
import com.thisisnsh.cuecard.android.services.TakeCounts
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

/** The screen the app opens on: the welcome, on a fresh install, or the library. */
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
                // Notes in the notes folder may have been edited elsewhere.
                scope.launch { settingsService.syncNotesFolder() }
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

        true -> LibraryAndEditor(settingsService, notifications)
    }

    val release = whatsNew.release
    if (showingWhatsNew && release != null) {
        WhatsNewDialog(release = release, version = whatsNew.version, onDismiss = whatsNew::dismiss)
    }
}

/** Where the library's state is kept, as it changes. */
private const val LIBRARY_PREFS = "library"

/**
 * Whether the editor was open over the library. Kept in preferences rather than
 * saved state, which is let go of when the app is closed, so the app opens
 * again on the screen it was left on.
 */
private const val EDITOR_OPEN_KEY = "library_path_editor"

/**
 * The library, with the editor over it on one script. It opens again on the
 * library or the editor it was left on, even after the app was closed; left
 * reading, it opens on the editor.
 */
@Composable
private fun LibraryAndEditor(settingsService: SettingsService, notifications: RemoteNotificationService) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(LIBRARY_PREFS, Context.MODE_PRIVATE) }
    var showingEditor by remember { mutableStateOf(prefs.getBoolean(EDITOR_OPEN_KEY, false)) }
    val takeCounts = remember { TakeCounts(context) }
    DisposableEffect(takeCounts) { onDispose { takeCounts.close() } }

    fun setEditor(open: Boolean) {
        showingEditor = open
        prefs.edit { putBoolean(EDITOR_OPEN_KEY, open) }
        // Back from the editor, there may be new takes or a new note.
        if (!open) takeCounts.reload()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        LibraryView(
            settingsService = settingsService,
            notifications = notifications,
            takeCounts = takeCounts,
            onOpenEditor = { setEditor(true) }
        )

        AnimatedVisibility(
            visible = showingEditor,
            enter = slideInHorizontally(initialOffsetX = { it }) + fadeIn(),
            exit = slideOutHorizontally(targetOffsetX = { it }) + fadeOut()
        ) {
            BackHandler { setEditor(false) }
            HomeView(
                settingsService = settingsService,
                notifications = notifications,
                onBack = { setEditor(false) }
            )
        }
    }
}
