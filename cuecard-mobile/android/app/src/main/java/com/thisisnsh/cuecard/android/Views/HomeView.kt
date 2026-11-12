package com.thisisnsh.cuecard.android.views

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.android.play.core.review.ReviewManagerFactory
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.EmphasisStyle
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.modifiers.scriptEdgeFade
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.ReviewPromptService
import com.thisisnsh.cuecard.android.services.SavedNote
import com.thisisnsh.cuecard.android.services.ScriptImages
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TakesLibrary
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import com.thisisnsh.cuecard.android.services.VideoAccess
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val HOME_SCREEN = "home"

/** The height of the controls row: the play button and the timer beside it. */
private val CONTROLS_ROW_HEIGHT = 52.dp

/** The status line at the bottom edge, below the controls. */
private val STATUS_HEIGHT = 22.dp

/**
 * How much of the editor's bottom the controls cover: the row, the gap above
 * it, and the status line below. The script keeps this much room clear so its
 * last line never rests underneath them.
 */
private val CONTROLS_HEIGHT = CONTROLS_ROW_HEIGHT + 12.dp + 8.dp + STATUS_HEIGHT

/**
 * The bottom fade reaches up past the floating controls, so a line is gone
 * before it can pass behind them.
 */
private val EDITOR_BOTTOM_FADE = 72.dp

/** The most characters of the title the status line shows. */
private const val FOOTER_TITLE_LIMIT = 20

