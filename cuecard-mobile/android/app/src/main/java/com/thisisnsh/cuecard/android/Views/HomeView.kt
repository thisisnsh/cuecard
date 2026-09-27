package com.thisisnsh.cuecard.android.views

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.play.core.review.ReviewManagerFactory
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.RemoteNotification
import com.thisisnsh.cuecard.android.models.ScriptFile
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.modifiers.scriptEdgeFade
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.ReviewPromptService
import com.thisisnsh.cuecard.android.services.SettingsService
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.thisisnsh.cuecard.android.services.SavedNote
import java.text.DateFormat
import java.util.Date
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.ViewCarousel
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import kotlinx.coroutines.CoroutineStart
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
    settingsService: SettingsService,
    notifications: RemoteNotificationService
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val notes by settingsService.notes.collectAsState()
    val settings by settingsService.settings.collectAsState()
    val savedNotes by settingsService.savedNotes.collectAsState()
    val currentNoteId by settingsService.currentNoteId.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()

    var showingSettings by remember { mutableStateOf(false) }
    var showingHelp by remember { mutableStateOf(false) }
    var showingTeleprompter by remember { mutableStateOf(false) }
    var showingCards by remember { mutableStateOf(false) }
    var showingSavedNotes by remember { mutableStateOf(false) }
    var showingTimer by remember { mutableStateOf(false) }
    var showingSaveDialog by remember { mutableStateOf(false) }
    var saveNoteTitle by remember { mutableStateOf("") }
    var showingMenu by remember { mutableStateOf(false) }
    var showingModeMenu by remember { mutableStateOf(false) }
    var fileErrorMessage by remember { mutableStateOf<String?>(null) }
    var isEditorFocused by remember { mutableStateOf(false) }
    val editorController = remember { CueEditorController() }

    val hasNotes = notes.trim().isNotEmpty()
    val isCardsMode = settings.scriptMode == ScriptMode.CARDS
    val cards = remember(notes) { CueCards.cards(notes) }
    val canStart = if (isCardsMode) cards.isNotEmpty() else hasNotes

    val banner = remember(payload, dismissedIds) {
        notifications.notification(RemoteNotification.Surface.HOME_BANNER)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("home")
    }

    /**
     * The script is written straight into the store, before this returns, so what
     * the editor reads back is never a keystroke behind what it just wrote.
     */
    fun saveNotes(text: String) {
        scope.launch(start = CoroutineStart.UNDISPATCHED) { settingsService.saveNotes(text) }
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

    BackHandler(
        enabled = showingSettings || showingSavedNotes || showingTeleprompter || showingTimer ||
            showingHelp || isEditorFocused
    ) {
        when {
            showingHelp -> showingHelp = false
            showingTeleprompter -> showingTeleprompter = false
            showingSettings -> showingSettings = false
            showingTimer -> showingTimer = false
            showingSavedNotes -> showingSavedNotes = false
            isEditorFocused -> isEditorFocused = false
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                TopAppBar(
                    // Teleprompter or cards: what the editor writes and the Play
                    // button opens. The bar shows the chosen mode's name.
                    title = {
                        Box {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .clickableWithoutRipple { showingModeMenu = true }
                                    .semantics { contentDescription = "Mode: ${settings.scriptMode.displayName}" }
                            ) {
                                Text(
                                    text = settings.scriptMode.displayName,
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = AppColors.textPrimary(isDark)
                                )
                                Icon(
                                    imageVector = Icons.Filled.KeyboardArrowDown,
                                    contentDescription = null,
                                    tint = AppColors.textSecondary(isDark),
                                    modifier = Modifier.size(18.dp)
                                )
                            }

                            // Plain items rather than a checked list: the bar already
                            // says which mode is on.
                            DropdownMenu(
                                expanded = showingModeMenu,
                                onDismissRequest = { showingModeMenu = false },
                                containerColor = AppColors.background(isDark)
                            ) {
                                ScriptMode.entries.forEach { mode ->
                                    DropdownMenuItem(
                                        text = { Text(mode.displayName) },
                                        onClick = {
                                            showingModeMenu = false
                                            AnalyticsEvents.logButtonClick("mode_${mode.rawValue}", "home")
                                            isEditorFocused = false
                                            scope.launch { settingsService.updateScriptMode(mode) }
                                        }
                                    )
                                }
                            }
                        }
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
                                    text = { Text("New") },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("new_note", "home")
                                        scope.launch { settingsService.createNewNote() }
                                    }
                                )

                                androidx.compose.material3.HorizontalDivider()

                                DropdownMenuItem(
                                    text = { Text("Saved Content") },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("saved_notes", "home")
                                        isEditorFocused = false
                                        showingSavedNotes = true
                                    }
                                )

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
                                .padding(horizontal = 8.dp)
                                .size(20.dp)
                                .clickableWithoutRipple {
                                    AnalyticsEvents.logButtonClick("settings", "home")
                                    isEditorFocused = false
                                    showingSettings = true
                                }
                        )

                        HelpButton(
                            page = HelpPage.writing(settings.scriptMode),
                            isDark = isDark,
                            modifier = Modifier.padding(end = 4.dp)
                        ) {
                            isEditorFocused = false
                            showingHelp = true
                        }
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
                    banner?.let { notification ->
                        NotificationBanner(
                            notification = notification,
                            notifications = notifications,
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .padding(top = 12.dp)
                        )
                    }

                    val bottomInset = if (isEditorFocused) CUE_BAR_HEIGHT else CONTROLS_HEIGHT
                    if (isCardsMode) {
                        CardsEditorView(
                            text = notes,
                            onTextChange = ::saveNotes,
                            isFocused = isEditorFocused,
                            onFocusChange = { isEditorFocused = it },
                            controller = editorController,
                            cueColor = settings.cards.cueColor,
                            isDark = isDark,
                            fontSize = settings.cards.editorFontSize.sp,
                            cardLimit = CueCards.CHARACTER_LIMIT,
                            bottomInset = bottomInset,
                            modifier = Modifier.weight(1f)
                        )
                    } else {
                        NotesEditorView(
                            text = notes,
                            onTextChange = ::saveNotes,
                            isFocused = isEditorFocused,
                            onFocusChange = { isEditorFocused = it },
                            controller = editorController,
                            cueColor = settings.cueColor,
                            isDark = isDark,
                            fontSize = settings.editorFontSize.sp,
                            bottomOverlayHeight = bottomInset,
                            modifier = Modifier.weight(1f)
                        )
                    }
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
                        onSelectAll = {
                            AnalyticsEvents.logButtonClick("select_all", "home")
                            editorController.selectAll()
                        },
                        onDismissKeyboard = { isEditorFocused = false },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .imePadding()
                    )
                } else {
                    Row(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
                        verticalAlignment = Alignment.Bottom,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (hasNotes) {
                            TimerButton(settings = settings, isDark = isDark) {
                                AnalyticsEvents.logButtonClick("set_timer", "home")
                                isEditorFocused = false
                                showingTimer = true
                            }
                        } else {
                            Box(
                                modifier = Modifier
                                    .height(52.dp)
                                    .glassed(Capsule, isDark)
                                    .clickableWithoutRipple {
                                        AnalyticsEvents.logButtonClick("add_sample_text", "home")
                                        scope.launch { settingsService.addSampleText() }
                                    }
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
                        }

                        Spacer(modifier = Modifier.weight(1f))

                        StartButton(
                            isCardsMode = isCardsMode,
                            isEnabled = canStart,
                            isDark = isDark
                        ) {
                            isEditorFocused = false
                            if (isCardsMode) {
                                AnalyticsEvents.logButtonClick("start_cards", "home")
                                showingCards = true
                            } else {
                                AnalyticsEvents.logButtonClick("start_teleprompter", "home")
                                showingTeleprompter = true
                            }
                        }
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
            EditorSettingsView(
                settingsService = settingsService,
                notifications = notifications,
                onDismiss = { showingSettings = false }
            )
        }

        AnimatedVisibility(
            visible = showingTimer,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            TimerSheet(
                settingsService = settingsService,
                onDismiss = { showingTimer = false }
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
                onDismiss = {
                    showingTeleprompter = false
                    requestReviewIfEarned()
                }
            )
        }

        AnimatedVisibility(
            visible = showingCards,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            // The deck as it was opened: edits wait for the next time it's read.
            val deck = remember { cards }
            CueCardsView(
                cards = deck,
                title = settingsService.currentNote?.title ?: "Cards",
                settings = settings,
                onDismiss = { showingCards = false }
            )
        }

        HelpOverlay(
            page = HelpPage.writing(settings.scriptMode),
            visible = showingHelp,
            onDismiss = { showingHelp = false }
        )
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
 * The timer's length, or that none is set, with its clock drawn in the color it
 * starts in. Opens the timer.
 */
@Composable
private fun TimerButton(settings: TeleprompterSettings, isDark: Boolean, onClick: () -> Unit) {
    val duration = settings.activeTimerDurationSeconds
    Row(
        modifier = Modifier
            .height(52.dp)
            .glassed(Capsule, isDark)
            .clickableWithoutRipple(onClick)
            .semantics {
                contentDescription = if (duration > 0) "Timer, ${formatTimer(duration)}" else "Timer, not set"
            }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.Timer,
            contentDescription = null,
            tint = if (duration > 0) {
                settings.activeTimerStyle.normalColor.color(isDark)
            } else {
                AppColors.textSecondary(isDark)
            },
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = if (duration > 0) formatTimer(duration) else "No Timer",
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = if (duration > 0) FontFamily.Monospace else null,
            color = AppColors.textPrimary(isDark)
        )
    }
}

/** Play for the teleprompter, Read Cards for a deck. */
@Composable
private fun StartButton(isCardsMode: Boolean, isEnabled: Boolean, isDark: Boolean, onClick: () -> Unit) {
    val onGreen = if (isDark) Color.Black else Color.White
    val modifier = Modifier
        .height(52.dp)
        .alpha(if (isEnabled) 1f else 0.6f)
        .clickableWithoutRipple { if (isEnabled) onClick() }

    if (isCardsMode) {
        Row(
            modifier = modifier
                .glassed(Capsule, isDark, tint = AppColors.green(isDark))
                .semantics { contentDescription = "Open Cards" }
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.ViewCarousel,
                contentDescription = null,
                tint = onGreen,
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = "Read Cards",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = onGreen,
                maxLines = 1
            )
        }
    } else {
        Box(
            modifier = modifier
                .size(52.dp)
                .glassed(CircleShape, isDark, tint = AppColors.green(isDark)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.PlayArrow,
                contentDescription = "Start Teleprompter",
                tint = onGreen,
                modifier = Modifier.size(20.dp)
            )
        }
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
    cueColor: CueColor,
    isDark: Boolean,
    fontSize: TextUnit,
    bottomOverlayHeight: Dp,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .scriptEdgeFade(isDark = isDark, top = CUE_EDITOR_EDGE_FADE, bottom = EDITOR_BOTTOM_FADE)
    ) {
        if (text.isEmpty()) {
            // Set on the editor's own font and insets, so the first line sits
            // exactly where the caret waiting in front of it does.
            Text(
                text = "Add your script here...\n\nTap Add Cue to drop in a delivery reminder, or type [ to write one yourself.\n\nFor example: Welcome everyone [cue smile and pause]",
                fontSize = fontSize,
                fontWeight = FontWeight.Medium,
                color = AppColors.textSecondary(isDark).copy(alpha = 0.6f),
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .padding(top = CUE_EDITOR_EDGE_FADE)
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
            fontSize = fontSize,
            bottomOverlayHeight = bottomOverlayHeight
        )
    }
}

private val CARD_EDITOR_CORNER_RADIUS = 22.dp

/** The first card starts below the top fade, never inside it. */
private val CARDS_TOP_FADE = 20.dp

/** A card being written, kept by an identity of its own while its text changes. */
private data class EditableCard(val id: Long, val text: String)

/**
 * Cards mode's editor: every card its own page, written on separately, with a
 * button below the last one to start another. A swipe removes a card.
 *
 * The deck is stored as one script with a separator between cards; the
 * separators are only ever written here, never shown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardsEditorView(
    text: String,
    onTextChange: (String) -> Unit,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    controller: CueEditorController,
    cueColor: CueColor,
    isDark: Boolean,
    fontSize: TextUnit,
    /** The characters a card holds before the rest is marked. */
    cardLimit: Int,
    /** Room kept clear below the last card for what floats over the list. */
    bottomInset: Dp,
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var nextId by remember { mutableLongStateOf(0L) }

    fun editable(texts: List<String>): List<EditableCard> =
        texts.map { EditableCard(nextId++, it) }

    var cards by remember { mutableStateOf(editable(CueCards.editableCards(text))) }
    /**
     * The script last written from `cards`, so an edit made here isn't read back
     * in as a whole new deck.
     */
    var writtenText by remember { mutableStateOf(text) }
    var focusedCard by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(text) {
        if (text != writtenText) {
            cards = editable(CueCards.editableCards(text))
            writtenText = text
        }
    }

    LaunchedEffect(focusedCard) {
        val hasFocus = focusedCard != null
        if (isFocused != hasFocus) onFocusChange(hasFocus)
    }

    LaunchedEffect(isFocused) {
        if (!isFocused) {
            focusedCard = null
        } else if (focusedCard == null) {
            focusedCard = cards.lastOrNull()?.id
        }
    }

    fun writeScript() {
        val script = CueCards.script(cards.map { it.text })
        writtenText = script
        if (text != script) onTextChange(script)
    }

    /**
     * Start writing in a new card after the last, or in the last one if it hasn't
     * been written in yet.
     */
    fun addCard() {
        val last = cards.lastOrNull()
        if (last == null || last.text.isNotBlank()) {
            val card = EditableCard(nextId++, "")
            cards = cards + card
            writeScript()
            focusedCard = card.id
        } else {
            focusedCard = last.id
        }
        scope.launch { listState.animateScrollToItem(cards.size) }
    }

    /**
     * Take a card out of the deck. The last one left is emptied instead, so there
     * is always a card to write in.
     */
    fun remove(id: Long) {
        if (focusedCard == id) focusedCard = null
        cards = if (cards.size == 1) editable(listOf("")) else cards.filter { it.id != id }
        writeScript()
    }

    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(top = CARDS_TOP_FADE, bottom = bottomInset + 16.dp),
        modifier = modifier
            .fillMaxSize()
            .imePadding()
            // The bottom fade reaches up past what floats over the list, so a card
            // is gone before it passes behind the controls or the cue bar.
            .scriptEdgeFade(isDark = isDark, top = CARDS_TOP_FADE, bottom = bottomInset)
    ) {
        itemsIndexed(cards, key = { _, card -> card.id }) { index, card ->
            val dismissState = rememberSwipeToDismissBoxState(
                confirmValueChange = { value ->
                    if (value == SwipeToDismissBoxValue.EndToStart) {
                        AnalyticsEvents.logButtonClick("remove_card", "home")
                        remove(card.id)
                        true
                    } else {
                        false
                    }
                }
            )

            SwipeToDismissBox(
                state = dismissState,
                enableDismissFromStartToEnd = false,
                backgroundContent = {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(CARD_EDITOR_CORNER_RADIUS))
                            .background(AppColors.red(isDark))
                            .padding(horizontal = 20.dp),
                        contentAlignment = Alignment.CenterEnd
                    ) {
                        Text(text = "Remove", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                },
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
            ) {
                CardEditorRow(
                    card = card,
                    number = index + 1,
                    isFocused = focusedCard == card.id,
                    onFocusChange = { focused ->
                        if (focused) {
                            focusedCard = card.id
                        } else if (focusedCard == card.id) {
                            focusedCard = null
                        }
                    },
                    onTextChange = { newText ->
                        val position = cards.indexOfFirst { it.id == card.id }
                        if (position != -1 && cards[position].text != newText) {
                            cards = cards.toMutableList().also { it[position] = it[position].copy(text = newText) }
                            writeScript()
                        }
                    },
                    controller = controller,
                    cueColor = cueColor,
                    isDark = isDark,
                    fontSize = fontSize,
                    cardLimit = cardLimit
                )
            }
        }

        item(key = "new-card") {
            val outline = AppColors.textSecondary(isDark).copy(alpha = 0.35f)
            Row(
                modifier = Modifier
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .fillMaxWidth()
                    .height(52.dp)
                    .drawBehind {
                        val radius = CARD_EDITOR_CORNER_RADIUS.toPx()
                        drawRoundRect(
                            color = outline,
                            cornerRadius = CornerRadius(radius, radius),
                            style = Stroke(
                                width = 1.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 6.dp.toPx()))
                            )
                        )
                    }
                    .clickableWithoutRipple {
                        AnalyticsEvents.logButtonClick("insert_card", "home")
                        addCard()
                    },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)
            ) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = null,
                    tint = AppColors.textPrimary(isDark),
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "Create New Card",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )
            }
        }
    }
}

