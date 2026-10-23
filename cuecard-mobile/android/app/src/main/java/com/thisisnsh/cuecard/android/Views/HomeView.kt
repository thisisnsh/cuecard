package com.thisisnsh.cuecard.android.views

import com.thisisnsh.cuecard.android.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.thisisnsh.cuecard.android.services.TakesLibrary
import com.thisisnsh.cuecard.android.services.VideoAccess
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
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
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
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.EmphasisStyle
import com.thisisnsh.cuecard.android.models.RichText
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    val versionCounts by settingsService.versionCounts.collectAsState()
    val draftIds by settingsService.draftIds.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()

    var showingSettings by remember { mutableStateOf(false) }
    var showingHelp by remember { mutableStateOf(false) }
    var showingTeleprompter by remember { mutableStateOf(false) }
    var showingCards by remember { mutableStateOf(false) }
    var showingSavedNotes by remember { mutableStateOf(false) }
    var showingVersions by remember { mutableStateOf(false) }
    var showingTakes by remember { mutableStateOf(false) }
    var showingTimer by remember { mutableStateOf(false) }
    var showingSaveDialog by remember { mutableStateOf(false) }
    var saveNoteTitle by remember { mutableStateOf("") }
    var showingMenu by remember { mutableStateOf(false) }
    var showingModeMenu by remember { mutableStateOf(false) }
    var fileErrorMessage by remember { mutableStateOf<String?>(null) }
    /** What's waiting on the user to agree to lose the unsaved script. */
    var confirmingDiscard by remember { mutableStateOf<Discarding?>(null) }
    /** "Saved" shows for a moment after a save, where "Unsaved" was. */
    var showsSaved by remember { mutableStateOf(false) }
    var savedJob by remember { mutableStateOf<Job?>(null) }
    var isEditorFocused by remember { mutableStateOf(false) }
    val editorController = remember { CueEditorController() }

    val hasNotes = notes.trim().isNotEmpty()
    val isCardsMode = settings.scriptMode == ScriptMode.CARDS
    val cards = remember(notes) { CueCards.cards(notes) }
    val canStart = if (isCardsMode) cards.isNotEmpty() else hasNotes

    val currentNote = savedNotes.firstOrNull { it.id == currentNoteId }
    val hasUnsavedChanges = if (currentNote != null) currentNote.content != notes else hasNotes
    /** The open note has older versions to go back to. */
    val hasVersionHistory = currentNoteId?.let { (versionCounts[it] ?: 1) > 1 } ?: false

    /**
     * What the script is filed under for its takes: the note it was opened
     * from, or the ID it will be saved under.
     */
    val scriptId = currentNoteId ?: draftIds[settings.scriptMode]
    val takesLibrary = remember { TakesLibrary(context) }
    val takes by takesLibrary.takes.collectAsState()
    val hasSessions by takesLibrary.hasSessions.collectAsState()
    val videoAccess by takesLibrary.status.collectAsState()
    /**
     * The videos recorded while the teleprompter or cards were open on the
     * script. Once it has been, and before the videos can be read, a button to
     * go find them.
     */
    val showsTakes = takes.isNotEmpty() ||
        (hasSessions && (videoAccess == VideoAccess.NOT_DETERMINED || videoAccess == VideoAccess.LIMITED))

    DisposableEffect(takesLibrary) {
        onDispose { takesLibrary.close() }
    }

    LaunchedEffect(scriptId) {
        scriptId?.let { takesLibrary.load(it) }
    }

    // Coming back to the app, a video may have been recorded or deleted.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) scope.launch { takesLibrary.reload() }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

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

    fun flashSaved() {
        showsSaved = true
        savedJob?.cancel()
        savedJob = scope.launch {
            delay(1000)
            showsSaved = false
        }
    }

    /** Save to the open note, or ask for a title if the script isn't one yet. */
    fun save() {
        AnalyticsEvents.logButtonClick("save_note", "home")
        if (currentNoteId != null) {
            scope.launch {
                if (settingsService.saveChangesToCurrentNote()) {
                    flashSaved()
                } else {
                    fileErrorMessage = context.getString(R.string.note_couldnt_be_saved)
                }
            }
        } else {
            saveNoteTitle = ""
            showingSaveDialog = true
        }
    }

    fun importNote(title: String, content: String) {
        scope.launch {
            if (!settingsService.importNote(title, content)) {
                fileErrorMessage = context.getString(R.string.file_opened_not_saved)
            }
        }
    }

    // MARK: - Files

    /** Open a text file in the editor, kept as a new saved note. */
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val text = withContext(Dispatchers.IO) { ScriptFile.readText(context, uri) }
                if (text.trim().isEmpty()) {
                    fileErrorMessage = context.getString(R.string.file_empty)
                    return@launch
                }
                val title = ScriptFile.title(context, uri)
                val content = TeleprompterParser.normalizingTags(text)
                // Asked only once a file is picked, so cancelling the picker never prompts.
                if (hasUnsavedChanges) {
                    confirmingDiscard = Discarding.Import(title, content)
                } else {
                    importNote(title, content)
                }
            } catch (e: ScriptFile.FileTooLarge) {
                fileErrorMessage = context.getString(R.string.file_too_large)
                AnalyticsEvents.logEvent(
                    "file_too_large",
                    mapOf("source" to "import", "size_mb" to e.size / (1024 * 1024))
                )
            } catch (e: Exception) {
                fileErrorMessage = context.getString(R.string.file_unreadable)
            }
        }
    }

    /**
     * Hand the script to the share sheet as it would be written to a file, with
     * cues in `[cue …]` form.
     */
    fun shareScript() {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, currentNote?.title ?: context.getString(R.string.speech))
            .putExtra(Intent.EXTRA_TEXT, TeleprompterParser.normalizingTags(notes))
        try {
            context.startActivity(Intent.createChooser(send, null))
        } catch (e: Exception) {
            // More text than one app can hand to another.
            fileErrorMessage = context.getString(R.string.script_too_long_to_share)
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
        enabled = showingSettings || showingSavedNotes || showingVersions || showingTeleprompter ||
            showingTimer || showingHelp || showingTakes || isEditorFocused
    ) {
        when {
            showingHelp -> showingHelp = false
            showingTakes -> showingTakes = false
            showingTeleprompter -> showingTeleprompter = false
            showingSettings -> showingSettings = false
            showingTimer -> showingTimer = false
            showingVersions -> showingVersions = false
            showingSavedNotes -> showingSavedNotes = false
            isEditorFocused -> isEditorFocused = false
        }
    }

    val modeDescription = stringResource(R.string.mode_description, settings.scriptMode.displayName)

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
                                    .semantics { contentDescription = modeDescription }
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
                        // Only once the note has an older version to go back to.
                        if (hasVersionHistory) {
                            Icon(
                                imageVector = Icons.Filled.History,
                                contentDescription = stringResource(R.string.version_history),
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .size(20.dp)
                                    .clickableWithoutRipple {
                                        AnalyticsEvents.logButtonClick("version_history", "home")
                                        isEditorFocused = false
                                        showingVersions = true
                                    }
                            )
                        }

                        Box {
                            Icon(
                                imageVector = Icons.Filled.MoreVert,
                                contentDescription = stringResource(R.string.more),
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
                                if (hasUnsavedChanges) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.save)) },
                                        onClick = {
                                            showingMenu = false
                                            save()
                                        }
                                    )

                                    HorizontalDivider()
                                }

                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.new_note)) },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("new_note", "home")
                                        if (hasUnsavedChanges) {
                                            confirmingDiscard = Discarding.New
                                        } else {
                                            scope.launch { settingsService.createNewNote() }
                                        }
                                    }
                                )

                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.open)) },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("saved_notes", "home")
                                        isEditorFocused = false
                                        showingSavedNotes = true
                                    }
                                )

                                HorizontalDivider()

                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.import_file)) },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("import_file", "home")
                                        importLauncher.launch(ScriptFile.importableMimeTypes)
                                    }
                                )

                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.share)) },
                                    enabled = hasNotes,
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("share", "home")
                                        shareScript()
                                    }
                                )
                            }
                        }

                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = stringResource(R.string.settings),
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
                    Box(modifier = Modifier.weight(1f)) {
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
                                bottomInset = bottomInset
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
                                bottomOverlayHeight = bottomInset
                            )
                        }
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
                        onFormat = { style ->
                            AnalyticsEvents.logButtonClick(
                                if (style == EmphasisStyle.BOLD) "format_bold" else "format_italic", "home"
                            )
                            editorController.toggle(style)
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
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // What's written since the last save is kept on this device,
                        // but isn't in Saved Notes until it's saved. Laid over the
                        // bottom of the script, so nothing moves when this comes or goes.
                        SaveStatus(
                            isUnsaved = hasUnsavedChanges,
                            showsSaved = showsSaved,
                            isDark = isDark,
                            onSave = ::save
                        )

                        Row(
                            modifier = Modifier.fillMaxWidth(),
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
                                        text = stringResource(R.string.add_sample_text),
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = AppColors.textPrimary(isDark)
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.weight(1f))

                            AnimatedVisibility(
                                visible = showsTakes,
                                enter = fadeIn() + scaleIn(),
                                exit = fadeOut() + scaleOut()
                            ) {
                                TakesButton(count = takes.size, isDark = isDark) {
                                    AnalyticsEvents.logButtonClick("takes", "home")
                                    isEditorFocused = false
                                    showingTakes = true
                                }
                            }

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
        }

        // MARK: - Presentations

        AnimatedVisibility(
            visible = showingSavedNotes,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            SavedNotesView(
                settingsService = settingsService,
                isDark = isDark,
                onDismiss = { showingSavedNotes = false },
                onLoad = { note ->
                    scope.launch { settingsService.loadNote(note) }
                    showingSavedNotes = false
                }
            )
        }

        AnimatedVisibility(
            visible = showingVersions,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            // The note the history was opened for, kept while the sheet slides away.
            val noteId = remember { currentNoteId }
            if (noteId != null) {
                NoteVersionsView(
                    noteId = noteId,
                    settingsService = settingsService,
                    onDismiss = { showingVersions = false }
                )
            }
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
            // The script it was opened on, kept while it slides away.
            val openScriptId = remember { scriptId }
            TeleprompterView(
                content = content,
                settings = settings,
                scriptId = openScriptId,
                onDismiss = {
                    showingTeleprompter = false
                    // Anything recorded while it was open is a take now.
                    scope.launch { takesLibrary.reload() }
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
            val openScriptId = remember { scriptId }
            CueCardsView(
                cards = deck,
                settings = settings,
                scriptId = openScriptId,
                onDismiss = {
                    showingCards = false
                    scope.launch { takesLibrary.reload() }
                }
            )
        }

        AnimatedVisibility(
            visible = showingTakes,
            enter = scaleIn(initialScale = 0.9f) + fadeIn(),
            exit = scaleOut(targetScale = 0.9f) + fadeOut()
        ) {
            TakesView(
                library = takesLibrary,
                scriptTitle = currentNote?.title,
                onDismiss = { showingTakes = false }
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
            title = stringResource(R.string.save_note),
            message = stringResource(R.string.enter_title),
            confirmLabel = stringResource(R.string.save),
            initialValue = saveNoteTitle,
            isDark = isDark,
            onDismiss = { showingSaveDialog = false },
            onConfirm = { title ->
                showingSaveDialog = false
                if (title.trim().isNotEmpty()) {
                    scope.launch {
                        if (settingsService.saveCurrentNote(title.trim())) {
                            flashSaved()
                        } else {
                            fileErrorMessage = context.getString(R.string.note_couldnt_be_saved)
                        }
                    }
                }
            }
        )
    }

    confirmingDiscard?.let { discarding ->
        ConfirmDialog(
            title = stringResource(R.string.discard_unsaved_changes),
            message = stringResource(R.string.unsaved_will_be_lost),
            confirmLabel = stringResource(R.string.discard_changes),
            isDark = isDark,
            onDismiss = { confirmingDiscard = null },
            onConfirm = {
                confirmingDiscard = null
                when (discarding) {
                    Discarding.New -> scope.launch { settingsService.createNewNote() }
                    is Discarding.Import -> importNote(discarding.title, discarding.content)
                }
            }
        )
    }

    fileErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { fileErrorMessage = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { fileErrorMessage = null }) {
                    Text(stringResource(R.string.ok), color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

/** What replaces the script in the editor once its unsaved changes are let go. */
private sealed class Discarding {
    data object New : Discarding()
    data class Import(val title: String, val content: String) : Discarding()
}

/**
 * "Unsaved" while there are changes to save, which a tap saves, then "Saved"
 * for a moment once they are.
 */
@Composable
private fun SaveStatus(
    isUnsaved: Boolean,
    showsSaved: Boolean,
    isDark: Boolean,
    onSave: () -> Unit,
    modifier: Modifier = Modifier
) {
    // What it last said, to go on saying it while it fades out.
    val unsaved = stringResource(R.string.unsaved)
    val saved = stringResource(R.string.saved)
    val savesChanges = stringResource(R.string.saves_your_changes)
    var label by remember { mutableStateOf(unsaved) }
    val current = when {
        isUnsaved -> unsaved
        showsSaved -> saved
        else -> null
    }
    if (current != null) SideEffect { label = current }

    AnimatedVisibility(
        visible = current != null,
        enter = fadeIn(tween(200)),
        exit = fadeOut(tween(200)),
        modifier = modifier
    ) {
        Text(
            text = current ?: label,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = AppColors.textSecondary(isDark),
            modifier = Modifier
                .glassed(Capsule, isDark)
                .clickableWithoutRipple { if (isUnsaved) onSave() }
                .semantics { if (isUnsaved) onClick(label = savesChanges, action = null) }
                .padding(horizontal = 14.dp, vertical = 6.dp)
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
    val timerDescription = if (duration > 0) {
        stringResource(R.string.timer_description, formatTimer(duration))
    } else {
        stringResource(R.string.timer_not_set)
    }
    Row(
        modifier = Modifier
            .height(52.dp)
            .glassed(Capsule, isDark)
            .clickableWithoutRipple(onClick)
            .semantics {
                contentDescription = timerDescription
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
            text = if (duration > 0) formatTimer(duration) else stringResource(R.string.no_timer),
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
    val openCards = stringResource(R.string.open_cards)
    val modifier = Modifier
        .height(52.dp)
        .alpha(if (isEnabled) 1f else 0.6f)
        .clickableWithoutRipple { if (isEnabled) onClick() }

    if (isCardsMode) {
        Row(
            modifier = modifier
                .glassed(Capsule, isDark, tint = AppColors.green(isDark))
                .semantics { contentDescription = openCards }
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
                text = stringResource(R.string.read_cards),
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
                contentDescription = stringResource(R.string.start_teleprompter),
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
                text = stringResource(R.string.editor_placeholder),
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
                        Text(text = stringResource(R.string.remove), color = Color.White, fontWeight = FontWeight.SemiBold)
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
                    text = stringResource(R.string.create_new_card),
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
                text = stringResource(R.string.card_number, number),
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
                        stringResource(R.string.first_card_placeholder)
                    } else {
                        stringResource(R.string.next_card_placeholder)
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
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    decorationBox = { field ->
                        if (value.isEmpty()) {
                            Text(stringResource(R.string.note_title), fontSize = 16.sp, color = AppColors.textSecondary(isDark))
                        }
                        field()
                    }
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
                Text(stringResource(R.string.cancel), color = AppColors.blue(isDark))
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
    settingsService: SettingsService,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onLoad: (SavedNote) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val savedNotes by settingsService.savedNotes.collectAsState()
    val versionCounts by settingsService.versionCounts.collectAsState()
    val currentNoteId by settingsService.currentNoteId.collectAsState()
    val hasNotesFolder by settingsService.hasNotesFolder.collectAsState()
    val notesFolderName by settingsService.notesFolderName.collectAsState()
    val oversizedFiles by settingsService.notesFolderOversizedFiles.collectAsState()
    val undeletedFiles by settingsService.notesFolderUndeletedFiles.collectAsState()

    var noteToRename by remember { mutableStateOf<SavedNote?>(null) }
    /** A note waiting on the user to agree to lose the unsaved script it replaces. */
    var noteToOpen by remember { mutableStateOf<SavedNote?>(null) }
    var showingMenu by remember { mutableStateOf(false) }
    var showingDeleteAll by remember { mutableStateOf(false) }
    var showingStopFolder by remember { mutableStateOf(false) }
    var showingStopFolderFailed by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    /** The mode whose notes are listed. Starts on the home screen's mode. */
    var modeFilter by remember { mutableStateOf(settingsService.settings.value.scriptMode) }
    val dateFormat = remember {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    }

    // Saved notes of the chosen mode, newest first, narrowed to those whose
    // title or text match the search.
    val trimmed = query.trim()
    val notes = remember(savedNotes, trimmed, modeFilter) {
        val sorted = savedNotes.filter { it.mode == modeFilter }.sortedByDescending { it.updatedAt }
        if (trimmed.isEmpty()) {
            sorted
        } else {
            sorted.filter {
                it.title.contains(trimmed, ignoreCase = true) ||
                    CueCards.removingSeparators(it.content).contains(trimmed, ignoreCase = true)
            }
        }
    }

    // Why deleting notes left files behind in the notes folder.
    fun undeletedFilesMessage(count: Int): String =
        notesFolderName?.let {
            context.getString(if (count == 1) R.string.undeleted_file_in_folder else R.string.undeleted_files_in_folder, it)
        } ?: context.getString(if (count == 1) R.string.undeleted_file_later else R.string.undeleted_files_later)

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("saved_notes")
        settingsService.syncNotesFolder()
    }

    val folderPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            try {
                settingsService.chooseNotesFolder(uri)
            } catch (e: Exception) {
                errorMessage = context.getString(R.string.folder_unusable)
            }
        }
    }

    val storageNote: @Composable (Modifier) -> Unit = { modifier ->
        StorageNote(
            folderName = notesFolderName,
            hasFolder = hasNotesFolder,
            oversizedFiles = oversizedFiles,
            undeletedFiles = undeletedFiles,
            isDark = isDark,
            modifier = modifier
        )
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                navigationIcon = {
                    Box {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = stringResource(R.string.more),
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .size(20.dp)
                                .clickableWithoutRipple { showingMenu = true }
                        )

                        DropdownMenu(
                            expanded = showingMenu,
                            onDismissRequest = { showingMenu = false },
                            containerColor = AppColors.background(isDark)
                        ) {
                            DropdownMenuItem(
                                text = { Text(if (hasNotesFolder) stringResource(R.string.change_notes_folder) else stringResource(R.string.choose_notes_folder)) },
                                onClick = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("choose_notes_folder", "saved_notes")
                                    folderPicker.launch(null)
                                }
                            )

                            if (hasNotesFolder) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.stop_using_folder)) },
                                    onClick = {
                                        showingMenu = false
                                        AnalyticsEvents.logButtonClick("stop_notes_folder", "saved_notes")
                                        showingStopFolder = true
                                    }
                                )
                            }

                            HorizontalDivider()

                            DropdownMenuItem(
                                text = {
                                    Text(
                                        text = stringResource(R.string.delete_all),
                                        color = AppColors.red(isDark)
                                            .copy(alpha = if (savedNotes.isEmpty()) 0.4f else 1f)
                                    )
                                },
                                enabled = savedNotes.isNotEmpty(),
                                onClick = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("delete_all_notes", "saved_notes")
                                    showingDeleteAll = true
                                }
                            )
                        }
                    }
                },
                title = {
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(
                            text = stringResource(R.string.saved_notes),
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                        if (savedNotes.isNotEmpty()) {
                            Text(
                                text = pluralStringResource(R.plurals.note_count, savedNotes.size, savedNotes.size),
                                fontSize = 11.sp,
                                color = AppColors.textSecondary(isDark)
                            )
                        }
                    }
                },
                actions = {
                    Text(
                        text = stringResource(R.string.done),
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
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(modifier = Modifier.weight(1f))
                Icon(
                    imageVector = Icons.Filled.Folder,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier.size(48.dp)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = stringResource(R.string.nothing_saved_yet),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = stringResource(R.string.save_scripts_to_open_later),
                    fontSize = 15.sp,
                    color = AppColors.textSecondary(isDark),
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.weight(1f))
                storageNote(Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 16.dp))
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                SearchField(
                    query = query,
                    onQueryChange = { query = it },
                    isDark = isDark,
                    placeholder = stringResource(R.string.search)
                )

                val modeLabel = stringResource(R.string.mode)
                SegmentedPicker(
                    options = ScriptMode.entries.map { it.displayName },
                    selected = modeFilter.ordinal,
                    isDark = isDark,
                    onSelect = { modeFilter = ScriptMode.entries[it] },
                    modifier = Modifier
                        .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp)
                        .semantics { contentDescription = modeLabel }
                )

                if (notes.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = if (trimmed.isEmpty()) {
                                stringResource(R.string.nothing_saved_yet)
                            } else {
                                stringResource(R.string.no_results_for, trimmed)
                            },
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                    }
                    return@Column
                }

                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(items = notes, key = { it.id }) { note ->
                        // When a note was last saved, and how many versions it has.
                        val versions = versionCounts[note.id] ?: 1
                        SavedNoteRow(
                            note = note,
                            isCurrent = note.id == currentNoteId,
                            isDark = isDark,
                            detail = "${dateFormat.format(Date(note.updatedAt))} · " +
                                pluralStringResource(R.plurals.version_count, versions, versions),
                            onLoad = {
                                AnalyticsEvents.logButtonClick("load_note", "saved_notes")
                                // Opening replaces the script of the note's own mode.
                                if (settingsService.hasUnsavedChanges(note.mode)) {
                                    noteToOpen = note
                                } else {
                                    onLoad(note)
                                }
                            },
                            onRename = {
                                AnalyticsEvents.logButtonClick("rename_note", "saved_notes")
                                noteToRename = note
                            },
                            onDelete = {
                                AnalyticsEvents.logButtonClick("delete_note", "saved_notes")
                                scope.launch {
                                    if (!settingsService.deleteNote(note.id)) {
                                        errorMessage = context.getString(R.string.note_was_deleted, undeletedFilesMessage(1))
                                    }
                                }
                            }
                        )
                    }

                    // At the end of the list, so it never covers a note.
                    item(key = "storage-note") {
                        storageNote(Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 16.dp))
                    }
                }
            }
        }
    }

    noteToOpen?.let { note ->
        ConfirmDialog(
            title = stringResource(R.string.discard_unsaved_changes),
            message = stringResource(R.string.unsaved_will_be_lost),
            confirmLabel = stringResource(R.string.discard_changes),
            isDark = isDark,
            onDismiss = { noteToOpen = null },
            onConfirm = {
                noteToOpen = null
                onLoad(note)
            }
        )
    }

    noteToRename?.let { note ->
        TitleDialog(
            title = stringResource(R.string.rename_note),
            message = stringResource(R.string.enter_new_title),
            confirmLabel = stringResource(R.string.rename),
            initialValue = note.title,
            isDark = isDark,
            onDismiss = { noteToRename = null },
            onConfirm = { title ->
                if (title.trim().isNotEmpty()) {
                    scope.launch {
                        if (!settingsService.updateNote(note.id, title = title.trim())) {
                            errorMessage = context.getString(R.string.note_couldnt_be_renamed)
                        }
                    }
                }
                noteToRename = null
            }
        )
    }

    if (showingStopFolder) {
        ConfirmDialog(
            title = stringResource(R.string.stop_using_notes_folder),
            message = notesFolderName?.let { stringResource(R.string.stop_folder_message, it) }
                ?: stringResource(R.string.notes_stay_on_device),
            confirmLabel = stringResource(R.string.stop_using_folder),
            isDark = isDark,
            onDismiss = { showingStopFolder = false },
            onConfirm = {
                showingStopFolder = false
                scope.launch {
                    if (!settingsService.stopUsingNotesFolder()) showingStopFolderFailed = true
                }
            }
        )
    }

    if (showingStopFolderFailed) {
        AlertDialog(
            onDismissRequest = { showingStopFolderFailed = false },
            title = { Text(stringResource(R.string.couldnt_delete_note_files)) },
            text = {
                Text(
                    notesFolderName?.let {
                        stringResource(R.string.stop_folder_failed, it)
                    } ?: stringResource(R.string.stop_folder_unreachable)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showingStopFolderFailed = false
                    scope.launch { settingsService.stopUsingNotesFolderKeepingFiles() }
                }) {
                    Text(stringResource(R.string.stop_anyway), color = AppColors.blue(isDark))
                }
            },
            dismissButton = {
                TextButton(onClick = { showingStopFolderFailed = false }) {
                    Text(stringResource(R.string.keep_using_folder), color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }

    if (showingDeleteAll) {
        ConfirmDialog(
            title = stringResource(R.string.delete_all_saved_notes),
            message = notesFolderName?.let { stringResource(R.string.delete_all_message_folder, it) }
                ?: stringResource(R.string.delete_all_message),
            confirmLabel = stringResource(R.string.delete_all),
            isDark = isDark,
            onDismiss = { showingDeleteAll = false },
            onConfirm = {
                showingDeleteAll = false
                scope.launch {
                    val count = savedNotes.size
                    if (!settingsService.deleteAllNotes()) {
                        errorMessage = context.getString(R.string.notes_were_deleted, undeletedFilesMessage(count))
                    }
                }
            }
        )
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) {
                    Text(stringResource(R.string.ok), color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

/** A dialog asking before something that can't be taken back. */
@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel, color = AppColors.red(isDark))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.cancel), color = AppColors.blue(isDark))
            }
        },
        containerColor = AppColors.background(isDark)
    )
}

