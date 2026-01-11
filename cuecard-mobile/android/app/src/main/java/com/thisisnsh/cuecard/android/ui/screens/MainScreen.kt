package com.thisisnsh.cuecard.android.ui.screens

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.SettingsService

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Home : Screen("home")
    data object Settings : Screen("settings")
    data object Teleprompter : Screen("teleprompter")
    data object SavedNotes : Screen("saved_notes")
}

@Composable
fun MainScreen() {
    val context = LocalContext.current
    val authService = remember { AuthenticationService(context) }
    val settingsService = remember { SettingsService.getInstance(context) }
    val currentUser by authService.currentUser.collectAsState()
    val notes by settingsService.notes.collectAsState()
    val settings by settingsService.settings.collectAsState()

    val navController = rememberNavController()

    // Navigate based on auth state
    LaunchedEffect(currentUser) {
        if (currentUser == null) {
            navController.navigate(Screen.Login.route) {
                popUpTo(0) { inclusive = true }
            }
        } else {
            // Only navigate to home if we're on login
            if (navController.currentDestination?.route == Screen.Login.route) {
                navController.navigate(Screen.Home.route) {
                    popUpTo(Screen.Login.route) { inclusive = true }
                }
            }
        }
    }

    // Load settings on startup
    LaunchedEffect(Unit) {
        settingsService.loadSettings()
    }

    val startDestination = if (currentUser != null) Screen.Home.route else Screen.Login.route

    NavHost(
        navController = navController,
        startDestination = startDestination,
        enterTransition = {
            fadeIn(animationSpec = tween(300))
        },
        exitTransition = {
            fadeOut(animationSpec = tween(300))
        }
    ) {
        composable(Screen.Login.route) {
            LoginScreen(
                authService = authService
            )
        }

        composable(Screen.Home.route) {
            HomeScreen(
                settingsService = settingsService,
                onNavigateToSettings = {
                    navController.navigate(Screen.Settings.route)
                },
                onNavigateToTeleprompter = {
                    navController.navigate(Screen.Teleprompter.route)
                },
                onNavigateToSavedNotes = {
                    navController.navigate(Screen.SavedNotes.route)
                }
            )
        }

        composable(
            route = Screen.Settings.route,
            enterTransition = {
                slideIntoContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Up,
                    animationSpec = tween(300)
                )
            },
            exitTransition = {
                slideOutOfContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Down,
                    animationSpec = tween(300)
                )
            }
        ) {
            SettingsScreen(
                authService = authService,
                settingsService = settingsService,
                onDismiss = {
                    navController.popBackStack()
                }
            )
        }

        composable(
            route = Screen.SavedNotes.route,
            enterTransition = {
                slideIntoContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Up,
                    animationSpec = tween(300)
                )
            },
            exitTransition = {
                slideOutOfContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Down,
                    animationSpec = tween(300)
                )
            }
        ) {
            SavedNotesScreen(
                settingsService = settingsService,
                onDismiss = {
                    navController.popBackStack()
                },
                onNoteSelected = {
                    navController.popBackStack()
                }
            )
        }

        composable(
            route = Screen.Teleprompter.route,
            enterTransition = {
                slideIntoContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Up,
                    animationSpec = tween(300)
                )
            },
            exitTransition = {
                slideOutOfContainer(
                    towards = AnimatedContentTransitionScope.SlideDirection.Down,
                    animationSpec = tween(300)
                )
            }
        ) {
            val content = remember(notes) { TeleprompterParser.parseNotes(notes) }
            TeleprompterScreen(
                content = content,
                settings = settings,
                onDismiss = {
                    navController.popBackStack()
                }
            )
        }
    }
}
