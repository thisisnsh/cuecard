package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.crashlytics.ktx.crashlytics
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.BuildConfig
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.RemoteNotification
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.FontSizePreset
import com.thisisnsh.cuecard.android.services.OverlayAspectRatio
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import com.thisisnsh.cuecard.android.services.ThemePreference
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsView(
    authService: AuthenticationService,
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val screenFocusManager = LocalFocusManager.current

    val settings by settingsService.settings.collectAsState()
    val user by authService.currentUser.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()

    var showingDeleteConfirmation by remember { mutableStateOf(false) }
    var isDeletingAccount by remember { mutableStateOf(false) }
    var deleteErrorMessage by remember { mutableStateOf<String?>(null) }

    val settingsNotification = remember(payload, dismissedIds) {
        notifications.notification(RemoteNotification.Surface.SETTINGS_ROW)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("settings")
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Settings",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                },
                actions = {
                    Text(
                        text = "Done",
                        fontSize = 17.sp,
                        color = AppColors.blue(isDark),
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("done", "settings")
                                onDismiss()
                            }
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.background(isDark)
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                // A tap that no control claimed puts the keyboard away, so a
                // number being typed has a way out anywhere on the screen.
                .pointerInput(Unit) {
                    detectTapGestures { screenFocusManager.clearFocus() }
                }
        ) {
            // A notice from the worker, if there's one meant for Settings.
            settingsNotification?.let { notification ->
                SettingsSection(isDark = isDark) {
                    NotificationRow(
                        notification = notification,
                        notifications = notifications,
                        modifier = Modifier.padding(horizontal = 20.dp)
                    )
                }
            }

            user?.let { firebaseUser ->
                SettingsSection(isDark = isDark) {
                    Column(
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = displayNameForUser(
                                firebaseUser.displayName,
                                firebaseUser.email
                            ),
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )

                        firebaseUser.email?.let { email ->
                            Text(
                                text = email,
                                fontSize = 15.sp,
                                color = AppColors.textSecondary(isDark)
                            )
                        }
                    }
                }
            }

            SettingsSection(isDark = isDark) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("rate_app", "settings")
                            openLink(context, AppLinks.PLAY_STORE)
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Review on Google Play",
                        fontSize = 17.sp,
                        color = AppColors.textPrimary(isDark)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Icon(
                        imageVector = Icons.Filled.ArrowOutward,
                        contentDescription = null,
                        tint = AppColors.textSecondary(isDark),
                        modifier = Modifier.size(12.dp)
                    )
                }
            }

            // MARK: - Teleprompter

            SettingsSection(title = "Teleprompter", isDark = isDark) {
                NumberRow(
                    label = "Start Delay",
                    unit = "seconds",
                    value = settings.countdownSeconds,
                    range = TeleprompterSettings.COUNTDOWN_RANGE,
                    isDark = isDark,
                    onCommit = { scope.launch { settingsService.updateCountdownSeconds(it) } }
                )

                NumberRow(
                    label = "Scroll Speed",
                    unit = "lines/min",
                    value = settings.linesPerMinute,
                    range = TeleprompterSettings.LPM_RANGE,
                    isDark = isDark,
                    onCommit = { scope.launch { settingsService.updateLinesPerMinute(it) } }
                )

                Column(
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Cue Color",
                        fontSize = 17.sp,
                        color = AppColors.textPrimary(isDark)
                    )

                    Row(
                        modifier = Modifier.padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        CueColor.entries.forEach { option ->
                            val isSelected = option == settings.cueColor
                            Box(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clickableWithoutRipple {
                                        scope.launch { settingsService.updateCueColor(option) }
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(36.dp)
                                        .border(
                                            width = if (isSelected) 2.dp else 0.dp,
                                            color = if (isSelected) {
                                                AppColors.textPrimary(isDark)
                                            } else {
                                                androidx.compose.ui.graphics.Color.Transparent
                                            },
                                            shape = CircleShape
                                        )
                                )
                                Box(
                                    modifier = Modifier
                                        .size(28.dp)
                                        .clip(CircleShape)
                                        .background(option.color(isDark)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (isSelected) {
                                        Icon(
                                            imageVector = Icons.Filled.Check,
                                            contentDescription = option.displayName,
                                            tint = AppColors.background(isDark),
                                            modifier = Modifier.size(12.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Text(
                        text = "Every cue is shown in this color.",
                        fontSize = 13.sp,
                        color = AppColors.textSecondary(isDark)
                    )
                }
            }

            // MARK: - Prompters

            SettingsSection(title = "In-App Prompter", isDark = isDark) {
                SegmentedRow(
                    label = "Text Size",
                    options = FontSizePreset.entries.map { it.displayName },
                    selectedIndex = FontSizePreset.entries.indexOf(settings.fontSizePreset),
                    isDark = isDark,
                    onSelect = {
                        scope.launch {
                            settingsService.updateFontSizePreset(FontSizePreset.entries[it])
                        }
                    }
                )
            }

            SettingsSection(title = "Floating Prompter", isDark = isDark) {
                SegmentedRow(
                    label = "Text Size",
                    options = FontSizePreset.entries.map { it.displayName },
                    selectedIndex = FontSizePreset.entries.indexOf(settings.pipFontSizePreset),
                    isDark = isDark,
                    onSelect = {
                        scope.launch {
                            settingsService.updatePipFontSizePreset(FontSizePreset.entries[it])
                        }
                    }
                )

                SegmentedRow(
                    label = "Dimension Ratio",
                    options = OverlayAspectRatio.entries.map { it.displayName },
                    selectedIndex = OverlayAspectRatio.entries.indexOf(settings.overlayAspectRatio),
                    isDark = isDark,
                    onSelect = {
                        scope.launch {
                            settingsService.updateOverlayAspectRatio(OverlayAspectRatio.entries[it])
                        }
                    }
                )
            }

            SettingsSection(title = "Appearance", isDark = isDark) {
                SegmentedRow(
                    label = "Theme",
                    options = ThemePreference.entries.map { it.displayName },
                    selectedIndex = ThemePreference.entries.indexOf(settings.themePreference),
                    isDark = isDark,
                    onSelect = {
                        scope.launch {
                            settingsService.updateThemePreference(ThemePreference.entries[it])
                        }
                    }
                )
            }

            SettingsSection(isDark = isDark) {
                Text(
                    text = "Reset to Defaults",
                    fontSize = 17.sp,
                    color = AppColors.blue(isDark),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("reset_to_defaults", "settings")
                            scope.launch { settingsService.resetSettings() }
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp)
                )
            }

            if (BuildConfig.DIAGNOSTICS) {
                SettingsSection(
                    isDark = isDark,
                    footer = "This intentionally crashes the app to verify Crashlytics reporting."
                ) {
                    Text(
                        text = "Trigger Test Crash",
                        fontSize = 17.sp,
                        color = AppColors.red(isDark),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("test_crash", "settings")
                                Firebase.crashlytics.log("Manually triggered test crash")
                                throw RuntimeException("Crashlytics test crash")
                            }
                            .padding(horizontal = 20.dp, vertical = 12.dp)
                    )
                }
            }

            SettingsSection(isDark = isDark) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("sign_out", "settings")
                            authService.signOut()
                            onDismiss()
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Logout,
                        contentDescription = null,
                        tint = AppColors.red(isDark),
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "Sign Out",
                        fontSize = 17.sp,
                        color = AppColors.red(isDark)
                    )
                }
            }

            SettingsSection(
                isDark = isDark,
                footer = "This will permanently delete your account and all data stored on this device."
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            if (isDeletingAccount) return@clickableWithoutRipple
                            AnalyticsEvents.logButtonClick("delete_account", "settings")
                            showingDeleteConfirmation = true
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    if (isDeletingAccount) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = AppColors.red(isDark),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = null,
                            tint = AppColors.red(isDark),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                    Text(
                        text = "Delete Account",
                        fontSize = 17.sp,
                        color = AppColors.red(isDark)
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    if (showingDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showingDeleteConfirmation = false },
            title = { Text("Delete Account") },
            text = { Text("Are you sure you want to delete your account? This action cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showingDeleteConfirmation = false
                    isDeletingAccount = true
                    scope.launch {
                        val result = authService.deleteAccount()
                        isDeletingAccount = false
                        result.fold(
                            onSuccess = { onDismiss() },
                            onFailure = { deleteErrorMessage = it.message ?: "An error occurred" }
                        )
                    }
                }) {
                    Text("Delete", color = AppColors.red(isDark))
                }
            },
            dismissButton = {
                TextButton(onClick = { showingDeleteConfirmation = false }) {
                    Text("Cancel", color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }

    deleteErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { deleteErrorMessage = null },
            title = { Text("Error") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { deleteErrorMessage = null }) {
                    Text("OK", color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

private fun displayNameForUser(displayName: String?, email: String?): String {
    if (!displayName.isNullOrEmpty()) return displayName
    if (email != null && email.contains("privaterelay.appleid.com")) return "Private User"
    return "User"
}

/** One grouped section of the settings list, with its heading and footnote. */
@Composable
private fun SettingsSection(
    isDark: Boolean,
    title: String? = null,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        title?.let {
            Text(
                text = it,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textSecondary(isDark),
                modifier = Modifier.padding(start = 20.dp, top = 24.dp, bottom = 8.dp)
            )
        }

        if (title == null) {
            Spacer(modifier = Modifier.height(16.dp))
        }

        content()

        footer?.let {
            Text(
                text = it,
                fontSize = 12.sp,
                color = AppColors.textSecondary(isDark),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
            )
        }

        HorizontalDivider(
            color = AppColors.textSecondary(isDark).copy(alpha = 0.15f),
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

/**
 * A labelled row holding a number the user types, rather than drags. The field
 * keeps whatever is being typed and only becomes a setting once editing stops,
 * so a half-typed figure is never held to the range.
 */
@Composable
private fun NumberRow(
    label: String,
    unit: String,
    value: Int,
    range: IntRange,
    isDark: Boolean,
    onCommit: (Int) -> Unit
) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    var isFocused by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }

    fun commit() {
        val typed = text.filter { it.isDigit() }.toIntOrNull()
        val committed = typed?.coerceIn(range.first, range.last) ?: value
        text = committed.toString()
        if (committed != value) onCommit(committed)
    }

    Row(
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )
        Spacer(modifier = Modifier.weight(1f))

        // The number and its unit share one filled box, and the whole box is
        // the target: tapping the unit starts editing, same as the digits.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.textSecondary(isDark).copy(alpha = 0.12f))
                .clickableWithoutRipple { focusRequester.requestFocus() }
                .padding(horizontal = 14.dp, vertical = 8.dp)
        ) {
            BasicTextField(
                value = text,
                onValueChange = { entered -> text = entered.filter { it.isDigit() }.take(3) },
                singleLine = true,
                textStyle = TextStyle(
                    fontSize = 15.sp,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.End,
                    color = AppColors.textPrimary(isDark)
                ),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Done
                ),
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                modifier = Modifier
                    .width(34.dp)
                    .focusRequester(focusRequester)
                    .onFocusChanged { state ->
                        if (isFocused && !state.isFocused) commit()
                        isFocused = state.isFocused
                    }
            )
            Spacer(modifier = Modifier.width(5.dp))
            Text(
                text = unit,
                fontSize = 15.sp,
                color = AppColors.textSecondary(isDark)
            )
        }
    }
}

/** A labelled segmented control, the parallel to SwiftUI's segmented picker. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SegmentedRow(
    label: String,
    options: List<String>,
    selectedIndex: Int,
    isDark: Boolean,
    onSelect: (Int) -> Unit
) {
    Column(
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = label,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )

        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    selected = index == selectedIndex,
                    onClick = { onSelect(index) },
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = AppColors.textPrimary(isDark).copy(alpha = 0.12f),
                        activeContentColor = AppColors.textPrimary(isDark),
                        inactiveContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                        inactiveContentColor = AppColors.textSecondary(isDark),
                        activeBorderColor = AppColors.textSecondary(isDark).copy(alpha = 0.3f),
                        inactiveBorderColor = AppColors.textSecondary(isDark).copy(alpha = 0.3f)
                    )
                ) {
                    Text(text = option, fontSize = 14.sp)
                }
            }
        }
    }
}
