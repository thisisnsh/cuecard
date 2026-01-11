package com.thisisnsh.cuecard.android.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.ui.components.glassEffect
import com.thisisnsh.cuecard.android.ui.theme.AppColors
import kotlinx.coroutines.launch
import android.widget.NumberPicker as AndroidNumberPicker

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    settingsService: SettingsService,
    onNavigateToSettings: () -> Unit,
    onNavigateToTeleprompter: () -> Unit,
    onNavigateToSavedNotes: () -> Unit
) {
    val settings by settingsService.settings.collectAsState()
    val notes by settingsService.notes.collectAsState()
    val currentNoteId by settingsService.currentNoteId.collectAsState()
    val scope = rememberCoroutineScope()
    val isDark = isSystemInDarkTheme()
    val focusManager = LocalFocusManager.current

    var showTimerPicker by remember { mutableStateOf(false) }
    var localNotes by remember { mutableStateOf(notes) }
    var showMenuDropdown by remember { mutableStateOf(false) }
    var showSaveDialog by remember { mutableStateOf(false) }
    var saveNoteTitle by remember { mutableStateOf("") }

    // Sync local notes with service
    LaunchedEffect(notes) {
        localNotes = notes
    }

    // Log screen view
    LaunchedEffect(Unit) {
        Firebase.analytics.logEvent("screen_view") {
            param("screen_name", "home")
        }
        settingsService.loadSettings()
    }

    val hasNotes = localNotes.trim().isNotEmpty()
    val hasUnsavedChanges = settingsService.hasUnsavedChanges

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
                        text = "CueCard",
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                },
                actions = {
                    // More menu with save options
                    Box {
                        IconButton(onClick = { showMenuDropdown = true }) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = "More options",
                                tint = AppColors.textPrimary(isDark)
                            )
                        }
                        DropdownMenu(
                            expanded = showMenuDropdown,
                            onDismissRequest = { showMenuDropdown = false },
                            modifier = Modifier.background(AppColors.background(isDark))
                        ) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = "Saved Notes",
                                        color = AppColors.textPrimary(isDark)
                                    )
                                },
                                onClick = {
                                    Firebase.analytics.logEvent("button_click") {
                                        param("button_name", "saved_notes")
                                        param("screen", "home")
                                    }
                                    onNavigateToSavedNotes()
                                    showMenuDropdown = false
                                }
                            )

                            HorizontalDivider(
                                color = AppColors.textSecondary(isDark).copy(alpha = 0.2f)
                            )

                            // Save option (only show if editing existing note with changes)
                            if (currentNoteId != null && hasUnsavedChanges) {
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            text = "Save",
                                            color = AppColors.textPrimary(isDark)
                                        )
                                    },
                                    onClick = {
                                        Firebase.analytics.logEvent("button_click") {
                                            param("button_name", "save_note")
                                            param("screen", "home")
                                        }
                                        scope.launch {
                                            settingsService.saveChangesToCurrentNote()
                                        }
                                        showMenuDropdown = false
                                    }
                                )
                            }

                            // Save as New option
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = "Save as New",
                                        color = if (hasNotes) AppColors.textPrimary(isDark)
                                        else AppColors.textSecondary(isDark)
                                    )
                                },
                                onClick = {
                                    if (hasNotes) {
                                        Firebase.analytics.logEvent("button_click") {
                                            param("button_name", "save_as_new")
                                            param("screen", "home")
                                        }
                                        saveNoteTitle = ""
                                        showSaveDialog = true
                                        showMenuDropdown = false
                                    }
                                },
                                enabled = hasNotes
                            )

                            HorizontalDivider(
                                color = AppColors.textSecondary(isDark).copy(alpha = 0.2f)
                            )

                            // New Note option
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = "New Note",
                                        color = AppColors.textPrimary(isDark)
                                    )
                                },
                                onClick = {
                                    Firebase.analytics.logEvent("button_click") {
                                        param("button_name", "new_note")
                                        param("screen", "home")
                                    }
                                    scope.launch {
                                        settingsService.createNewNote()
                                    }
                                    showMenuDropdown = false
                                }
                            )
                        }
                    }

                    IconButton(onClick = onNavigateToSettings) {
                        Icon(
                            imageVector = Icons.Default.Settings,
                            contentDescription = "Settings",
                            tint = AppColors.textPrimary(isDark)
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.background(isDark)
                )
            )

            // Notes Editor
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
            ) {
                BasicTextField(
                    value = localNotes,
                    onValueChange = { newValue ->
                        localNotes = newValue
                        scope.launch {
                            settingsService.saveNotes(newValue)
                        }
                    },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(vertical = 8.dp),
                    textStyle = TextStyle(
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppColors.textPrimary(isDark),
                        lineHeight = 24.sp
                    ),
                    cursorBrush = SolidColor(AppColors.green(isDark)),
                    decorationBox = { innerTextField ->
                        Box {
                            if (localNotes.isEmpty()) {
                                Text(
                                    text = "Add your script here...\n\nUse [note text] for delivery cues like \"Welcome Everyone [note smile and pause]\"",
                                    fontSize = 16.sp,
                                    color = AppColors.textSecondary(isDark).copy(alpha = 0.6f),
                                    lineHeight = 24.sp
                                )
                            }
                            innerTextField()
                        }
                    }
                )
            }

            // Bottom Controls
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 24.dp)
                    .imePadding()
            ) {
                // Timer Picker (animated)
                AnimatedVisibility(
                    visible = showTimerPicker,
                    enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                    exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(AppColors.background(isDark))
                            .border(
                                width = 1.dp,
                                color = AppColors.textSecondary(isDark).copy(alpha = 0.2f),
                                shape = RoundedCornerShape(16.dp)
                            )
                            .padding(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Timer",
                                fontSize = 16.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.textPrimary(isDark)
                            )
                            IconButton(
                                onClick = { showTimerPicker = false },
                                modifier = Modifier
                                    .size(28.dp)
                                    .clip(CircleShape)
                                    .background(AppColors.background(isDark).copy(alpha = 0.85f))
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Close",
                                    modifier = Modifier.size(14.dp),
                                    tint = AppColors.textSecondary(isDark)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(12.dp))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Duration",
                                color = AppColors.textSecondary(isDark)
                            )

                            Row(
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                // Minutes picker
                                NumberPicker(
                                    value = settings.timerMinutes,
                                    range = 0..59,
                                    onValueChange = { newValue ->
                                        scope.launch {
                                            settingsService.updateTimerMinutes(newValue)
                                        }
                                    }
                                )

                                Text(
                                    text = ":",
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = AppColors.textSecondary(isDark),
                                    modifier = Modifier.padding(horizontal = 8.dp)
                                )

                                // Seconds picker
                                NumberPicker(
                                    value = settings.timerSeconds,
                                    range = 0..59,
                                    onValueChange = { newValue ->
                                        scope.launch {
                                            settingsService.updateTimerSeconds(newValue)
                                        }
                                    },
                                    formatValue = { String.format("%02d", it) }
                                )
                            }
                        }
                    }
                }

                // Bottom Row: Timer/Sample Text Button + Play Button
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Bottom
                ) {
                    // Set Timer or Add Sample Text Button
                    Box(
                        modifier = Modifier
                            .height(52.dp)
                            .clip(RoundedCornerShape(50))
                            .glassEffect(isDark = isDark)
                            .clickable {
                                if (hasNotes || showTimerPicker) {
                                    showTimerPicker = !showTimerPicker
                                } else {
                                    scope.launch {
                                        settingsService.addSampleText()
                                    }
                                }
                            }
                            .padding(horizontal = 16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = when {
                                showTimerPicker -> "Done"
                                hasNotes -> "Set Timer"
                                else -> "Add Sample Text"
                            },
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                    }

                    Spacer(modifier = Modifier.width(12.dp))

                    // Play Button
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .clip(CircleShape)
                            .background(
                                if (hasNotes) AppColors.green(isDark)
                                else AppColors.green(isDark).copy(alpha = 0.6f)
                            )
                            .glassEffect(shape = CircleShape, isDark = isDark)
                            .clickable(enabled = hasNotes) {
                                focusManager.clearFocus()
                                onNavigateToTeleprompter()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = "Start Teleprompter",
                            modifier = Modifier.size(24.dp),
                            tint = if (isDark) Color.Black else Color.White
                        )
                    }
                }
            }
        }
    }

    // Save Note Dialog
    if (showSaveDialog) {
        AlertDialog(
            onDismissRequest = { showSaveDialog = false },
            title = {
                Text(
                    text = "Save Note",
                    color = AppColors.textPrimary(isDark)
                )
            },
            text = {
                Column {
                    Text(
                        text = "Enter a title for your note",
                        color = AppColors.textSecondary(isDark),
                        fontSize = 14.sp
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedTextField(
                        value = saveNoteTitle,
                        onValueChange = { saveNoteTitle = it },
                        label = { Text("Note title") },
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.green(isDark),
                            cursorColor = AppColors.green(isDark)
                        )
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val title = saveNoteTitle.trim()
                        if (title.isNotEmpty()) {
                            scope.launch {
                                settingsService.saveCurrentNote(title)
                            }
                        }
                        showSaveDialog = false
                    }
                ) {
                    Text(
                        text = "Save",
                        color = AppColors.green(isDark)
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showSaveDialog = false }) {
                    Text(
                        text = "Cancel",
                        color = AppColors.textSecondary(isDark)
                    )
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

@Composable
private fun NumberPicker(
    value: Int,
    range: IntRange,
    onValueChange: (Int) -> Unit,
    formatValue: (Int) -> String = { it.toString() }
) {
    AndroidView(
        factory = { context ->
            AndroidNumberPicker(context).apply {
                minValue = range.first
                maxValue = range.last
                wrapSelectorWheel = true
                descendantFocusability = AndroidNumberPicker.FOCUS_BLOCK_DESCENDANTS
                setFormatter { formatValue(it) }
                setOnValueChangedListener { _, _, newValue ->
                    onValueChange(newValue)
                }
            }
        },
        update = { picker ->
            if (picker.minValue != range.first) {
                picker.minValue = range.first
            }
            if (picker.maxValue != range.last) {
                picker.maxValue = range.last
            }
            picker.setFormatter { formatValue(it) }
            if (picker.value != value) {
                picker.value = value
            }
        },
        modifier = Modifier
            .width(64.dp)
            .height(88.dp)
    )
}
