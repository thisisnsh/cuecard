package com.thisisnsh.cuecard.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.models.FontSizePreset
import com.thisisnsh.cuecard.android.models.OverlayAspectRatio
import com.thisisnsh.cuecard.android.models.TeleprompterSettings
import com.thisisnsh.cuecard.android.models.ThemePreference
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.ui.theme.AppColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    authService: AuthenticationService,
    settingsService: SettingsService,
    onDismiss: () -> Unit
) {
    val currentUser by authService.currentUser.collectAsState()
    val settings by settingsService.settings.collectAsState()
    val scope = rememberCoroutineScope()
    val isDark = isSystemInDarkTheme()
    val scrollState = rememberScrollState()

    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var isDeletingAccount by remember { mutableStateOf(false) }
    var deleteErrorMessage by remember { mutableStateOf<String?>(null) }

    // Log screen view
    LaunchedEffect(Unit) {
        Firebase.analytics.logEvent("screen_view") {
            param("screen_name", "settings")
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.background(isDark))
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // Top App Bar
            TopAppBar(
                title = {
                    Text(
                        text = "Settings",
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                },
                actions = {
                    TextButton(onClick = onDismiss) {
                        Text(
                            text = "Done",
                            color = AppColors.green(isDark),
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.background(isDark)
                )
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(horizontal = 16.dp)
            ) {
                // User Profile Section
                currentUser?.let { user ->
                    UserProfileSection(user = user, isDark = isDark)
                    Spacer(modifier = Modifier.height(24.dp))
                }

                // Countdown Section
                SettingsSection(title = "Countdown", isDark = isDark) {
                    CountdownSlider(
                        value = settings.countdownSeconds,
                        onValueChange = { newValue ->
                            scope.launch {
                                settingsService.updateCountdownSeconds(newValue)
                            }
                        },
                        isDark = isDark
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Teleprompter Section
                SettingsSection(title = "Teleprompter", isDark = isDark) {
                    // Highlight Words Toggle
                    SettingsRow(
                        title = "Highlight Words",
                        isDark = isDark
                    ) {
                        Switch(
                            checked = settings.autoScroll,
                            onCheckedChange = { enabled ->
                                scope.launch {
                                    settingsService.updateAutoScroll(enabled)
                                }
                            },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = AppColors.green(isDark),
                                checkedTrackColor = AppColors.green(isDark).copy(alpha = 0.5f)
                            )
                        )
                    }

                    // Highlight Speed (only when auto scroll is enabled)
                    if (settings.autoScroll) {
                        Spacer(modifier = Modifier.height(16.dp))
                        WpmSlider(
                            value = settings.wordsPerMinute,
                            onValueChange = { newValue ->
                                scope.launch {
                                    settingsService.updateWordsPerMinute(newValue)
                                }
                            },
                            isDark = isDark
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Text Size Section
                SettingsSection(title = "Text Size", isDark = isDark) {
                    // App Text Size
                    Column {
                        Text(
                            text = "App Text Size",
                            fontSize = 14.sp,
                            color = AppColors.textPrimary(isDark)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        FontSizeSegmentedButton(
                            selected = settings.fontSizePreset,
                            onSelectionChange = { preset ->
                                scope.launch {
                                    settingsService.updateFontSizePreset(preset)
                                }
                            },
                            isDark = isDark
                        )
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Overlay Text Size
                    Column {
                        Text(
                            text = "Overlay Text Size",
                            fontSize = 14.sp,
                            color = AppColors.textPrimary(isDark)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        FontSizeSegmentedButton(
                            selected = settings.pipFontSizePreset,
                            onSelectionChange = { preset ->
                                scope.launch {
                                    settingsService.updatePipFontSizePreset(preset)
                                }
                            },
                            isDark = isDark
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Overlay Section
                SettingsSection(title = "Overlay", isDark = isDark) {
                    Column {
                        Text(
                            text = "Overlay Dimension Ratio",
                            fontSize = 14.sp,
                            color = AppColors.textPrimary(isDark)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        AspectRatioSegmentedButton(
                            selected = settings.overlayAspectRatio,
                            onSelectionChange = { ratio ->
                                scope.launch {
                                    settingsService.updateOverlayAspectRatio(ratio)
                                }
                            },
                            isDark = isDark
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Appearance Section
                SettingsSection(title = "Appearance", isDark = isDark) {
                    Column {
                        Text(
                            text = "Theme",
                            fontSize = 14.sp,
                            color = AppColors.textPrimary(isDark)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        ThemeSegmentedButton(
                            selected = settings.themePreference,
                            onSelectionChange = { theme ->
                                scope.launch {
                                    settingsService.updateThemePreference(theme)
                                }
                            },
                            isDark = isDark
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Reset Section
                SettingsSection(title = "", isDark = isDark) {
                    TextButton(
                        onClick = {
                            scope.launch {
                                settingsService.resetSettings()
                            }
                        }
                    ) {
                        Text(
                            text = "Reset to Defaults",
                            color = AppColors.textPrimary(isDark)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Sign Out Section
                SettingsSection(title = "", isDark = isDark) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                Firebase.analytics.logEvent("button_click") {
                                    param("button_name", "sign_out")
                                    param("screen", "settings")
                                }
                                authService.signOut()
                                onDismiss()
                            }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Logout,
                            contentDescription = "Sign Out",
                            tint = AppColors.red(isDark),
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Sign Out",
                            color = AppColors.red(isDark),
                            fontSize = 16.sp
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Delete Account Section
                SettingsSection(title = "", isDark = isDark) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !isDeletingAccount) {
                                Firebase.analytics.logEvent("button_click") {
                                    param("button_name", "delete_account")
                                    param("screen", "settings")
                                }
                                showDeleteConfirmation = true
                            }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (isDeletingAccount) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = AppColors.red(isDark),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Delete,
                                contentDescription = "Delete Account",
                                tint = AppColors.red(isDark),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Delete Account",
                            color = AppColors.red(isDark),
                            fontSize = 16.sp
                        )
                    }
                    Text(
                        text = "This will permanently delete your account and all data stored on this device.",
                        fontSize = 12.sp,
                        color = AppColors.textSecondary(isDark),
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }

                Spacer(modifier = Modifier.height(48.dp))
            }
        }
    }

    // Delete Confirmation Dialog
    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = {
                Text(
                    text = "Delete Account",
                    color = AppColors.textPrimary(isDark)
                )
            },
            text = {
                Text(
                    text = "Are you sure you want to delete your account? This action cannot be undone.",
                    color = AppColors.textSecondary(isDark)
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirmation = false
                        isDeletingAccount = true
                        scope.launch {
                            val result = authService.deleteAccount()
                            isDeletingAccount = false
                            result.fold(
                                onSuccess = {
                                    onDismiss()
                                },
                                onFailure = { error ->
                                    deleteErrorMessage = error.message ?: "An error occurred"
                                }
                            )
                        }
                    }
                ) {
                    Text(
                        text = "Delete",
                        color = AppColors.red(isDark)
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
                    Text(
                        text = "Cancel",
                        color = AppColors.textSecondary(isDark)
                    )
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }

    // Error Dialog
    if (deleteErrorMessage != null) {
        AlertDialog(
            onDismissRequest = { deleteErrorMessage = null },
            title = {
                Text(
                    text = "Error",
                    color = AppColors.textPrimary(isDark)
                )
            },
            text = {
                Text(
                    text = deleteErrorMessage ?: "An error occurred",
                    color = AppColors.textSecondary(isDark)
                )
            },
            confirmButton = {
                TextButton(onClick = { deleteErrorMessage = null }) {
                    Text(
                        text = "OK",
                        color = AppColors.green(isDark)
                    )
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

@Composable
private fun UserProfileSection(
    user: FirebaseUser,
    isDark: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        val displayName = getDisplayNameForUser(user)

        Text(
            text = displayName,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary(isDark)
        )
        Spacer(modifier = Modifier.height(4.dp))

        user.email?.let { email ->
            Text(
                text = email,
                fontSize = 14.sp,
                fontWeight = FontWeight.Normal,
                color = AppColors.textSecondary(isDark)
            )
        }
    }
}

private fun getDisplayNameForUser(user: FirebaseUser): String {
    val displayName = user.displayName
    if (!displayName.isNullOrEmpty()) {
        return displayName
    }
    val email = user.email
    if (email != null && email.contains("privaterelay.appleid.com")) {
        return "Private User"
    }
    return "User"
}

@Composable
private fun SettingsSection(
    title: String,
    isDark: Boolean,
    content: @Composable () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth()
    ) {
        if (title.isNotEmpty()) {
            Text(
                text = title.uppercase(),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textSecondary(isDark),
                letterSpacing = 1.sp
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(
                    if (isDark) AppColors.Dark.textSecondary.copy(alpha = 0.1f)
                    else AppColors.Light.textSecondary.copy(alpha = 0.1f)
                )
                .padding(16.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun SettingsRow(
    title: String,
    isDark: Boolean,
    trailing: @Composable () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            fontSize = 16.sp,
            color = AppColors.textPrimary(isDark)
        )
        trailing()
    }
}

@Composable
private fun CountdownSlider(
    value: Int,
    onValueChange: (Int) -> Unit,
    isDark: Boolean
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Start Delay",
                fontSize = 16.sp,
                color = AppColors.textPrimary(isDark)
            )
            Text(
                text = "$value seconds",
                fontSize = 16.sp,
                color = AppColors.textSecondary(isDark)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Slider(
            value = value.toFloat(),
            onValueChange = { onValueChange(it.toInt()) },
            valueRange = 0f..10f,
            steps = 9,
            colors = SliderDefaults.colors(
                thumbColor = AppColors.green(isDark),
                activeTrackColor = AppColors.green(isDark)
            )
        )
    }
}

@Composable
private fun WpmSlider(
    value: Int,
    onValueChange: (Int) -> Unit,
    isDark: Boolean
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Highlight Speed",
                fontSize = 16.sp,
                color = AppColors.textPrimary(isDark)
            )
            Text(
                text = "$value WPM",
                fontSize = 16.sp,
                color = AppColors.textSecondary(isDark)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Slider(
            value = value.toFloat(),
            onValueChange = { onValueChange((it / 10).toInt() * 10) },
            valueRange = TeleprompterSettings.WPM_RANGE.first.toFloat()..TeleprompterSettings.WPM_RANGE.last.toFloat(),
            colors = SliderDefaults.colors(
                thumbColor = AppColors.green(isDark),
                activeTrackColor = AppColors.green(isDark)
            )
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FontSizeSegmentedButton(
    selected: FontSizePreset,
    onSelectionChange: (FontSizePreset) -> Unit,
    isDark: Boolean
) {
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier.fillMaxWidth()
    ) {
        FontSizePreset.entries.forEachIndexed { index, preset ->
            SegmentedButton(
                selected = selected == preset,
                onClick = { onSelectionChange(preset) },
                shape = SegmentedButtonDefaults.itemShape(
                    index = index,
                    count = FontSizePreset.entries.size
                ),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = AppColors.green(isDark).copy(alpha = 0.2f),
                    activeContentColor = AppColors.green(isDark),
                    inactiveContainerColor = AppColors.textSecondary(isDark).copy(alpha = 0.1f),
                    inactiveContentColor = AppColors.textPrimary(isDark)
                )
            ) {
                Text(text = preset.displayName)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AspectRatioSegmentedButton(
    selected: OverlayAspectRatio,
    onSelectionChange: (OverlayAspectRatio) -> Unit,
    isDark: Boolean
) {
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier.fillMaxWidth()
    ) {
        OverlayAspectRatio.entries.forEachIndexed { index, ratio ->
            SegmentedButton(
                selected = selected == ratio,
                onClick = { onSelectionChange(ratio) },
                shape = SegmentedButtonDefaults.itemShape(
                    index = index,
                    count = OverlayAspectRatio.entries.size
                ),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = AppColors.green(isDark).copy(alpha = 0.2f),
                    activeContentColor = AppColors.green(isDark),
                    inactiveContainerColor = AppColors.textSecondary(isDark).copy(alpha = 0.1f),
                    inactiveContentColor = AppColors.textPrimary(isDark)
                )
            ) {
                Text(text = ratio.displayName)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThemeSegmentedButton(
    selected: ThemePreference,
    onSelectionChange: (ThemePreference) -> Unit,
    isDark: Boolean
) {
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier.fillMaxWidth()
    ) {
        ThemePreference.entries.forEachIndexed { index, theme ->
            SegmentedButton(
                selected = selected == theme,
                onClick = { onSelectionChange(theme) },
                shape = SegmentedButtonDefaults.itemShape(
                    index = index,
                    count = ThemePreference.entries.size
                ),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = AppColors.green(isDark).copy(alpha = 0.2f),
                    activeContentColor = AppColors.green(isDark),
                    inactiveContainerColor = AppColors.textSecondary(isDark).copy(alpha = 0.1f),
                    inactiveContentColor = AppColors.textPrimary(isDark)
                )
            ) {
                Text(text = theme.displayName)
            }
        }
    }
}
