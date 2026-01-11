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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.analytics.ktx.analytics
import com.google.firebase.analytics.logEvent
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.models.SavedNote
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.ui.theme.AppColors
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedNotesScreen(
    settingsService: SettingsService,
    onDismiss: () -> Unit,
    onNoteSelected: () -> Unit
) {
    val savedNotes by settingsService.savedNotes.collectAsState()
    val scope = rememberCoroutineScope()
    val isDark = isSystemInDarkTheme()

    var noteToRename by remember { mutableStateOf<SavedNote?>(null) }
    var renameTitle by remember { mutableStateOf("") }

    // Log screen view
    LaunchedEffect(Unit) {
        Firebase.analytics.logEvent("screen_view") {
            param("screen_name", "saved_notes")
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
                        text = "Saved Notes",
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

            if (savedNotes.isEmpty()) {
                // Empty state
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Folder,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = AppColors.textSecondary(isDark)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "No Saved Notes",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Save your notes to access them later",
                        fontSize = 14.sp,
                        color = AppColors.textSecondary(isDark)
                    )
                }
            } else {
                // Notes list
                LazyColumn(
                    modifier = Modifier.fillMaxSize()
                ) {
                    items(
                        items = savedNotes.sortedByDescending { it.updatedAt },
                        key = { it.id }
                    ) { note ->
                        SavedNoteItem(
                            note = note,
                            isDark = isDark,
                            onClick = {
                                Firebase.analytics.logEvent("button_click") {
                                    param("button_name", "load_note")
                                    param("screen", "saved_notes")
                                    param("note_id", note.id)
                                }
                                scope.launch {
                                    settingsService.loadNote(note)
                                    onNoteSelected()
                                }
                            },
                            onRename = {
                                Firebase.analytics.logEvent("button_click") {
                                    param("button_name", "rename_note")
                                    param("screen", "saved_notes")
                                    param("note_id", note.id)
                                }
                                renameTitle = note.title
                                noteToRename = note
                            },
                            onDelete = {
                                Firebase.analytics.logEvent("button_click") {
                                    param("button_name", "delete_note")
                                    param("screen", "saved_notes")
                                    param("note_id", note.id)
                                }
                                scope.launch {
                                    settingsService.deleteNote(note.id)
                                }
                            }
                        )
                        HorizontalDivider(
                            color = AppColors.textSecondary(isDark).copy(alpha = 0.2f)
                        )
                    }
                }
            }
        }
    }

    // Rename Dialog
    if (noteToRename != null) {
        AlertDialog(
            onDismissRequest = { noteToRename = null },
            title = {
                Text(
                    text = "Rename Note",
                    color = AppColors.textPrimary(isDark)
                )
            },
            text = {
                Column {
                    Text(
                        text = "Enter a new title for your note",
                        color = AppColors.textSecondary(isDark),
                        fontSize = 14.sp
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedTextField(
                        value = renameTitle,
                        onValueChange = { renameTitle = it },
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
                        val note = noteToRename
                        val title = renameTitle.trim()
                        if (note != null && title.isNotEmpty()) {
                            scope.launch {
                                settingsService.updateNote(note.id, title = title)
                            }
                        }
                        noteToRename = null
                    }
                ) {
                    Text(
                        text = "Rename",
                        color = AppColors.green(isDark)
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { noteToRename = null }) {
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SavedNoteItem(
    note: SavedNote,
    isDark: Boolean,
    onClick: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit
) {
    val dateFormatter = remember {
        SimpleDateFormat("MMM d, yyyy 'at' h:mm a", Locale.getDefault())
    }

    // Swipe to dismiss state - matching iOS swipe actions
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> {
                    // Swipe right to delete (trailing edge)
                    onDelete()
                    true
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    // Swipe left to rename (leading edge)
                    onRename()
                    false // Don't dismiss, just trigger rename dialog
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        }
    )

    // Reset state after rename action
    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue == SwipeToDismissBoxValue.StartToEnd) {
            dismissState.reset()
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            val color = when (direction) {
                SwipeToDismissBoxValue.EndToStart -> AppColors.red(isDark) // Delete - red
                SwipeToDismissBoxValue.StartToEnd -> Color(0xFFFF9500) // Rename - orange like iOS
                else -> Color.Transparent
            }
            val icon = when (direction) {
                SwipeToDismissBoxValue.EndToStart -> Icons.Default.Delete
                SwipeToDismissBoxValue.StartToEnd -> Icons.Default.Edit
                else -> null
            }
            val alignment = when (direction) {
                SwipeToDismissBoxValue.EndToStart -> Alignment.CenterEnd
                SwipeToDismissBoxValue.StartToEnd -> Alignment.CenterStart
                else -> Alignment.Center
            }

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(color)
                    .padding(horizontal = 20.dp),
                contentAlignment = alignment
            ) {
                icon?.let {
                    Icon(
                        imageVector = it,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
        },
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = true
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(AppColors.background(isDark))
                .clickable(onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = note.title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = note.content
                        .take(100)
                        .replace("\n", " "),
                    fontSize = 14.sp,
                    color = AppColors.textSecondary(isDark),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = dateFormatter.format(Date(note.updatedAt)),
                    fontSize = 12.sp,
                    color = AppColors.textSecondary(isDark).copy(alpha = 0.7f)
                )
            }
        }
    }
}