/**
 * The editor, opened from the library on one script: written in its mode,
 * played from here, and saved back to the library.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    onBack: () -> Unit
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

    var showingSettings by remember { mutableStateOf(false) }
    var showingHelp by remember { mutableStateOf(false) }
    var showingTeleprompter by remember { mutableStateOf(false) }
    var showingCards by remember { mutableStateOf(false) }
    var showingVersions by remember { mutableStateOf(false) }
    var showingTakes by remember { mutableStateOf(false) }
    var showingTimer by remember { mutableStateOf(false) }
    var showingSaveDialog by remember { mutableStateOf(false) }
    var showingSaveAsNew by remember { mutableStateOf(false) }
    var showingRename by remember { mutableStateOf(false) }
    var showingMenu by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    /** "Saved" shows for a moment after a save, in the status at the bottom. */
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

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(HOME_SCREEN)
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

    /**
     * Save to the open note, or ask for a title if the script isn't one yet.
     * `button` says which of the save buttons was used.
     */
    fun save(button: String) {
        AnalyticsEvents.logButtonClick(button, HOME_SCREEN)
        isEditorFocused = false
        if (currentNoteId != null) {
            scope.launch {
                if (settingsService.saveChangesToCurrentNote()) {
                    flashSaved()
                } else {
                    errorMessage = context.getString(R.string.note_couldnt_be_saved)
                }
            }
        } else {
            showingSaveDialog = true
        }
    }

    /** Keep the images picked from the gallery and place them at the caret. */
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(maxItems = 10)
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        editorController.beginAddingImages()
        scope.launch {
            val names = withContext(Dispatchers.IO) { uris.mapNotNull { ScriptImages.add(context, it) } }
            if (names.size < uris.size) {
                errorMessage = context.getString(R.string.image_not_added)
            }
            editorController.insertImages(names)
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
        enabled = showingSettings || showingVersions || showingTeleprompter || showingCards ||
            showingTimer || showingHelp || showingTakes || isEditorFocused
    ) {
        when {
            showingHelp -> showingHelp = false
            showingTakes -> showingTakes = false
            showingTeleprompter -> showingTeleprompter = false
            showingCards -> showingCards = false
            showingSettings -> showingSettings = false
            showingTimer -> showingTimer = false
            showingVersions -> showingVersions = false
            isEditorFocused -> isEditorFocused = false
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                TopAppBar(
                    navigationIcon = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.library),
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(horizontal = 12.dp)
                                .size(22.dp)
                                .clickableWithoutRipple {
                                    AnalyticsEvents.logButtonClick("editor_back", HOME_SCREEN)
                                    isEditorFocused = false
                                    onBack()
                                }
                        )
                    },
                    title = {},
                    actions = {
                        // Save, beside the options, while there are changes to save.
                        AnimatedVisibility(visible = hasUnsavedChanges, enter = fadeIn(), exit = fadeOut()) {
                            val savesChanges = stringResource(R.string.saves_your_changes)
                            Text(
                                text = stringResource(R.string.save),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.textPrimary(isDark),
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .clickableWithoutRipple { save("save_note_top") }
                                    .semantics { onClick(label = savesChanges, action = null) }
                                    .padding(horizontal = 6.dp, vertical = 8.dp)
                            )
                        }

                        Box {
                            Icon(
                                imageVector = Icons.Filled.MoreVert,
                                contentDescription = stringResource(R.string.script_options),
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .size(20.dp)
                                    .clickableWithoutRipple {
                                        AnalyticsEvents.logButtonClick("editor_menu", HOME_SCREEN)
                                        showingMenu = true
                                    }
                            )

                            DropdownMenu(
                                expanded = showingMenu,
                                onDismissRequest = { showingMenu = false },
                                containerColor = AppColors.background(isDark)
                            ) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.save)) },
                                    enabled = hasUnsavedChanges,
                                    onClick = {
                                        showingMenu = false
                                        save("save_note_menu")
                                    }
                                )
                                // With no saved script open, Save asks for a title already.
                                if (currentNoteId != null) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.save_as_new)) },
                                        enabled = hasNotes,
                                        onClick = {
                                            showingMenu = false
                                            AnalyticsEvents.logButtonClick("save_as_new_menu", HOME_SCREEN)
                                            isEditorFocused = false
                                            showingSaveAsNew = true
                                        }
                                    )
                                }
                                if (hasVersionHistory) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.version_history)) },
                                        onClick = {
                                            showingMenu = false
                                            AnalyticsEvents.logButtonClick("version_history_menu", HOME_SCREEN)
                                            isEditorFocused = false
                                            showingVersions = true
                                        }
                                    )
                                }
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
                                    AnalyticsEvents.logButtonClick("settings", HOME_SCREEN)
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

                // What floats over the bottom of the script: the cue bar while
                // writing, the timer and Play otherwise, with the script's status
                // below them at the bottom edge.
                if (isEditorFocused) {
                    CueBar(
                        isDark = isDark,
                        onAddCue = {
                            AnalyticsEvents.logButtonClick("insert_cue", HOME_SCREEN)
                            editorController.insertCue()
                        },
                        // Anchors are for jumping through the teleprompter;
                        // cards are turned one at a time.
                        onAddAnchor = if (isCardsMode) null else {
                            {
                                AnalyticsEvents.logButtonClick("insert_anchor", HOME_SCREEN)
                                editorController.insertAnchor()
                            }
                        },
                        onAddImage = {
                            AnalyticsEvents.logButtonClick("insert_image", HOME_SCREEN)
                            imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                        onFormat = { style ->
                            AnalyticsEvents.logButtonClick(
                                if (style == EmphasisStyle.BOLD) "format_bold" else "format_italic", HOME_SCREEN
                            )
                            editorController.toggle(style)
                        },
                        onDismissKeyboard = {
                            AnalyticsEvents.logButtonClick("hide_keyboard", HOME_SCREEN)
                            isEditorFocused = false
                        },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .imePadding()
                    )
                } else {
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .widthIn(max = 680.dp)
                            .fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            if (hasNotes) {
                                // The timer on the left; Takes and Play on the right.
                                TimerButton(settings = settings, isDark = isDark) {
                                    AnalyticsEvents.logButtonClick("set_timer", HOME_SCREEN)
                                    isEditorFocused = false
                                    showingTimer = true
                                }

                                Spacer(modifier = Modifier.weight(1f))

                                AnimatedVisibility(
                                    visible = showsTakes,
                                    enter = fadeIn() + scaleIn(),
                                    exit = fadeOut() + scaleOut()
                                ) {
                                    TakesButton(count = takes.size, isDark = isDark) {
                                        AnalyticsEvents.logButtonClick("takes", HOME_SCREEN)
                                        isEditorFocused = false
                                        showingTakes = true
                                    }
                                }

                                StartButton(isCardsMode = isCardsMode, isEnabled = canStart, isDark = isDark) {
                                    isEditorFocused = false
                                    if (isCardsMode) {
                                        AnalyticsEvents.logButtonClick("start_cards", HOME_SCREEN)
                                        showingCards = true
                                    } else {
                                        AnalyticsEvents.logButtonClick("start_teleprompter", HOME_SCREEN)
                                        showingTeleprompter = true
                                    }
                                }
                            } else {
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(CONTROLS_ROW_HEIGHT)
                                        .glassed(Capsule, isDark)
                                        .clickableWithoutRipple {
                                            AnalyticsEvents.logButtonClick("add_sample_text", HOME_SCREEN)
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
                        }

                        StatusFooter(
                            note = currentNote,
                            isCardsMode = isCardsMode,
                            isUnsaved = hasUnsavedChanges,
                            showsSaved = showsSaved,
                            version = currentNoteId?.let { versionCounts[it] ?: 1 },
                            isDark = isDark,
                            onRename = {
                                AnalyticsEvents.logButtonClick("rename_note", HOME_SCREEN)
                                showingRename = true
                            },
                            onVersions = {
                                AnalyticsEvents.logButtonClick("version_history_footer", HOME_SCREEN)
                                showingVersions = true
                            }
                        )
                    }
                }
            }
        }

        // MARK: - Presentations

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
            SettingsView(
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
        TextFieldDialog(
            title = stringResource(R.string.save_note),
            message = stringResource(R.string.enter_title),
            confirmLabel = stringResource(R.string.save),
            initialValue = "",
            placeholder = stringResource(R.string.note_title),
            isDark = isDark,
            maxLength = SavedNote.TITLE_LIMIT,
            onDismiss = {
                AnalyticsEvents.logButtonClick("save_dialog_cancel", HOME_SCREEN)
                showingSaveDialog = false
            },
            onConfirm = { title ->
                AnalyticsEvents.logButtonClick("save_dialog_save", HOME_SCREEN)
                showingSaveDialog = false
                if (title.isNotBlank()) {
                    scope.launch {
                        if (settingsService.saveCurrentNote(title.trim())) {
                            flashSaved()
                        } else {
                            errorMessage = context.getString(R.string.note_couldnt_be_saved)
                        }
                    }
                }
            }
        )
    }

    if (showingSaveAsNew) {
        // Named to start with after the one open, which stays as it was last saved.
        val copyTitle = currentNote?.let { SavedNote.limitedTitle(stringResource(R.string.title_copy, it.title)) }.orEmpty()
        TextFieldDialog(
            title = stringResource(R.string.save_as_new),
            message = stringResource(R.string.save_as_new_message, currentNote?.title.orEmpty()),
            confirmLabel = stringResource(R.string.save),
            initialValue = copyTitle,
            placeholder = stringResource(R.string.note_title),
            isDark = isDark,
            maxLength = SavedNote.TITLE_LIMIT,
            onDismiss = {
                AnalyticsEvents.logButtonClick("save_as_new_cancel", HOME_SCREEN)
                showingSaveAsNew = false
            },
            onConfirm = { title ->
                AnalyticsEvents.logButtonClick("save_as_new_save", HOME_SCREEN)
                showingSaveAsNew = false
                if (title.isNotBlank()) {
                    scope.launch {
                        if (settingsService.saveCurrentNoteAsNew(title.trim())) {
                            flashSaved()
                        } else {
                            errorMessage = context.getString(R.string.note_couldnt_be_saved)
                        }
                    }
                }
            }
        )
    }

    if (showingRename && currentNote != null) {
        TextFieldDialog(
            title = stringResource(R.string.rename_script),
            message = null,
            confirmLabel = stringResource(R.string.rename),
            initialValue = currentNote.title,
            placeholder = stringResource(R.string.title),
            isDark = isDark,
            maxLength = SavedNote.TITLE_LIMIT,
            onDismiss = {
                AnalyticsEvents.logButtonClick("rename_dialog_cancel", HOME_SCREEN)
                showingRename = false
            },
            onConfirm = { title ->
                AnalyticsEvents.logButtonClick("rename_dialog_save", HOME_SCREEN)
                showingRename = false
                if (title.isNotBlank()) {
                    scope.launch {
                        if (!settingsService.updateNote(currentNote.id, title = title.trim())) {
                            errorMessage = context.getString(R.string.note_couldnt_be_renamed)
                        }
                    }
                }
            }
        )
    }

    errorMessage?.let { message ->
        ErrorDialog(message = message, isDark = isDark) {
            AnalyticsEvents.logButtonClick("editor_error_ok", HOME_SCREEN)
            errorMessage = null
        }
    }
}

