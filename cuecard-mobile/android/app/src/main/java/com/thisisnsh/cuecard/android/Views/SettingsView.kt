package com.thisisnsh.cuecard.android.views

import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
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
import com.thisisnsh.cuecard.android.services.OverlayAspectRatio
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingPreset
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import com.thisisnsh.cuecard.android.services.ThemePreference
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val screenFocusManager = LocalFocusManager.current

    val settings by settingsService.settings.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()

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

            SettingsSection(isDark = isDark) {
                LinkRow(title = "Share CueCard", icon = Icons.Filled.Share, isDark = isDark) {
                    AnalyticsEvents.logButtonClick("share_app", "settings")
                    shareApp(context)
                }

                LinkRow(title = "Review on Google Play", icon = Icons.Filled.ArrowOutward, isDark = isDark) {
                    AnalyticsEvents.logButtonClick("rate_app", "settings")
                    openLink(context, AppLinks.PLAY_STORE)
                }
            }

            SettingsSection(title = "Editor", isDark = isDark) {
                SizePresetPicker(
                    label = "Text Size",
                    value = settings.editorFontSize,
                    presets = TeleprompterSettings.EDITOR_FONT_SIZE_PRESETS,
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updateEditorFontSize(it) } }
                )
            }

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

                SizePresetPicker(
                    label = "Text Size",
                    value = settings.fontSize,
                    presets = TeleprompterSettings.FONT_SIZE_PRESETS,
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updateFontSize(it) } }
                )
            }

            SettingsSection(title = "Floating Window", isDark = isDark) {
                SizePresetPicker(
                    label = "Text Size",
                    value = settings.pipFontSize,
                    presets = TeleprompterSettings.PIP_FONT_SIZE_PRESETS,
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updatePipFontSize(it) } }
                )

                MenuPickerRow(
                    label = "Layout",
                    options = OverlayAspectRatio.entries,
                    selected = settings.overlayAspectRatio,
                    optionLabel = { it.label },
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updateOverlayAspectRatio(it) } }
                )
            }

            SettingsSection(title = "Appearance", isDark = isDark) {
                MenuPickerRow(
                    label = "Theme",
                    options = ThemePreference.entries,
                    selected = settings.themePreference,
                    optionLabel = { it.displayName },
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updateThemePreference(it) } }
                )

                CueColorRow(
                    selected = settings.cueColor,
                    isDark = isDark,
                    onSelect = { scope.launch { settingsService.updateCueColor(it) } }
                )
            }

            AdvancedSection(
                screen = "settings",
                footer = advancedFooter(),
                isDark = isDark
            ) {
                NumberRow(
                    label = "Editor Text Size",
                    unit = "pt",
                    value = settings.editorFontSize,
                    range = TeleprompterSettings.EDITOR_FONT_SIZE_RANGE,
                    isDark = isDark,
                    onCommit = { scope.launch { settingsService.updateEditorFontSize(it) } }
                )
                NumberRow(
                    label = "Teleprompter Text Size",
                    unit = "pt",
                    value = settings.fontSize,
                    range = TeleprompterSettings.FONT_SIZE_RANGE,
                    isDark = isDark,
                    onCommit = { scope.launch { settingsService.updateFontSize(it) } }
                )
                NumberRow(
                    label = "Floating Window Text Size",
                    unit = "pt",
                    value = settings.pipFontSize,
                    range = TeleprompterSettings.PIP_FONT_SIZE_RANGE,
                    isDark = isDark,
                    onCommit = { scope.launch { settingsService.updatePipFontSize(it) } }
                )
            }

            SettingsSection(isDark = isDark) {
                // Greyed out once there's nothing left to reset, so a tap that
                // changes nothing never looks like one that didn't register.
                val canReset = settingsService.canResetSettings(settings)
                Text(
                    text = "Reset to Defaults",
                    fontSize = 17.sp,
                    color = if (canReset) AppColors.blue(isDark) else AppColors.textSecondary(isDark).copy(alpha = 0.5f),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            if (!canReset) return@clickableWithoutRipple
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

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/** A row that leaves Settings for something else, with an icon saying where. */
@Composable
private fun LinkRow(title: String, icon: ImageVector, isDark: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple(onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )
        Spacer(modifier = Modifier.weight(1f))
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(14.dp)
        )
    }
}

/** Hand the app's link to the system share sheet. */
private fun shareApp(context: Context) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, AppLinks.SHARE_MESSAGE)
    context.startActivity(Intent.createChooser(send, null))
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
 * A labelled row holding a number the user types, rather than drags. A figure
 * within range takes effect as it's typed; leaving the field holds whatever is
 * there to the range, so a half-typed figure is never clamped mid-typing.
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
                onValueChange = { entered ->
                    text = entered.filter { it.isDigit() }.take(3)
                    // A figure within range takes effect as it's typed, so a
                    // size can be watched changing.
                    text.toIntOrNull()?.let { if (it in range && it != value) onCommit(it) }
                },
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