@Composable
private fun CardEditorRow(
    card: EditableCard,
    number: Int,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    onTextChange: (String) -> Unit,
    controller: CueEditorController,
    cueColor: CueColor,
    isDark: Boolean,
    fontSize: TextUnit,
    cardLimit: Int
) {
    val measure = remember(card.text, cardLimit) { CueCards.measure(card.text, cardLimit) }
    val isOver = measure.overflow != null
    // The count only shows once a card is getting close to full.
    val showsCount = measure.length * 5 >= cardLimit * 4
    val secondary = AppColors.textSecondary(isDark)
    val shape = RoundedCornerShape(CARD_EDITOR_CORNER_RADIUS)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(cardBackground(isDark))
            .border(
                width = if (isOver) 1.dp else 0.7.dp,
                color = if (isOver) AppColors.red(isDark).copy(alpha = 0.6f) else secondary.copy(alpha = 0.2f),
                shape = shape
            )
            // A tap on the card around the text still starts writing in it.
            .clickableWithoutRipple { onFocusChange(true) }
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Text(
                text = "Card $number",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = secondary
            )
            Spacer(modifier = Modifier.weight(1f))
            if (showsCount) {
                Text(
                    text = "${measure.length}/$cardLimit",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    color = if (isOver) AppColors.red(isDark) else secondary
                )
            }
        }

        Box(modifier = Modifier.heightIn(min = with(LocalDensity.current) { (fontSize * 3).toDp() })) {
            if (card.text.isEmpty()) {
                // The first card explains the deck. Later ones only ask for the
                // next thought, since by then it's clear what a card is.
                Text(
                    text = if (number == 1) {
                        "One thought per card.\n\nType [ or tap Add Cue for reminders like [cue pause]."
                    } else {
                        "Your next thought…"
                    },
                    fontSize = fontSize,
                    fontWeight = FontWeight.Medium,
                    color = secondary.copy(alpha = 0.6f)
                )
            }

            CueTextEditor(
                text = card.text,
                onTextChange = onTextChange,
                isFocused = isFocused,
                onFocusChange = onFocusChange,
                controller = controller,
                cueColor = cueColor,
                isDark = isDark,
                fontSize = fontSize,
                cardLimit = cardLimit,
                growsWithText = true
            )
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
    var showingHelp by remember { mutableStateOf(false) }
    val dateFormat = remember {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("saved_notes")
    }

    BackHandler(enabled = showingHelp) { showingHelp = false }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            text = "Saved Content",
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

                        HelpButton(page = HelpPage.SAVED_CONTENT, isDark = isDark) { showingHelp = true }
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
                        text = "No Saved Content",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Save your scripts and cards to open them later",
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

        HelpOverlay(page = HelpPage.SAVED_CONTENT, visible = showingHelp, onDismiss = { showingHelp = false })
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
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = note.title,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )

                if (note.mode == ScriptMode.CARDS) {
                    Text(
                        text = "Cards",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.green(isDark),
                        modifier = Modifier
                            .clip(Capsule)
                            .background(AppColors.green(isDark).copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }
            }

            // The start of a note, with card breaks read as spaces.
            Text(
                text = CueCards.removingSeparators(note.content).take(120).replace("\n", " "),
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
