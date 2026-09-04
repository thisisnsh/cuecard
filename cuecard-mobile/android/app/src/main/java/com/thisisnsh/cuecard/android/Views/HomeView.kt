package com.thisisnsh.cuecard.android.views

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.play.core.review.ReviewManagerFactory
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.RemoteMessage
import com.thisisnsh.cuecard.android.models.ScriptFile
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.modifiers.scriptEdgeFade
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.RemoteConfigService
import com.thisisnsh.cuecard.android.services.ReviewPromptService
import com.thisisnsh.cuecard.android.services.SettingsService
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.thisisnsh.cuecard.android.services.SavedNote
import java.text.DateFormat
import java.util.Locale
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * How much of the editor's bottom the controls row covers: the play button and
 * the timer beside it, plus the gap they sit above. The script keeps this much
 * room clear so its last line never rests underneath them.
 */
private val CONTROLS_HEIGHT = 52.dp + 24.dp

/**
 * The bottom fade reaches up past the floating controls, so a line is gone
 * before it can pass behind them.
 */
private val EDITOR_BOTTOM_FADE = 72.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeView(
    authService: AuthenticationService,
    settingsService: SettingsService,
    remoteConfig: RemoteConfigService
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val notes by settingsService.notes.collectAsState()
    val settings by settingsService.settings.collectAsState()
    val savedNotes by settingsService.savedNotes.collectAsState()
    val currentNoteId by settingsService.currentNoteId.collectAsState()
    val config by remoteConfig.config.collectAsState()
    val dismissedIds by remoteConfig.dismissedIds.collectAsState()

    var showingSettings by remember { mutableStateOf(false) }
    var showingTeleprompter by remember { mutableStateOf(false) }
    var showingSavedNotes by remember { mutableStateOf(false) }
    var showingTimerPicker by remember { mutableStateOf(false) }
    var timerPickerContentVisible by remember { mutableStateOf(false) }
    var showingSaveDialog by remember { mutableStateOf(false) }
    var saveNoteTitle by remember { mutableStateOf("") }
    var showingMenu by remember { mutableStateOf(false) }
    var fileErrorMessage by remember { mutableStateOf<String?>(null) }
    var isEditorFocused by remember { mutableStateOf(false) }
    val editorController = remember { CueEditorController() }

    val hasNotes = notes.trim().isNotEmpty()

    val bannerMessage = remember(config, dismissedIds) {
        remoteConfig.message(RemoteMessage.Surface.HOME_BANNER)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("home")
    }

    // MARK: - Files

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val text = ScriptFile.readText(context, uri)
                if (text.trim().isEmpty()) {
                    fileErrorMessage = "That file is empty."
                    return@launch
                }
                settingsService.importNote(
                    title = ScriptFile.title(context, uri),
                    content = TeleprompterParser.normalizingTags(text)
                )
            } catch (e: Exception) {
                fileErrorMessage = "This file couldn't be read as text."
            }
        }
    }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument(ScriptFile.EXPORT_MIME_TYPE)
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        try {
            context.contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(TeleprompterParser.normalizingTags(notes).toByteArray())
            } ?: throw IllegalStateException("Could not open $uri")
        } catch (e: Exception) {
            fileErrorMessage = e.message ?: "This file couldn't be written."
        }
    }

    // MARK: - Timer picker

    fun openTimerPicker() {
        AnalyticsEvents.logButtonClick("set_timer", "home")
        showingTimerPicker = true
        scope.launch {
            delay(120)
            timerPickerContentVisible = true
        }
    }

    fun closeTimerPicker() {
        AnalyticsEvents.logButtonClick("close_timer_picker", "home")
        timerPickerContentVisible = false
        scope.launch {
            delay(180)
            showingTimerPicker = false
        }
    }

    /**
     * Ask for a review once the teleprompter has closed and the user is back on a
     * calm screen. The delay lets the full-screen dismissal finish first, so the
     * system dialog doesn't land on top of an animating view.
     */
    fun requestReviewIfEarned() {
        val reviewPrompts = ReviewPromptService.getInstance(context)
        if (!reviewPrompts.shouldRequestReview) return

        scope.launch {
            delay(800)
            reviewPrompts.logReviewRequested()

            val activity = context.findActivity() ?: return@launch
            val manager = ReviewManagerFactory.create(context)
            manager.requestReviewFlow().addOnCompleteListener { task ->
                // Like StoreKit, Play decides whether anything is actually shown,
                // and there is no callback saying whether it was.
                if (task.isSuccessful) {
                    runCatching { manager.launchReviewFlow(activity, task.result) }
                }
            }
        }
    }

    BackHandler(enabled = showingSettings || showingSavedNotes || showingTeleprompter || isEditorFocused) {
        when {
            showingTeleprompter -> showingTeleprompter = false
            showingSettings -> showingSettings = false
            showingSavedNotes -> showingSavedNotes = false
            isEditorFocused -> isEditorFocused = false
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            text = "CueCard",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                    },
                    navigationIcon = {
                        Icon(
                            imageVector = Icons.Filled.Folder,
                            contentDescription = "Saved Notes",
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(horizontal = 12.dp)
                                .size(20.dp)
                                .clickableWithoutRipple {
                                    AnalyticsEvents.logButtonClick("saved_notes", "home")
                                    showingSavedNotes = true
                                }
                        )
                    },
                    actions = {
                        Box {
                            Icon(
                                imageVector = Icons.Filled.MoreVert,
                                contentDescription = "More",
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .size(20.dp)
                                    .clickableWithoutRipple { showingMenu = true }
                            )

                            DropdownMenu(
                                expanded = showingMenu,
                                onDismissRequest = { showingMenu = false },
                                containerColor = AppColors.background(isDark)
                            ) {
                                if (currentNoteId != null && settingsService.hasUnsavedChanges) {
                                    DropdownMenuItem(
                                        text = { Text("Save") },
                                        onClick = {
                                            showingMenu = false
                                            AnalyticsEvents.logButtonClick("save_note", "home")
                                            scope.launch { settingsService.saveChangesToCurrentNote() }
                                        }
                                    )
                                }

                                DropdownMenuItem(
                                    text = { Text("Save as New") },
                                    enabled = hasNotes,
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("save_as_new", "home")
                                        saveNoteTitle = ""
                                        showingSaveDialog = true
                                    }
                                )

                                androidx.compose.material3.HorizontalDivider()

                                DropdownMenuItem(
                                    text = { Text("New Note") },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("new_note", "home")
                                        scope.launch { settingsService.createNewNote() }
                                    }
                                )

                                androidx.compose.material3.HorizontalDivider()

                                DropdownMenuItem(
                                    text = { Text("Import from File") },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("import_file", "home")
                                        importLauncher.launch(ScriptFile.importableMimeTypes)
                                    }
                                )

                                DropdownMenuItem(
                                    text = { Text("Export to File") },
                                    enabled = hasNotes,
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("export_file", "home")
                                        exportLauncher.launch(
                                            ScriptFile.suggestedFileName(
                                                title = settingsService.currentNote?.title,
                                                content = notes
                                            )
                                        )
                                    }
                                )
                            }
                        }

                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = "Settings",
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(start = 8.dp, end = 16.dp)
                                .size(20.dp)
                                .clickableWithoutRipple {
                                    AnalyticsEvents.logButtonClick("settings", "home")
                                    showingSettings = true
                                }
                        )
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.background(isDark)
                    )
                )
            }
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    // Anything the worker wants people to see, above the script.
                    // Nothing to show is the normal case, and then this is a
                    // zero-height view the layout never notices.
                    bannerMessage?.let { message ->
                        RemoteMessageBanner(
                            message = message,
                            remoteConfig = remoteConfig,
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .padding(top = 12.dp)
                        )
                    }

                    NotesEditorView(
                        text = notes,
                        onTextChange = { scope.launch { settingsService.saveNotes(it) } },
                        isFocused = isEditorFocused,
                        onFocusChange = { isEditorFocused = it },
                        controller = editorController,
                        cueColor = settings.cueColor,
                        isDark = isDark,
                        bottomOverlayHeight = if (isEditorFocused) CUE_BAR_HEIGHT else CONTROLS_HEIGHT,
                        modifier = Modifier.weight(1f)
                    )
                }

                // The controls at the bottom: the cue bar while a script is being
                // written, the timer and play button once the keyboard has gone.
                if (isEditorFocused) {
                    CueBar(
                        isDark = isDark,
                        onAddCue = {
                            AnalyticsEvents.logButtonClick("insert_cue", "home")
                            editorController.insertCue()
                        },
                        onDismissKeyboard = { isEditorFocused = false },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .imePadding()
                    )
                } else {
                    TimerControl(
                        settings = settings,
                        hasNotes = hasNotes,
                        isExpanded = showingTimerPicker,
                        contentVisible = timerPickerContentVisible,
                        isDark = isDark,
                        onOpen = { openTimerPicker() },
                        onClose = { closeTimerPicker() },
                        onMinutes = { scope.launch { settingsService.updateTimerMinutes(it) } },
                        onSeconds = { scope.launch { settingsService.updateTimerSeconds(it) } },
                        onAddSampleText = {
                            AnalyticsEvents.logButtonClick("add_sample_text", "home")
                            scope.launch { settingsService.addSampleText() }
                        },
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 20.dp, bottom = 24.dp, end = 84.dp)
                    )

                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(end = 20.dp, bottom = 24.dp)
                            .size(52.dp)
                            .alpha(if (hasNotes) 1f else 0.6f)
                            .clip(CircleShape)
                            .background(AppColors.green(isDark))
                            .glassed(CircleShape, isDark)
                            .clickableWithoutRipple {
                                if (!hasNotes) return@clickableWithoutRipple
                                AnalyticsEvents.logButtonClick("start_teleprompter", "home")
                                isEditorFocused = false
                                showingTeleprompter = true
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Filled.PlayArrow,
                            contentDescription = "Start",
                            tint = if (isDark) Color.Black else Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }

        // MARK: - Presentations

        AnimatedVisibility(
            visible = showingSavedNotes,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            SavedNotesView(
                savedNotes = savedNotes,
                isDark = isDark,
                onDismiss = { showingSavedNotes = false },
                onLoad = { note ->
                    scope.launch { settingsService.loadNote(note) }
                    showingSavedNotes = false
                },
                onRename = { note, title -> scope.launch { settingsService.updateNote(note.id, title = title) } },
                onDelete = { note -> scope.launch { settingsService.deleteNote(note.id) } }
            )
        }

        AnimatedVisibility(
            visible = showingSettings,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            SettingsView(
                authService = authService,
                settingsService = settingsService,
                remoteConfig = remoteConfig,
                onDismiss = { showingSettings = false }
            )
        }

        AnimatedVisibility(
            visible = showingTeleprompter,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            val content = remember(notes) { TeleprompterParser.parseNotes(notes) }
            TeleprompterView(
                content = content,
                settings = settings,
                remoteConfig = remoteConfig,
                onDismiss = {
                    showingTeleprompter = false
                    requestReviewIfEarned()
                }
            )
        }
    }

    // MARK: - Dialogs

    if (showingSaveDialog) {
        TitleDialog(
            title = "Save Note",
            message = "Enter a title for your note",
            confirmLabel = "Save",
            initialValue = saveNoteTitle,
            isDark = isDark,
            onDismiss = { showingSaveDialog = false },
            onConfirm = { title ->
                showingSaveDialog = false
                if (title.trim().isNotEmpty()) {
                    scope.launch { settingsService.saveCurrentNote(title.trim()) }
                }
            }
        )
    }

    fileErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { fileErrorMessage = null },
            title = { Text("Something Went Wrong") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { fileErrorMessage = null }) {
                    Text("OK", color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

/**
 * Notes editor with live syntax highlighting for `[cue …]` tags, and the
 * placeholder that says how to write one.
 */
@Composable
fun NotesEditorView(
    text: String,
    onTextChange: (String) -> Unit,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    controller: CueEditorController,
    cueColor: com.thisisnsh.cuecard.android.models.CueColor,
    isDark: Boolean,
    bottomOverlayHeight: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .scriptEdgeFade(isDark = isDark, top = CUE_EDITOR_EDGE_FADE, bottom = EDITOR_BOTTOM_FADE)
    ) {
        if (text.isEmpty()) {
            Text(
                text = "Add your script here...\n\nTap Add Cue below the script — or just type [ — to drop in a delivery reminder like \"Welcome everyone [cue smile and pause]\"",
                fontSize = 16.sp,
                color = AppColors.textSecondary(isDark).copy(alpha = 0.6f),
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .padding(top = CUE_EDITOR_EDGE_FADE + 8.dp)
            )
        }

        CueTextEditor(
            text = text,
            onTextChange = onTextChange,
            isFocused = isFocused,
            onFocusChange = onFocusChange,
            controller = controller,
            cueColor = cueColor,
            isDark = isDark,
            bottomOverlayHeight = bottomOverlayHeight
        )
    }
}

/**
 * The timer control at the bottom left: a capsule that expands into a card with
 * two wheels, or the invitation to fill an empty script.
 */
@Composable
private fun TimerControl(
    settings: com.thisisnsh.cuecard.android.services.TeleprompterSettings,
    hasNotes: Boolean,
    isExpanded: Boolean,
    contentVisible: Boolean,
    isDark: Boolean,
    onOpen: () -> Unit,
    onClose: () -> Unit,
    onMinutes: (Int) -> Unit,
    onSeconds: (Int) -> Unit,
    onAddSampleText: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (!hasNotes && !isExpanded) {
        Box(
            modifier = modifier
                .height(52.dp)
                .glassed(Capsule, isDark)
                .clickableWithoutRipple(onAddSampleText)
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "Add Sample Text",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )
        }
        return
    }

    // The container springs open and the contents arrive a moment later; closing
    // takes the contents away first and collapses behind them.
    val cornerRadius by animateDpAsState(
        targetValue = if (isExpanded) 16.dp else 26.dp,
        animationSpec = spring(dampingRatio = 0.86f, stiffness = 385.5f),
        label = "timerCorner"
    )
    val contentAlpha by animateFloatAsState(
        targetValue = if (contentVisible) 1f else 0f,
        animationSpec = tween(durationMillis = 180),
        label = "timerContent"
    )

    Column(
        modifier = modifier
            .animateContentSizeSpring()
            .glassed(RoundedCornerShape(cornerRadius), isDark)
            .padding(if (isExpanded) 12.dp else 0.dp)
    ) {
        if (isExpanded) {
            Column(
                modifier = Modifier.alpha(contentAlpha),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Timer",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )

                    Spacer(modifier = Modifier.weight(1f))

                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close",
                        tint = AppColors.textSecondary(isDark),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(AppColors.background(isDark).copy(alpha = 0.85f))
                            .clickableWithoutRipple { if (contentVisible) onClose() }
                            .padding(6.dp)
                            .size(12.dp)
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Duration",
                        fontSize = 15.sp,
                        color = AppColors.textSecondary(isDark)
                    )

                    Spacer(modifier = Modifier.weight(1f))

                    WheelPicker(
                        range = 0..59,
                        selected = settings.timerMinutes,
                        onSelect = onMinutes,
                        format = { it.toString() },
                        isDark = isDark
                    )

                    Text(
                        text = ":",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textSecondary(isDark)
                    )

                    WheelPicker(
                        range = 0..59,
                        selected = settings.timerSeconds,
                        onSelect = onSeconds,
                        format = { String.format(Locale.US, "%02d", it) },
                        isDark = isDark
                    )
                }
            }
        } else {
            Box(
                modifier = Modifier
                    .height(52.dp)
                    .clickableWithoutRipple(onOpen)
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Set Timer",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )
            }
        }
    }
}