private fun advancedFooter(): String {
    val editor = TeleprompterSettings.EDITOR_FONT_SIZE_RANGE
    val prompter = TeleprompterSettings.FONT_SIZE_RANGE
    val pip = TeleprompterSettings.PIP_FONT_SIZE_RANGE
    return "Editor text can be set from ${editor.first} to ${editor.last} pt, " +
        "teleprompter text from ${prompter.first} to ${prompter.last} pt, " +
        "and floating window text from ${pip.first} to ${pip.last} pt."
}

/** The color every cue is drawn in, picked from a row of swatches. */
@Composable
private fun CueColorRow(selected: CueColor, isDark: Boolean, onSelect: (CueColor) -> Unit) {
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
                val isSelected = option == selected
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clickableWithoutRipple { onSelect(option) },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .border(
                                width = if (isSelected) 2.dp else 0.dp,
                                color = if (isSelected) AppColors.textPrimary(isDark) else Color.Transparent,
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

/**
 * A setting picked from a menu, with the current choice in grey at the trailing
 * edge — the parallel to a SwiftUI menu picker.
 */
@Composable
private fun <T> MenuPickerRow(
    label: String,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    isDark: Boolean,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple { expanded = true }
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )
        Spacer(modifier = Modifier.weight(1f))

        Box {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = optionLabel(selected),
                    fontSize = 17.sp,
                    color = AppColors.textSecondary(isDark)
                )
                Icon(
                    imageVector = Icons.Filled.UnfoldMore,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier
                        .padding(start = 4.dp)
                        .size(16.dp)
                )
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                containerColor = AppColors.background(isDark)
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = optionLabel(option),
                                color = AppColors.textPrimary(isDark)
                            )
                        },
                        trailingIcon = {
                            if (option == selected) {
                                Icon(
                                    imageVector = Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = AppColors.textPrimary(isDark),
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        },
                        onClick = {
                            expanded = false
                            onSelect(option)
                        }
                    )
                }
            }
        }
    }
}

/**
 * A text size picked from a menu of presets, the same kind of row as Theme. A
 * size typed in Advanced that matches no preset shows as its own entry, so the
 * row never reads blank.
 */
@Composable
private fun SizePresetPicker(
    label: String,
    value: Int,
    presets: List<SettingPreset>,
    isDark: Boolean,
    onSelect: (Int) -> Unit
) {
    val sizes = presets.map { it.value }.let { if (value in it) it else it + value }
    MenuPickerRow(
        label = label,
        options = sizes,
        selected = value,
        optionLabel = { size -> presets.find { it.value == size }?.label ?: "Custom ($size pt)" },
        isDark = isDark,
        onSelect = onSelect
    )
}

/**
 * Typed sizes for anyone who wants one the presets don't offer. Hidden until
 * asked for, and the choice to show it is remembered.
 */
@Composable
private fun AdvancedSection(
    screen: String,
    footer: String,
    isDark: Boolean,
    fields: @Composable () -> Unit
) {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val prefs = remember { context.getSharedPreferences(ADVANCED_PREFS, Context.MODE_PRIVATE) }
    var showAdvanced by remember { mutableStateOf(prefs.getBoolean(SHOW_ADVANCED_KEY, false)) }

    SettingsSection(isDark = isDark, footer = if (showAdvanced) footer else null) {
        AnimatedVisibility(visible = showAdvanced) {
            Column { fields() }
        }

        Text(
            text = if (showAdvanced) "Hide Advanced Settings" else "Show Advanced Settings",
            fontSize = 17.sp,
            color = AppColors.blue(isDark),
            modifier = Modifier
                .fillMaxWidth()
                .clickableWithoutRipple {
                    AnalyticsEvents.logButtonClick(
                        if (showAdvanced) "hide_advanced" else "show_advanced",
                        screen
                    )
                    // Leave the field being typed in first, so its figure is
                    // committed before hiding takes the field away.
                    focusManager.clearFocus()
                    showAdvanced = !showAdvanced
                    prefs.edit().putBoolean(SHOW_ADVANCED_KEY, showAdvanced).apply()
                }
                .padding(horizontal = 20.dp, vertical = 12.dp)
        )
    }
}

private const val ADVANCED_PREFS = "cuecard_settings_ui"
private const val SHOW_ADVANCED_KEY = "settings.showAdvancedSettings"