/** Where saved notes are kept, shown whether or not there are any. */
@Composable
private fun StorageNote(
    folderName: String?,
    hasFolder: Boolean,
    oversizedFiles: List<String>,
    undeletedFiles: List<String>,
    isDark: Boolean,
    modifier: Modifier = Modifier
) {
    // Files in the notes folder that were too large to bring in, if any.
    val warning = when (oversizedFiles.size) {
        0 -> null
        1 -> stringResource(R.string.oversized_file, oversizedFiles.first())
        else -> stringResource(R.string.oversized_files, oversizedFiles.size)
    }

    // Files of deleted notes still in the notes folder, if any.
    val undeletedWarning = when (undeletedFiles.size) {
        0 -> null
        1 -> stringResource(R.string.undeleted_file_warning, undeletedFiles.first())
        else -> stringResource(R.string.undeleted_files_warning, undeletedFiles.size)
    }

    // Notes never leave the device, so the lock stays whatever the folder.
    val storage = when {
        folderName != null -> stringResource(R.string.storage_folder, folderName)
        hasFolder -> stringResource(R.string.storage_folder_unreachable)
        else -> stringResource(R.string.storage_device, "⋮")
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        listOfNotNull(warning, undeletedWarning).forEach {
            StorageLine(text = it, icon = Icons.Filled.Warning, color = AppColors.yellow(isDark))
        }
        StorageLine(text = storage, icon = Icons.Filled.Lock, color = AppColors.textSecondary(isDark))
    }
}

@Composable
private fun StorageLine(text: String, icon: ImageVector, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier
                .padding(top = 2.dp)
                .size(12.dp)
        )
        Text(
            text = text,
            fontSize = 12.sp,
            color = color,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f, fill = false)
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
    /** The note open in the editor. */
    isCurrent: Boolean,
    isDark: Boolean,
    detail: String,
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
                    text = if (isRename) stringResource(R.string.rename) else stringResource(R.string.delete),
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
                    color = AppColors.textPrimary(isDark),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )

                // The note open in the editor.
                if (isCurrent) {
                    Text(
                        text = stringResource(R.string.current),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.blue(isDark),
                        maxLines = 1,
                        modifier = Modifier
                            .clip(Capsule)
                            .background(AppColors.blue(isDark).copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }
            }

            // The start of a note, with card breaks read as spaces and emphasis
            // markers left out.
            Text(
                text = RichText.plain(CueCards.removingSeparators(note.content)).take(120).replace("\n", " "),
                fontSize = 15.sp,
                color = AppColors.textSecondary(isDark),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            Text(
                text = detail,
                fontSize = 12.sp,
                color = AppColors.textSecondary(isDark).copy(alpha = 0.7f)
            )
        }
    }
}