/** A dialog asking for a note title. */
@Composable
private fun TitleDialog(
    title: String,
    message: String,
    confirmLabel: String,
    initialValue: String,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var value by remember { mutableStateOf(initialValue) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(message, fontSize = 14.sp, color = AppColors.textSecondary(isDark))
                BasicTextField(
                    value = value,
                    onValueChange = { value = it },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 16.sp, color = AppColors.textPrimary(isDark)),
                    cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(AppColors.textSecondary(isDark).copy(alpha = 0.12f))
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(value) }) {
                Text(confirmLabel, color = AppColors.blue(isDark))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = AppColors.blue(isDark))
            }
        },
        containerColor = AppColors.background(isDark)
    )
}

/** The activity behind a composable's context, for the Play review flow. */
internal fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}

/** The card resizes on the same spring its corners travel on. */
private fun Modifier.animateContentSizeSpring(): Modifier =
    this.animateContentSize(
        animationSpec = spring(
            dampingRatio = 0.86f,
            stiffness = 385.5f,
            visibilityThreshold = IntSize.VisibilityThreshold
        )
    )

/**
 * One of the two wheels behind the timer's Duration row.
 *
 * SwiftUI has a wheel picker; Compose does not, so this is a snapping list three
 * items tall with the chosen value in the middle.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WheelPicker(
    range: IntRange,
    selected: Int,
    onSelect: (Int) -> Unit,
    format: (Int) -> String,
    isDark: Boolean
) {
    val itemHeight = 29.dp
    val state = rememberLazyListState(
        initialFirstVisibleItemIndex = (selected - range.first).coerceIn(0, range.count() - 1)
    )
    val flingBehavior = rememberSnapFlingBehavior(lazyListState = state)

    // The value under the middle of the wheel is the one that's chosen.
    val centered by remember {
        derivedStateOf {
            val index = state.firstVisibleItemIndex +
                if (state.firstVisibleItemScrollOffset > 0) 1 else 0
            (range.first + index).coerceIn(range.first, range.last)
        }
    }

    LaunchedEffect(state.isScrollInProgress) {
        if (!state.isScrollInProgress && centered != selected) {
            onSelect(centered)
        }
    }

    LaunchedEffect(selected) {
        if (!state.isScrollInProgress && centered != selected) {
            state.scrollToItem((selected - range.first).coerceIn(0, range.count() - 1))
        }
    }

    LazyColumn(
        state = state,
        flingBehavior = flingBehavior,
        contentPadding = PaddingValues(vertical = itemHeight),
        modifier = Modifier
            .width(60.dp)
            .height(itemHeight * 3)
    ) {
        items(range.count()) { index ->
            val value = range.first + index
            Box(
                modifier = Modifier
                    .height(itemHeight)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = format(value),
                    fontSize = 20.sp,
                    color = if (value == centered) {
                        AppColors.textPrimary(isDark)
                    } else {
                        AppColors.textSecondary(isDark)
                    }
                )
            }
        }
    }
}

/** View for displaying and managing saved notes */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedNotesView(
    savedNotes: List<SavedNote>,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onLoad: (SavedNote) -> Unit,
    onRename: (SavedNote, String) -> Unit,
    onDelete: (SavedNote) -> Unit
) {
    var noteToRename by remember { mutableStateOf<SavedNote?>(null) }
    val dateFormat = remember {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("saved_notes")
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Saved Notes",
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
                                AnalyticsEvents.logButtonClick("done", "saved_notes")
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
        if (savedNotes.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Folder,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier.size(48.dp)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "No Saved Notes",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Save your notes to access them later",
                    fontSize = 15.sp,
                    color = AppColors.textSecondary(isDark),
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                items(
                    items = savedNotes.sortedByDescending { it.updatedAt },
                    key = { it.id }
                ) { note ->
                    SavedNoteRow(
                        note = note,
                        isDark = isDark,
                        timestamp = dateFormat.format(Date(note.updatedAt)),
                        onLoad = {
                            AnalyticsEvents.logButtonClick(
                                "load_note",
                                "saved_notes",
                                mapOf("note_id" to note.id)
                            )
                            onLoad(note)
                        },
                        onRename = {
                            AnalyticsEvents.logButtonClick(
                                "rename_note",
                                "saved_notes",
                                mapOf("note_id" to note.id)
                            )
                            noteToRename = note
                        },
                        onDelete = {
                            AnalyticsEvents.logButtonClick(
                                "delete_note",
                                "saved_notes",
                                mapOf("note_id" to note.id)
                            )
                            onDelete(note)
                        }
                    )
                }
            }
        }
    }

    noteToRename?.let { note ->
        TitleDialog(
            title = "Rename Note",
            message = "Enter a new title for your note",
            confirmLabel = "Rename",
            initialValue = note.title,
            isDark = isDark,
            onDismiss = { noteToRename = null },
            onConfirm = { title ->
                if (title.trim().isNotEmpty()) {
                    onRename(note, title.trim())
                }
                noteToRename = null
            }
        )
    }
}

/**
 * One saved note. A full swipe from the trailing edge deletes it; a swipe from
 * the leading edge reveals Rename, and springs back rather than committing.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SavedNoteRow(
    note: SavedNote,
    isDark: Boolean,
    timestamp: String,
    onLoad: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> {
                    onDelete()
                    true
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    onRename()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val isRename = dismissState.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(if (isRename) Color(0xFFFF9500) else AppColors.red(isDark))
                    .padding(horizontal = 20.dp),
                contentAlignment = if (isRename) Alignment.CenterStart else Alignment.CenterEnd
            ) {
                Text(
                    text = if (isRename) "Rename" else "Delete",
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(AppColors.background(isDark))
                .clickableWithoutRipple(onLoad)
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = note.title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )

            Text(
                text = note.content.take(100).replace("\n", " "),
                fontSize = 15.sp,
                color = AppColors.textSecondary(isDark),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            Text(
                text = timestamp,
                fontSize = 12.sp,
                color = AppColors.textSecondary(isDark).copy(alpha = 0.7f)
            )
        }
    }
}