/**
 * The script's title, whether it has changes to save, and the saved one's
 * version, in small text on one line at the bottom edge, below the controls.
 * The title is cut short after 20 characters. "Saved" for a moment after
 * saving. The title opens to be renamed, the version its history.
 */
@Composable
private fun StatusFooter(
    note: SavedNote?,
    isCardsMode: Boolean,
    isUnsaved: Boolean,
    showsSaved: Boolean,
    version: Int?,
    isDark: Boolean,
    onRename: () -> Unit,
    onVersions: () -> Unit
) {
    val title = note?.title ?: stringResource(if (isCardsMode) R.string.new_deck else R.string.new_script)
    // Kept short, so the version beside it always has room.
    val shown = if (title.length > FOOTER_TITLE_LIMIT) title.take(FOOTER_TITLE_LIMIT).trim() + "…" else title
    val state = when {
        isUnsaved -> stringResource(R.string.unsaved)
        showsSaved -> stringResource(R.string.saved)
        else -> null
    }
    val versionText = version?.let { stringResource(R.string.version_number, it) }
    val details = listOfNotNull(state, versionText).joinToString(" · ")
    val renames = stringResource(R.string.renames_the_script)
    val opensHistory = stringResource(R.string.opens_version_history)
    val color = AppColors.textSecondary(isDark)

    Row(
        modifier = Modifier
            .height(STATUS_HEIGHT)
            .padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = shown,
            fontSize = 11.sp,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f, fill = false)
                .then(
                    if (note != null) {
                        Modifier
                            .clickableWithoutRipple(onRename)
                            .semantics { onClick(label = renames, action = null) }
                    } else {
                        Modifier
                    }
                )
        )
        if (details.isNotEmpty()) {
            Text(
                text = " · $details",
                fontSize = 11.sp,
                color = color,
                maxLines = 1,
                modifier = if (versionText != null) {
                    Modifier
                        .clickableWithoutRipple(onVersions)
                        .semantics { onClick(label = opensHistory, action = null) }
                } else {
                    Modifier
                }
            )
        }
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
            .height(CONTROLS_ROW_HEIGHT)
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

/** Play, for the teleprompter and for a deck alike. */
@Composable
private fun StartButton(isCardsMode: Boolean, isEnabled: Boolean, isDark: Boolean, onClick: () -> Unit) {
    val onGreen = if (isDark) Color.Black else Color.White
    val label = stringResource(if (isCardsMode) R.string.open_cards else R.string.start_teleprompter)
    Box(
        modifier = Modifier
            .size(CONTROLS_ROW_HEIGHT)
            .alpha(if (isEnabled) 1f else 0.4f)
            .glassed(CircleShape, isDark, tint = AppColors.green(isDark))
            .clickableWithoutRipple { if (isEnabled) onClick() }
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.PlayArrow,
            contentDescription = null,
            tint = onGreen,
            modifier = Modifier.size(24.dp)
        )
    }
}

/**
 * Notes editor with live syntax highlighting for `[…]` cues, and the
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


/** The activity behind a composable's context, for the Play review flow. */
internal fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}

