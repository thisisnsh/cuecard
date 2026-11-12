package com.thisisnsh.cuecard.android.views

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.RemoteNotification
import com.thisisnsh.cuecard.android.models.RichText
import com.thisisnsh.cuecard.android.models.ScriptFile
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.modifiers.scriptEdgeFade
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SavedNote
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.Take
import com.thisisnsh.cuecard.android.services.TakeCounts
import com.thisisnsh.cuecard.android.services.TakesLibrary
import com.thisisnsh.cuecard.android.services.TextPack
import com.thisisnsh.cuecard.android.services.containsCollection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private const val LIBRARY_SCREEN = "library"
private const val LIBRARY_PREFS = "library"
private const val SORT_KEY = "library_sort"
private const val MODE_KEY = "library_mode"
/** The collection chosen, or empty for All. */
private const val COLLECTION_KEY = "library_collection"
/** The warning that scripts are lost with the app until there's a storage folder. */
private const val WARNING_DISMISSED_KEY = "library_collection_tip_dismissed"
private const val OPENS_KEY = "library_opens_since_folder_tip_dismissed"
/** A put-away warning comes back every this many times the app is opened. */
private const val OPENS_BETWEEN_REMINDERS = 10

/** The list's own margins keep rows off the screen's edges. */
private val SIDE_MARGIN = 20.dp

/** The launch's open is counted once, however often the library appears. */
private var hasCountedLaunch = false

private enum class LibrarySort(val rawValue: String) {
    EDITED("edited"), CREATED("created"), TITLE("title");

    companion object {
        fun fromString(value: String?): LibrarySort = entries.firstOrNull { it.rawValue == value } ?: EDITED
    }
}

/** A script about to replace what's being written in its mode's editor. */
private sealed class PendingOpen {
    abstract val mode: ScriptMode

    data class Note(val note: SavedNote) : PendingOpen() {
        override val mode: ScriptMode get() = note.mode
    }

    data class New(override val mode: ScriptMode) : PendingOpen()
}

/** When a script was edited or made, as the sections of the library. */
internal enum class LibraryDateGroup {
    TODAY, YESTERDAY, WEEK, MONTH, EARLIER;

    companion object {
        fun of(date: Long, now: Long = System.currentTimeMillis()): LibraryDateGroup {
            val days = daysBetween(date, now)
            return when {
                days <= 0 -> TODAY
                days == 1 -> YESTERDAY
                days < 7 -> WEEK
                days < 30 -> MONTH
                else -> EARLIER
            }
        }

        private fun daysBetween(from: Long, to: Long): Int {
            fun startOfDay(time: Long) = Calendar.getInstance().apply {
                timeInMillis = time
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val start = startOfDay(from)
            val end = startOfDay(to)
            var days = 0
            while (start.before(end) && days < 400) {
                start.add(Calendar.DAY_OF_YEAR, 1)
                days++
            }
            return days
        }
    }
}

/** Notes listed together, under a date section's name or none. */
private data class LibraryGroup(val kind: LibraryDateGroup?, val notes: List<SavedNote>)

/** A collection named beside a script, with a dot of its color. */
private data class LibraryCollectionTag(val name: String, val color: Color)

/**
 * Where the app opens: every saved script and deck, in collections, with the
 * takes recorded with each. A script opens into the editor from here. The
 * collections are chips at the top that narrow the list to one collection's,
 * in place; All shows every one, filed or not. The chosen collection, the mode
 * and the order are remembered.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    takeCounts: TakeCounts,
    onOpenEditor: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val prefs = remember { context.getSharedPreferences(LIBRARY_PREFS, Context.MODE_PRIVATE) }

    val savedNotes by settingsService.savedNotes.collectAsState()
    val allCollections by settingsService.collections.collectAsState()
    val scripts by settingsService.scripts.collectAsState()
    val noteIds by settingsService.noteIds.collectAsState()
    val draftCollections by settingsService.draftCollections.collectAsState()
    val draftIds by settingsService.draftIds.collectAsState()
    val hasNotesFolder by settingsService.hasNotesFolder.collectAsState()
    val notesFolderName by settingsService.notesFolderName.collectAsState()
    val oversizedFiles by settingsService.notesFolderOversizedFiles.collectAsState()
    val undeletedFiles by settingsService.notesFolderUndeletedFiles.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()
    val takeTotals by takeCounts.counts.collectAsState()
    val recentTakes by takeCounts.recent.collectAsState()

    var sort by remember { mutableStateOf(LibrarySort.fromString(prefs.getString(SORT_KEY, null))) }
    var mode by remember { mutableStateOf(ScriptMode.fromString(prefs.getString(MODE_KEY, null))) }
    var chosenCollection by remember { mutableStateOf(prefs.getString(COLLECTION_KEY, "").orEmpty()) }
    var warningDismissed by remember { mutableStateOf(prefs.getBoolean(WARNING_DISMISSED_KEY, false)) }

    fun choose(collection: String) {
        chosenCollection = collection
        prefs.edit { putString(COLLECTION_KEY, collection) }
    }

    var query by remember { mutableStateOf("") }
    var showingHelp by remember { mutableStateOf(false) }
    var showingSettings by remember { mutableStateOf(false) }
    var showingModeMenu by remember { mutableStateOf(false) }
    var showingMenu by remember { mutableStateOf(false) }
    var showingSortMenu by remember { mutableStateOf(false) }
    var showingStopFolder by remember { mutableStateOf(false) }
    var showingStopFolderFailed by remember { mutableStateOf(false) }
    var showingDeleteAll by remember { mutableStateOf(false) }
    var pendingOpen by remember { mutableStateOf<PendingOpen?>(null) }
    var draftToDiscard by remember { mutableStateOf<ScriptMode?>(null) }
    var noteToRename by remember { mutableStateOf<SavedNote?>(null) }
    var noteToDelete by remember { mutableStateOf<SavedNote?>(null) }
    var noteToCollect by remember { mutableStateOf<SavedNote?>(null) }
    var showingNewCollection by remember { mutableStateOf(false) }
    var collectionToRename by remember { mutableStateOf<String?>(null) }
    var collectionToDelete by remember { mutableStateOf<String?>(null) }
    /** The script whose takes are open. */
    var takesTarget by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    /** The collection shown, or null for All. One deleted since it was chosen is All. */
    val collection = chosenCollection.takeIf { it in allCollections }
    val collections = remember(allCollections) { allCollections.sortedWith(String.CASE_INSENSITIVE_ORDER) }
    val trimmedQuery = query.trim()

    fun matches(title: String, content: String): Boolean =
        trimmedQuery.isEmpty() || title.contains(trimmedQuery, ignoreCase = true) ||
            LibraryText.plain(content).contains(trimmedQuery, ignoreCase = true)

    /**
     * The saved notes shown: the chosen collection's, or every one under All, of
     * the chosen mode, matching the search, in the chosen order.
     */
    val notes = remember(savedNotes, collection, mode, trimmedQuery, sort) {
        val shown = savedNotes.filter { note ->
            (collection == null || note.collection == collection) && note.mode == mode && matches(note.title, note.content)
        }
        when (sort) {
            LibrarySort.EDITED -> shown.sortedByDescending { it.updatedAt }
            LibrarySort.CREATED -> shown.sortedByDescending { it.createdAt }
            LibrarySort.TITLE -> shown.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
        }
    }

    fun draftCollection(mode: ScriptMode): String? =
        draftCollections[mode]?.let { name -> allCollections.firstOrNull { it.equals(name, ignoreCase = true) } }

    fun hasUnsavedChanges(mode: ScriptMode): Boolean {
        val text = scripts[mode].orEmpty()
        val note = noteIds[mode]?.let { id -> savedNotes.find { it.id == id } } ?: return text.isNotBlank()
        return note.content != text
    }

    /** A new script of the chosen mode that isn't saved yet, if it was started here. */
    val draftText = scripts[mode].orEmpty()
    val hasDraft = noteIds[mode] == null && draftText.isNotBlank() &&
        (collection == null || draftCollection(mode) == collection) && matches("", draftText)

    /** The saved note open in the editor in the chosen mode, if it's listed. */
    val openNote = noteIds[mode]?.let { id -> notes.find { it.id == id } }

    /** The script open in the editor is shown on its own at the top, unless the list is being searched. */
    val showsHero = trimmedQuery.isEmpty() && (hasDraft || openNote != null)

    /**
     * The notes listed below the open script, in sections by when they were
     * edited or made while sorted by date. Searched, or sorted by title, they're one list.
     */
    val groups = remember(notes, showsHero, openNote, trimmedQuery, sort) {
        val heroId = if (showsHero) openNote?.id else null
        val listed = notes.filter { it.id != heroId }
        if (trimmedQuery.isNotEmpty() || sort == LibrarySort.TITLE) {
            if (listed.isEmpty()) emptyList() else listOf(LibraryGroup(null, listed))
        } else {
            val now = System.currentTimeMillis()
            val grouped = mutableListOf<LibraryGroup>()
            for (note in listed) {
                val kind = LibraryDateGroup.of(if (sort == LibrarySort.CREATED) note.createdAt else note.updatedAt, now)
                val last = grouped.lastOrNull()
                if (last?.kind == kind) {
                    grouped[grouped.size - 1] = last.copy(notes = last.notes + note)
                } else {
                    grouped += LibraryGroup(kind, listOf(note))
                }
            }
            grouped
        }
    }

    /** Shown until there's a storage folder, unless put away, and whenever the folder can't be reached. */
    val showsStorageWarning = if (hasNotesFolder) notesFolderName == null else !warningDismissed

    val banner = remember(payload, dismissedIds) { notifications.notification(RemoteNotification.Surface.HOME_BANNER) }

    /** A deck's card count. Scripts aren't given a length. */
    val cardCountLabels = remember(notes, mode) {
        if (mode == ScriptMode.CARDS) notes.associate { it.id to CueCards.cards(it.content).size } else emptyMap()
    }
    @Composable
    fun cardCount(content: String, id: String? = null): String? {
        if (mode != ScriptMode.CARDS) return null
        val count = id?.let { cardCountLabels[it] } ?: CueCards.cards(content).size
        return pluralStringResource(R.plurals.cards_count, count, count)
    }

    /** A collection's name and color, shown under All only: a chosen collection already says where everything is. */
    fun tag(name: String?): LibraryCollectionTag? {
        if (collection != null || name == null) return null
        return LibraryCollectionTag(name, collectionColor(name, allCollections, isDark))
    }

    // MARK: Actions

    /** Back to what's being written in `mode`, as it was left. */
    fun openDraft(mode: ScriptMode) {
        scope.launch {
            settingsService.updateScriptMode(mode)
            onOpenEditor()
        }
    }

    fun proceed(pending: PendingOpen) {
        scope.launch {
            when (pending) {
                is PendingOpen.Note -> settingsService.loadNote(pending.note)
                is PendingOpen.New -> settingsService.createNewNote(pending.mode, collection)
            }
            onOpenEditor()
        }
    }

    /**
     * Open `note` in the editor. One already open there keeps what's being
     * written in it; any other replaces its mode's script, once the user agrees
     * to lose what isn't saved.
     */
    fun openInEditor(note: SavedNote) {
        when {
            noteIds[note.mode] == note.id -> openDraft(note.mode)
            hasUnsavedChanges(note.mode) -> pendingOpen = PendingOpen.Note(note)
            else -> proceed(PendingOpen.Note(note))
        }
    }

    fun open(note: SavedNote, button: String = "load_note") {
        AnalyticsEvents.logButtonClick(button, LIBRARY_SCREEN)
        openInEditor(note)
    }

    fun startNew(mode: ScriptMode) {
        AnalyticsEvents.logButtonClick(if (mode == ScriptMode.CARDS) "new_deck" else "new_script", LIBRARY_SCREEN)
        if (hasUnsavedChanges(mode)) pendingOpen = PendingOpen.New(mode) else proceed(PendingOpen.New(mode))
    }

    fun duplicate(note: SavedNote, button: String) {
        AnalyticsEvents.logButtonClick(button, LIBRARY_SCREEN)
        scope.launch {
            if (settingsService.duplicateNote(note.id) == null) {
                errorMessage = context.getString(R.string.script_couldnt_be_duplicated)
            }
        }
    }

    /** Why deleting scripts left files behind in the storage folder. */
    fun undeletedFilesMessage(count: Int): String =
        notesFolderName?.let {
            context.getString(if (count == 1) R.string.undeleted_file_in_folder else R.string.undeleted_files_in_folder, it)
        } ?: context.getString(if (count == 1) R.string.undeleted_file_later else R.string.undeleted_files_later)

    // MARK: Files

    /** A file picked to import, kept as a script in the collection shown, and opened. */
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            val isPackage = withContext(Dispatchers.IO) { TextPack.isPackage(context, uri) }
            try {
                // A TextPack brings its images in with it.
                val text = withContext(Dispatchers.IO) {
                    if (isPackage) TextPack.readScript(context, uri) else ScriptFile.readText(context, uri)
                }
                if (text.isBlank()) {
                    errorMessage = context.getString(R.string.file_empty)
                    return@launch
                }
                val content = TeleprompterParser.normalizingTags(text)
                val note = settingsService.importNote(ScriptFile.title(context, uri), content, collection)
                // Opened, so it's plain the file came in, whatever the list shows.
                if (note != null) openInEditor(note) else errorMessage = context.getString(R.string.file_not_saved_as_script)
            } catch (e: ScriptFile.FileTooLarge) {
                errorMessage = context.getString(if (isPackage) R.string.package_too_large else R.string.file_too_large)
                AnalyticsEvents.logEvent("file_too_large", mapOf("source" to "import", "size_mb" to e.size / (1024 * 1024)))
            } catch (e: Exception) {
                errorMessage = context.getString(R.string.file_unreadable)
            }
        }
    }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            try {
                settingsService.chooseNotesFolder(uri)
            } catch (e: Exception) {
                errorMessage = context.getString(R.string.folder_unusable)
            }
        }
    }

    fun chooseFolder(button: String) {
        AnalyticsEvents.logButtonClick(button, LIBRARY_SCREEN)
        runCatching { folderPicker.launch(null) }
    }

    // MARK: Lifecycle

    /** A put-away warning about having no storage folder comes back every tenth time the app is opened. */
    fun countOpen() {
        if (!warningDismissed || settingsService.hasNotesFolder.value) return
        val opens = prefs.getInt(OPENS_KEY, 0) + 1
        if (opens >= OPENS_BETWEEN_REMINDERS) {
            warningDismissed = false
            prefs.edit {
                putBoolean(WARNING_DISMISSED_KEY, false)
                putInt(OPENS_KEY, 0)
            }
        } else {
            prefs.edit { putInt(OPENS_KEY, opens) }
        }
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(LIBRARY_SCREEN)
        takeCounts.reload()
        if (!hasCountedLaunch) {
            hasCountedLaunch = true
            countOpen()
        }
        settingsService.syncNotesFolder()
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        var wasInBackground = false
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> wasInBackground = true
                Lifecycle.Event.ON_RESUME -> {
                    takeCounts.reload()
                    if (wasInBackground) {
                        wasInBackground = false
                        countOpen()
                    }
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    val listState = rememberLazyListState()
    // A scroll of the list ends the search, like the keyboard's Done key.
    LaunchedEffect(listState.isScrollInProgress) {
        if (listState.isScrollInProgress) focusManager.clearFocus()
    }

    BackHandler(enabled = showingHelp || showingSettings || takesTarget != null) {
        when {
            showingHelp -> showingHelp = false
            takesTarget != null -> takesTarget = null
            showingSettings -> showingSettings = false
        }
    }

    val kindName = if (mode == ScriptMode.CARDS) stringResource(R.string.decks) else stringResource(R.string.scripts)
    val modeDescription = stringResource(R.string.mode_description, mode.displayName)

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                TopAppBar(
                    // Teleprompter or cards: whose scripts the library shows. The
                    // bar shows the chosen mode's name.
                    title = {
                        Box {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .clickableWithoutRipple {
                                        AnalyticsEvents.logButtonClick("library_mode_menu", LIBRARY_SCREEN)
                                        showingModeMenu = true
                                    }
                                    .semantics { contentDescription = modeDescription }
                            ) {
                                Text(
                                    text = mode.displayName,
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
                                ScriptMode.entries.forEach { choice ->
                                    DropdownMenuItem(
                                        text = { Text(choice.displayName) },
                                        onClick = {
                                            showingModeMenu = false
                                            AnalyticsEvents.logButtonClick("library_mode_${choice.rawValue}", LIBRARY_SCREEN)
                                            mode = choice
                                            prefs.edit { putString(MODE_KEY, choice.rawValue) }
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
                                contentDescription = stringResource(R.string.library_options),
                                tint = AppColors.textPrimary(isDark),
                                modifier = Modifier
                                    .padding(horizontal = 8.dp)
                                    .size(20.dp)
                                    .clickableWithoutRipple {
                                        AnalyticsEvents.logButtonClick("library_menu", LIBRARY_SCREEN)
                                        focusManager.clearFocus()
                                        showingMenu = true
                                    }
                            )

                            LibraryMenu(
                                expanded = showingMenu,
                                collection = collection,
                                hasNotesFolder = hasNotesFolder,
                                hasNotes = savedNotes.isNotEmpty(),
                                isDark = isDark,
                                onDismiss = { showingMenu = false },
                                onSort = {
                                    showingMenu = false
                                    showingSortMenu = true
                                },
                                onImport = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("import_file", LIBRARY_SCREEN)
                                    runCatching {
                                        importLauncher.launch(ScriptFile.importableMimeTypes + TextPack.importableMimeTypes)
                                    }
                                },
                                onNewCollection = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("new_collection", LIBRARY_SCREEN)
                                    showingNewCollection = true
                                },
                                onRenameCollection = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("rename_collection", LIBRARY_SCREEN)
                                    collectionToRename = collection
                                },
                                onDeleteCollection = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("delete_collection", LIBRARY_SCREEN)
                                    collectionToDelete = collection
                                },
                                onChooseFolder = {
                                    showingMenu = false
                                    chooseFolder("choose_notes_folder")
                                },
                                onStopFolder = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("stop_notes_folder", LIBRARY_SCREEN)
                                    showingStopFolder = true
                                },
                                onDeleteAll = {
                                    showingMenu = false
                                    AnalyticsEvents.logButtonClick("delete_all_notes", LIBRARY_SCREEN)
                                    showingDeleteAll = true
                                }
                            )

                            DropdownMenu(
                                expanded = showingSortMenu,
                                onDismissRequest = { showingSortMenu = false },
                                containerColor = AppColors.background(isDark)
                            ) {
                                LibrarySort.entries.forEach { choice ->
                                    DropdownMenuItem(
                                        text = { Text(sortLabel(choice)) },
                                        trailingIcon = {
                                            if (choice == sort) {
                                                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                                            }
                                        },
                                        onClick = {
                                            showingSortMenu = false
                                            AnalyticsEvents.logButtonClick("library_sort", LIBRARY_SCREEN)
                                            sort = choice
                                            prefs.edit { putString(SORT_KEY, choice.rawValue) }
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
                                    AnalyticsEvents.logButtonClick("settings", LIBRARY_SCREEN)
                                    focusManager.clearFocus()
                                    showingSettings = true
                                }
                        )

                        HelpButton(page = HelpPage.LIBRARY, isDark = isDark, modifier = Modifier.padding(end = 4.dp)) {
                            focusManager.clearFocus()
                            showingHelp = true
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background(isDark))
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                // Out of the list, so they stay in reach and run edge to edge.
                if (collections.isNotEmpty()) {
                    CollectionChips(
                        collections = collections,
                        selected = collection,
                        allCount = savedNotes.count { it.mode == mode },
                        countOf = { name -> savedNotes.count { it.collection == name && it.mode == mode } },
                        isDark = isDark,
                        onSelect = { name ->
                            AnalyticsEvents.logButtonClick(
                                if (name == null) "library_collection_all" else "library_collection_choose", LIBRARY_SCREEN
                            )
                            choose(name.orEmpty())
                        },
                        onNew = {
                            AnalyticsEvents.logButtonClick("new_collection_chip", LIBRARY_SCREEN)
                            showingNewCollection = true
                        },
                        onRename = { name ->
                            AnalyticsEvents.logButtonClick("rename_collection_chip", LIBRARY_SCREEN)
                            collectionToRename = name
                        },
                        onDelete = { name ->
                            AnalyticsEvents.logButtonClick("delete_collection_chip", LIBRARY_SCREEN)
                            collectionToDelete = name
                        }
                    )
                }

                Box(modifier = Modifier.weight(1f)) {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(start = SIDE_MARGIN, end = SIDE_MARGIN, bottom = 96.dp),
                        modifier = Modifier
                            .fillMaxSize()
                            // Faded at the top only: at the bottom the list runs on
                            // under the search, which floats over it.
                            .scriptEdgeFade(isDark = isDark, top = 12.dp, bottom = 0.dp)
                    ) {
                        banner?.let { notification ->
                            item(key = "banner") {
                                NotificationBanner(
                                    notification = notification,
                                    notifications = notifications,
                                    modifier = Modifier.padding(vertical = 6.dp)
                                )
                            }
                        }

                        if (trimmedQuery.isEmpty() && showsStorageWarning) {
                            item(key = "storage-warning") {
                                LibraryStorageBanner(
                                    isUnreachable = hasNotesFolder,
                                    isDark = isDark,
                                    onChoose = { chooseFolder("choose_notes_folder_banner") },
                                    onDismiss = if (hasNotesFolder) null else {
                                        {
                                            AnalyticsEvents.logButtonClick("dismiss_folder_tip", LIBRARY_SCREEN)
                                            warningDismissed = true
                                            prefs.edit {
                                                putBoolean(WARNING_DISMISSED_KEY, true)
                                                putInt(OPENS_KEY, 0)
                                            }
                                        }
                                    }
                                )
                            }
                        }

                        if (hasDraft || notes.isNotEmpty()) {
                            val draftScriptId = draftIds[mode]
                            val newTitle = if (mode == ScriptMode.CARDS) R.string.new_deck else R.string.new_script
                            if (showsHero && openNote != null) {
                                item(key = "hero-${openNote.id}") {
                                    val isUnsaved = hasUnsavedChanges(mode)
                                    NoteSwipe(
                                        isDark = isDark,
                                        onDelete = {
                                            AnalyticsEvents.logButtonClick("delete_note_swipe", LIBRARY_SCREEN)
                                            noteToDelete = openNote
                                        },
                                        onCollect = {
                                            AnalyticsEvents.logButtonClick("add_to_collection_swipe", LIBRARY_SCREEN)
                                            noteToCollect = openNote
                                        }
                                    ) {
                                        NoteMenuBox(
                                            note = openNote,
                                            isDark = isDark,
                                            onOpen = { open(openNote, "load_note_menu") },
                                            onRename = {
                                                AnalyticsEvents.logButtonClick("rename_note_menu", LIBRARY_SCREEN)
                                                noteToRename = openNote
                                            },
                                            onDuplicate = { duplicate(openNote, "duplicate_note_menu") },
                                            onCollect = {
                                                AnalyticsEvents.logButtonClick("add_to_collection_menu", LIBRARY_SCREEN)
                                                noteToCollect = openNote
                                            },
                                            onShare = {
                                                AnalyticsEvents.logButtonClick("share_note_menu", LIBRARY_SCREEN)
                                                shareScript(context, scope, openNote.title, openNote.content) { errorMessage = it }
                                            },
                                            onDelete = {
                                                AnalyticsEvents.logButtonClick("delete_note_menu", LIBRARY_SCREEN)
                                                noteToDelete = openNote
                                            },
                                            onTap = { open(openNote) }
                                        ) {
                                            LibraryHero(
                                                title = openNote.title,
                                                preview = LibraryText.preview(draftText),
                                                detail = listOfNotNull(cardCount(draftText), LibraryText.date(openNote.updatedAt)).joinToString(" · "),
                                                badge = if (isUnsaved) stringResource(R.string.unsaved) else null,
                                                collection = tag(openNote.collection),
                                                takes = takeTotals[openNote.id] ?: 0,
                                                recentTakes = recentTakes[openNote.id].orEmpty(),
                                                library = takeCounts.library,
                                                isDark = isDark,
                                                onTakes = {
                                                    AnalyticsEvents.logButtonClick("library_takes_note", LIBRARY_SCREEN)
                                                    takesTarget = openNote.id
                                                }
                                            )
                                        }
                                    }
                                }
                            } else if (hasDraft) {
                                item(key = "draft-${mode.rawValue}") {
                                    DraftSwipe(isDark = isDark, onDiscard = {
                                        AnalyticsEvents.logButtonClick("discard_draft_swipe", LIBRARY_SCREEN)
                                        draftToDiscard = mode
                                    }) {
                                        DraftMenuBox(
                                            isDark = isDark,
                                            onKeepWriting = {
                                                AnalyticsEvents.logButtonClick("open_draft_menu", LIBRARY_SCREEN)
                                                openDraft(mode)
                                            },
                                            onDiscard = {
                                                AnalyticsEvents.logButtonClick("discard_draft_menu", LIBRARY_SCREEN)
                                                draftToDiscard = mode
                                            },
                                            onTap = {
                                                AnalyticsEvents.logButtonClick("open_draft", LIBRARY_SCREEN)
                                                openDraft(mode)
                                            }
                                        ) {
                                            val onTakes = {
                                                AnalyticsEvents.logButtonClick("library_takes_draft", LIBRARY_SCREEN)
                                                takesTarget = draftScriptId
                                            }
                                            if (showsHero) {
                                                LibraryHero(
                                                    title = stringResource(newTitle),
                                                    preview = LibraryText.preview(draftText),
                                                    detail = cardCount(draftText).orEmpty(),
                                                    badge = stringResource(R.string.draft),
                                                    collection = tag(draftCollection(mode)),
                                                    takes = draftScriptId?.let { takeTotals[it] } ?: 0,
                                                    recentTakes = draftScriptId?.let { recentTakes[it] }.orEmpty(),
                                                    library = takeCounts.library,
                                                    isDark = isDark,
                                                    onTakes = onTakes
                                                )
                                            } else {
                                                // The draft as a row of its own, while the list is searched.
                                                LibraryScriptRow(
                                                    title = stringResource(newTitle),
                                                    preview = LibraryText.preview(draftText),
                                                    detail = listOfNotNull(cardCount(draftText), stringResource(R.string.not_saved_yet)).joinToString(" · "),
                                                    hasBadge = true,
                                                    collection = tag(draftCollection(mode)),
                                                    takes = draftScriptId?.let { takeTotals[it] } ?: 0,
                                                    recentTakes = draftScriptId?.let { recentTakes[it] }.orEmpty(),
                                                    library = takeCounts.library,
                                                    isDark = isDark,
                                                    onTakes = onTakes
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            groups.forEach { group ->
                                group.kind?.let { kind ->
                                    item(key = "group-${kind.name}") { GroupHeader(dateGroupTitle(kind), isDark) }
                                }
                                items(group.notes, key = { it.id }) { note ->
                                    val isOpen = noteIds[note.mode] == note.id
                                    val date = if (sort == LibrarySort.CREATED) note.createdAt else note.updatedAt
                                    val whenText = group.kind?.let { LibraryText.date(date, it) } ?: LibraryText.date(date)
                                    NoteSwipe(
                                        isDark = isDark,
                                        onDelete = {
                                            AnalyticsEvents.logButtonClick("delete_note_swipe", LIBRARY_SCREEN)
                                            noteToDelete = note
                                        },
                                        onCollect = {
                                            AnalyticsEvents.logButtonClick("add_to_collection_swipe", LIBRARY_SCREEN)
                                            noteToCollect = note
                                        }
                                    ) {
                                        NoteMenuBox(
                                            note = note,
                                            isDark = isDark,
                                            onOpen = { open(note, "load_note_menu") },
                                            onRename = {
                                                AnalyticsEvents.logButtonClick("rename_note_menu", LIBRARY_SCREEN)
                                                noteToRename = note
                                            },
                                            onDuplicate = { duplicate(note, "duplicate_note_menu") },
                                            onCollect = {
                                                AnalyticsEvents.logButtonClick("add_to_collection_menu", LIBRARY_SCREEN)
                                                noteToCollect = note
                                            },
                                            onShare = {
                                                AnalyticsEvents.logButtonClick("share_note_menu", LIBRARY_SCREEN)
                                                shareScript(context, scope, note.title, note.content) { errorMessage = it }
                                            },
                                            onDelete = {
                                                AnalyticsEvents.logButtonClick("delete_note_menu", LIBRARY_SCREEN)
                                                noteToDelete = note
                                            },
                                            onTap = { open(note) }
                                        ) {
                                            LibraryScriptRow(
                                                title = note.title,
                                                preview = LibraryText.preview(note.content),
                                                detail = listOfNotNull(cardCount(note.content, note.id), whenText).joinToString(" · "),
                                                hasBadge = isOpen && hasUnsavedChanges(note.mode),
                                                collection = tag(note.collection),
                                                takes = takeTotals[note.id] ?: 0,
                                                recentTakes = recentTakes[note.id].orEmpty(),
                                                library = takeCounts.library,
                                                isDark = isDark,
                                                onTakes = {
                                                    AnalyticsEvents.logButtonClick("library_takes_note", LIBRARY_SCREEN)
                                                    takesTarget = note.id
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            item(key = "empty") {
                                EmptyState(
                                    query = trimmedQuery,
                                    kindName = kindName,
                                    isCards = mode == ScriptMode.CARDS,
                                    isDark = isDark
                                )
                            }
                        }

                        if (trimmedQuery.isEmpty()) {
                            item(key = "footer") {
                                LibraryFooter(
                                    hasFolder = hasNotesFolder,
                                    folderName = notesFolderName,
                                    oversizedFiles = oversizedFiles,
                                    undeletedFiles = undeletedFiles,
                                    isDark = isDark,
                                    modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 10.dp, bottom = 16.dp)
                                )
                            }
                        }
                    }

                    // Searching and starting a script, together at the bottom,
                    // floating over the list. The search ends with the keyboard's
                    // Done key, or a scroll of the list.
                    Row(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .navigationBarsPadding()
                            .imePadding()
                            .widthIn(max = 600.dp)
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        LibrarySearchField(
                            query = query,
                            onQueryChange = { query = it },
                            placeholder = collection?.let { stringResource(R.string.search_collection, it) }
                                ?: stringResource(R.string.search),
                            isDark = isDark,
                            onDone = {
                                AnalyticsEvents.logButtonClick("library_search_done", LIBRARY_SCREEN)
                                focusManager.clearFocus()
                            },
                            onClear = {
                                AnalyticsEvents.logButtonClick("library_search_clear", LIBRARY_SCREEN)
                                query = ""
                            },
                            modifier = Modifier.weight(1f)
                        )

                        val newLabel = stringResource(if (mode == ScriptMode.CARDS) R.string.new_deck else R.string.new_script)
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .glassed(CircleShape, isDark, tint = AppColors.green(isDark))
                                .clickableWithoutRipple {
                                    focusManager.clearFocus()
                                    startNew(mode)
                                }
                                .semantics { contentDescription = newLabel },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Add,
                                contentDescription = null,
                                tint = if (isDark) Color.Black else Color.White,
                                modifier = Modifier.size(24.dp)
                            )
                        }
                    }
                }
            }
        }

        // MARK: - Presentations

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
            visible = takesTarget != null,
            enter = scaleIn(initialScale = 0.9f) + fadeIn(),
            exit = scaleOut(targetScale = 0.9f) + fadeOut()
        ) {
            // The script the takes were opened for, kept while they close.
            val target = remember { takesTarget }
            if (target != null) {
                ScriptTakes(scriptId = target) {
                    takesTarget = null
                    takeCounts.reload()
                }
            }
        }

        HelpOverlay(page = HelpPage.LIBRARY, visible = showingHelp, onDismiss = { showingHelp = false })
    }

    // MARK: - Dialogs

    pendingOpen?.let { pending ->
        val unsavedMessage = noteIds[pending.mode]?.let { id -> savedNotes.find { it.id == id }?.title }
            ?.let { stringResource(R.string.unsaved_open_message, it) }
            ?: stringResource(if (pending.mode == ScriptMode.CARDS) R.string.unsaved_new_deck_message else R.string.unsaved_new_script_message)
        val saveAndContinue = stringResource(R.string.save_and_continue)
        val keepEditing = stringResource(R.string.keep_editing)
        val discardChanges = stringResource(R.string.discard_changes)
        ChoiceDialog(
            title = stringResource(R.string.unsaved_changes),
            message = unsavedMessage,
            choices = listOfNotNull(
                if (noteIds[pending.mode] != null) {
                    DialogChoice(saveAndContinue) {
                        AnalyticsEvents.logButtonClick("unsaved_save_continue", LIBRARY_SCREEN)
                        pendingOpen = null
                        scope.launch {
                            if (settingsService.saveChanges(pending.mode)) {
                                proceed(pending)
                            } else {
                                errorMessage = context.getString(R.string.note_couldnt_be_saved)
                            }
                        }
                    }
                } else {
                    null
                },
                DialogChoice(keepEditing) {
                    AnalyticsEvents.logButtonClick("unsaved_keep_editing", LIBRARY_SCREEN)
                    pendingOpen = null
                    openDraft(pending.mode)
                },
                DialogChoice(discardChanges, isDestructive = true) {
                    AnalyticsEvents.logButtonClick("unsaved_discard", LIBRARY_SCREEN)
                    pendingOpen = null
                    proceed(pending)
                }
            ),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("unsaved_cancel", LIBRARY_SCREEN)
                pendingOpen = null
            }
        )
    }

    draftToDiscard?.let { discarding ->
        ConfirmDialog(
            title = stringResource(R.string.discard_draft),
            message = stringResource(R.string.discard_draft_message),
            confirmLabel = stringResource(R.string.discard),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("discard_draft_cancel", LIBRARY_SCREEN)
                draftToDiscard = null
            },
            onConfirm = {
                AnalyticsEvents.logButtonClick("discard_draft", LIBRARY_SCREEN)
                draftToDiscard = null
                scope.launch { settingsService.discardDraft(discarding) }
            }
        )
    }

    noteToRename?.let { note ->
        TextFieldDialog(
            title = stringResource(R.string.rename_script),
            message = null,
            confirmLabel = stringResource(R.string.rename),
            initialValue = note.title,
            placeholder = stringResource(R.string.title),
            isDark = isDark,
            maxLength = SavedNote.TITLE_LIMIT,
            onDismiss = {
                AnalyticsEvents.logButtonClick("rename_note_cancel", LIBRARY_SCREEN)
                noteToRename = null
            },
            onConfirm = { title ->
                AnalyticsEvents.logButtonClick("rename_note_confirm", LIBRARY_SCREEN)
                noteToRename = null
                if (title.isNotBlank()) {
                    scope.launch {
                        if (!settingsService.updateNote(note.id, title = title.trim())) {
                            errorMessage = context.getString(R.string.note_couldnt_be_renamed)
                        }
                    }
                }
            }
        )
    }

    noteToDelete?.let { note ->
        ConfirmDialog(
            title = stringResource(R.string.delete_named, note.title),
            message = notesFolderName?.let { stringResource(R.string.delete_note_message_folder, it) }
                ?: stringResource(R.string.delete_note_message),
            confirmLabel = stringResource(R.string.delete),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("delete_note_cancel", LIBRARY_SCREEN)
                noteToDelete = null
            },
            onConfirm = {
                AnalyticsEvents.logButtonClick("delete_note", LIBRARY_SCREEN)
                noteToDelete = null
                scope.launch {
                    if (!settingsService.deleteNote(note.id)) {
                        errorMessage = context.getString(R.string.note_was_deleted, undeletedFilesMessage(1))
                    }
                }
            }
        )
    }

    noteToCollect?.let { note ->
        CollectionPicker(
            note = savedNotes.find { it.id == note.id } ?: note,
            collections = collections,
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("add_to_collection_cancel", LIBRARY_SCREEN)
                noteToCollect = null
            },
            onPut = { name, button ->
                AnalyticsEvents.logButtonClick(button, LIBRARY_SCREEN)
                scope.launch {
                    if (settingsService.moveNote(note.id, name)) {
                        noteToCollect = null
                    } else {
                        errorMessage = context.getString(R.string.script_couldnt_be_collected)
                    }
                }
            },
            onCreate = { name ->
                AnalyticsEvents.logButtonClick("add_to_collection_new", LIBRARY_SCREEN)
                scope.launch {
                    val created = settingsService.createCollection(name)
                    if (created == null) {
                        errorMessage = context.getString(R.string.collection_name_taken)
                    } else if (settingsService.moveNote(note.id, created)) {
                        noteToCollect = null
                    } else {
                        errorMessage = context.getString(R.string.script_couldnt_be_collected)
                    }
                }
            }
        )
    }

    if (showingNewCollection) {
        TextFieldDialog(
            title = stringResource(R.string.new_collection),
            message = null,
            confirmLabel = stringResource(R.string.create),
            initialValue = "",
            placeholder = stringResource(R.string.name),
            isDark = isDark,
            maxLength = 40,
            onDismiss = {
                AnalyticsEvents.logButtonClick("new_collection_cancel", LIBRARY_SCREEN)
                showingNewCollection = false
            },
            onConfirm = { name ->
                AnalyticsEvents.logButtonClick("new_collection_create", LIBRARY_SCREEN)
                showingNewCollection = false
                scope.launch {
                    val created = settingsService.createCollection(name)
                    // Opened on the new collection, so what's made next goes in it.
                    if (created != null) choose(created) else errorMessage = context.getString(R.string.collection_name_taken)
                }
            }
        )
    }

    collectionToRename?.let { name ->
        TextFieldDialog(
            title = stringResource(R.string.rename_collection),
            message = null,
            confirmLabel = stringResource(R.string.rename),
            initialValue = name,
            placeholder = stringResource(R.string.name),
            isDark = isDark,
            maxLength = 40,
            onDismiss = {
                AnalyticsEvents.logButtonClick("rename_collection_cancel", LIBRARY_SCREEN)
                collectionToRename = null
            },
            onConfirm = { newName ->
                AnalyticsEvents.logButtonClick("rename_collection_confirm", LIBRARY_SCREEN)
                collectionToRename = null
                scope.launch {
                    if (!settingsService.renameCollection(name, newName)) {
                        errorMessage = context.getString(R.string.collection_name_taken)
                    } else if (collection == name) {
                        // The chosen collection stays chosen under its new name.
                        choose(ScriptFile.collectionName(newName))
                    }
                }
            }
        )
    }

    collectionToDelete?.let { name ->
        ConfirmDialog(
            title = stringResource(R.string.delete_collection_named, name),
            message = stringResource(R.string.delete_collection_message),
            confirmLabel = stringResource(R.string.delete_collection),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("delete_collection_cancel", LIBRARY_SCREEN)
                collectionToDelete = null
            },
            onConfirm = {
                AnalyticsEvents.logButtonClick("delete_collection_confirm", LIBRARY_SCREEN)
                collectionToDelete = null
                scope.launch {
                    settingsService.deleteCollection(name)
                    if (collection == name) choose("")
                }
            }
        )
    }

    if (showingStopFolder) {
        ConfirmDialog(
            title = stringResource(R.string.stop_using_storage_folder),
            message = notesFolderName?.let { stringResource(R.string.stop_storage_folder_message, it) }
                ?: stringResource(R.string.scripts_stay_in_cuecard),
            confirmLabel = stringResource(R.string.stop_using_folder),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("stop_notes_folder_cancel", LIBRARY_SCREEN)
                showingStopFolder = false
            },
            onConfirm = {
                AnalyticsEvents.logButtonClick("stop_notes_folder_confirm", LIBRARY_SCREEN)
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
            title = { Text(stringResource(R.string.couldnt_delete_script_files)) },
            text = {
                Text(
                    notesFolderName?.let { stringResource(R.string.stop_storage_folder_failed, it) }
                        ?: stringResource(R.string.stop_storage_folder_unreachable)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    AnalyticsEvents.logButtonClick("stop_notes_folder_anyway", LIBRARY_SCREEN)
                    showingStopFolderFailed = false
                    scope.launch { settingsService.stopUsingNotesFolderKeepingFiles() }
                }) {
                    Text(stringResource(R.string.stop_anyway), color = AppColors.blue(isDark))
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    AnalyticsEvents.logButtonClick("stop_notes_folder_keep", LIBRARY_SCREEN)
                    showingStopFolderFailed = false
                }) {
                    Text(stringResource(R.string.keep_using_folder), color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }

    if (showingDeleteAll) {
        ConfirmDialog(
            title = stringResource(R.string.delete_all_scripts_question),
            message = notesFolderName?.let { stringResource(R.string.delete_all_scripts_message_folder, it) }
                ?: stringResource(R.string.delete_all_scripts_message),
            confirmLabel = stringResource(R.string.delete_all),
            isDark = isDark,
            onDismiss = {
                AnalyticsEvents.logButtonClick("delete_all_notes_cancel", LIBRARY_SCREEN)
                showingDeleteAll = false
            },
            onConfirm = {
                AnalyticsEvents.logButtonClick("delete_all_notes_confirm", LIBRARY_SCREEN)
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
        ErrorDialog(message = message, isDark = isDark) {
            AnalyticsEvents.logButtonClick("library_error_ok", LIBRARY_SCREEN)
            errorMessage = null
        }
    }
}

@Composable
private fun sortLabel(sort: LibrarySort): String = stringResource(
    when (sort) {
        LibrarySort.EDITED -> R.string.date_edited
        LibrarySort.CREATED -> R.string.date_created
        LibrarySort.TITLE -> R.string.title
    }
)

@Composable
private fun dateGroupTitle(group: LibraryDateGroup): String = stringResource(
    when (group) {
        LibraryDateGroup.TODAY -> R.string.today
        LibraryDateGroup.YESTERDAY -> R.string.yesterday
        LibraryDateGroup.WEEK -> R.string.previous_7_days
        LibraryDateGroup.MONTH -> R.string.previous_30_days
        LibraryDateGroup.EARLIER -> R.string.earlier
    }
)

/**
 * Each collection's color, by the order the collections were made in, so it
 * stays the same as more are made.
 */
private fun collectionColor(name: String, collections: List<String>, isDark: Boolean): Color {
    val palette = listOf(
        AppColors.blue(isDark),
        AppColors.purple(isDark),
        AppColors.pink(isDark),
        AppColors.red(isDark),
        AppColors.green(isDark),
        Color(0xFFFF9500)
    )
    val index = collections.indexOfFirst { it.equals(name, ignoreCase = true) }.coerceAtLeast(0)
    return palette[index % palette.size]
}

// MARK: - Menu

@Composable
private fun LibraryMenu(
    expanded: Boolean,
    collection: String?,
    hasNotesFolder: Boolean,
    hasNotes: Boolean,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onSort: () -> Unit,
    onImport: () -> Unit,
    onNewCollection: () -> Unit,
    onRenameCollection: () -> Unit,
    onDeleteCollection: () -> Unit,
    onChooseFolder: () -> Unit,
    onStopFolder: () -> Unit,
    onDeleteAll: () -> Unit
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, containerColor = AppColors.background(isDark)) {
        DropdownMenuItem(text = { Text(stringResource(R.string.sort_by)) }, onClick = onSort)
        DropdownMenuItem(text = { Text(stringResource(R.string.import_file)) }, onClick = onImport)
        DropdownMenuItem(text = { Text(stringResource(R.string.new_collection)) }, onClick = onNewCollection)
        if (collection != null) {
            DropdownMenuItem(text = { Text(stringResource(R.string.rename_named, collection)) }, onClick = onRenameCollection)
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete_named_plain, collection), color = AppColors.red(isDark)) },
                onClick = onDeleteCollection
            )
        }

        HorizontalDivider()

        DropdownMenuItem(
            text = {
                Text(stringResource(if (hasNotesFolder) R.string.change_storage_folder else R.string.choose_storage_folder))
            },
            onClick = onChooseFolder
        )
        if (hasNotesFolder) {
            DropdownMenuItem(text = { Text(stringResource(R.string.stop_using_storage_folder_menu)) }, onClick = onStopFolder)
        }

        HorizontalDivider()

        DropdownMenuItem(
            text = {
                Text(
                    stringResource(R.string.delete_all_scripts),
                    color = AppColors.red(isDark).copy(alpha = if (hasNotes) 1f else 0.4f)
                )
            },
            enabled = hasNotes,
            onClick = onDeleteAll
        )
    }
}

// MARK: - Collections

/**
 * All, then each collection, side by side and scrolling sideways, with one to
 * make another. The chosen one is filled in, and the list below shows only
 * what's in it. Touched and held, a collection offers to rename or delete it.
 */
@Composable
private fun CollectionChips(
    collections: List<String>,
    selected: String?,
    allCount: Int,
    countOf: (String) -> Int,
    isDark: Boolean,
    onSelect: (String?) -> Unit,
    onNew: () -> Unit,
    onRename: (String) -> Unit,
    onDelete: (String) -> Unit
) {
    val state = rememberLazyListState()
    // Back on a collection chosen further along, it's scrolled into view.
    LaunchedEffect(Unit) {
        val index = selected?.let { collections.indexOf(it) + 1 } ?: 0
        if (index > 0) state.scrollToItem(index)
    }
    val newCollection = stringResource(R.string.new_collection)

    LazyRow(
        state = state,
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(top = 2.dp, bottom = 6.dp)
    ) {
        item(key = "") {
            CollectionChip(stringResource(R.string.all), allCount, selected == null, isDark, onClick = { onSelect(null) })
        }
        items(collections, key = { it }) { name ->
            var showingMenu by remember { mutableStateOf(false) }
            Box {
                CollectionChip(
                    title = name,
                    count = countOf(name),
                    isSelected = selected == name,
                    isDark = isDark,
                    onClick = { onSelect(name) },
                    onLongClick = { showingMenu = true }
                )
                DropdownMenu(
                    expanded = showingMenu,
                    onDismissRequest = { showingMenu = false },
                    containerColor = AppColors.background(isDark)
                ) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.rename)) }, onClick = {
                        showingMenu = false
                        onRename(name)
                    })
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.delete_collection), color = AppColors.red(isDark)) },
                        onClick = {
                            showingMenu = false
                            onDelete(name)
                        }
                    )
                }
            }
        }
        item(key = "new-collection") {
            val outline = AppColors.textSecondary(isDark).copy(alpha = 0.4f)
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .drawBehind {
                        drawCircle(
                            color = outline,
                            style = Stroke(
                                width = 1.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx()))
                            )
                        )
                    }
                    .clip(CircleShape)
                    .clickableWithoutRipple(onNew)
                    .semantics { contentDescription = newCollection },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

/** A name and how many scripts it holds, filled in while it's the one chosen. */
@Composable
private fun CollectionChip(
    title: String,
    count: Int,
    isSelected: Boolean,
    isDark: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val primary = AppColors.textPrimary(isDark)
    val foreground = if (isSelected) AppColors.background(isDark) else primary
    val label = "$title, $count"
    Row(
        modifier = Modifier
            .height(36.dp)
            .clip(Capsule)
            .then(
                if (isSelected) {
                    Modifier.background(primary, Capsule)
                } else {
                    Modifier.border(1.dp, AppColors.textSecondary(isDark).copy(alpha = 0.3f), Capsule)
                }
            )
            .pointerInput(onLongClick) {
                detectTapGestures(onTap = { onClick() }, onLongPress = onLongClick?.let { { _: Offset -> it() } })
            }
            .semantics {
                contentDescription = label
                selected = isSelected
            }
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(text = title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
        Text(text = "$count", fontSize = 15.sp, color = foreground.copy(alpha = 0.6f))
    }
}

/**
 * Puts a note in one of the collections, or a new one named here, or takes it
 * out of the one it's in.
 */
@Composable
private fun CollectionPicker(
    note: SavedNote,
    collections: List<String>,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onPut: (String?, String) -> Unit,
    onCreate: (String) -> Unit
) {
    var newName by remember { mutableStateOf("") }
    val current = note.collection

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.add_to_collection)) },
        text = {
            LazyColumn(modifier = Modifier.heightIn(max = 420.dp)) {
                items(collections, key = { it }) { name ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onPut(name, "add_to_collection_choose") }
                            .semantics { selected = current == name }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.CollectionsBookmark,
                            contentDescription = null,
                            tint = AppColors.textSecondary(isDark),
                            modifier = Modifier.size(20.dp)
                        )
                        Text(name, fontSize = 16.sp, color = AppColors.textPrimary(isDark), modifier = Modifier.weight(1f))
                        if (current == name) {
                            Icon(
                                imageVector = Icons.Filled.Check,
                                contentDescription = null,
                                tint = AppColors.green(isDark),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
                item(key = "new") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Add,
                            contentDescription = null,
                            tint = AppColors.textSecondary(isDark),
                            modifier = Modifier.size(20.dp)
                        )
                        BasicTextField(
                            value = newName,
                            onValueChange = { newName = it.take(40) },
                            singleLine = true,
                            textStyle = TextStyle(fontSize = 16.sp, color = AppColors.textPrimary(isDark)),
                            cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = {
                                if (newName.isNotBlank()) onCreate(newName)
                            }),
                            modifier = Modifier.weight(1f),
                            decorationBox = { field ->
                                if (newName.isEmpty()) {
                                    Text(stringResource(R.string.new_collection), fontSize = 16.sp, color = AppColors.textSecondary(isDark))
                                }
                                field()
                            }
                        )
                    }
                }
                if (current != null) {
                    item(key = "remove") {
                        HorizontalDivider(color = AppColors.textSecondary(isDark).copy(alpha = 0.15f))
                        Text(
                            text = stringResource(R.string.remove_from_named, current),
                            fontSize = 16.sp,
                            color = AppColors.red(isDark),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onPut(null, "remove_from_collection") }
                                .padding(vertical = 14.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            if (newName.isNotBlank()) {
                TextButton(onClick = { onCreate(newName) }) {
                    Text(stringResource(R.string.create), color = AppColors.blue(isDark))
                }
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

// MARK: - Rows

/**
 * A saved note's swipes: from the trailing edge to delete it, from the leading
 * edge to add it to a collection. Both spring back, and ask first.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NoteSwipe(isDark: Boolean, onDelete: () -> Unit, onCollect: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> onDelete()
                SwipeToDismissBoxValue.StartToEnd -> onCollect()
                SwipeToDismissBoxValue.Settled -> Unit
            }
            false
        }
    )
    SwipeToDismissBox(
        state = state,
        backgroundContent = {
            val isCollect = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            SwipeBackground(
                label = stringResource(if (isCollect) R.string.add_to_collection else R.string.delete),
                color = if (isCollect) AppColors.purple(isDark) else AppColors.red(isDark),
                alignsStart = isCollect
            )
        }
    ) {
        Box(modifier = Modifier.background(AppColors.background(isDark))) { content() }
    }
}

/** The draft's swipe, from the trailing edge, to discard it. It asks first. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DraftSwipe(isDark: Boolean, onDiscard: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onDiscard()
            false
        }
    )
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            SwipeBackground(label = stringResource(R.string.discard), color = AppColors.red(isDark), alignsStart = false)
        }
    ) {
        Box(modifier = Modifier.background(AppColors.background(isDark))) { content() }
    }
}

@Composable
private fun SwipeBackground(label: String, color: Color, alignsStart: Boolean) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(color)
            .padding(horizontal = 20.dp),
        contentAlignment = if (alignsStart) Alignment.CenterStart else Alignment.CenterEnd
    ) {
        Text(text = label, color = Color.White, fontWeight = FontWeight.SemiBold)
    }
}

/** A saved note's row, opened by a tap, with its menu on a touch and hold. */
@Composable
private fun NoteMenuBox(
    note: SavedNote,
    isDark: Boolean,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onCollect: () -> Unit,
    onShare: () -> Unit,
    onDelete: () -> Unit,
    onTap: () -> Unit,
    content: @Composable () -> Unit
) {
    var showingMenu by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier.pointerInput(note.id) {
            detectTapGestures(onTap = { onTap() }, onLongPress = { showingMenu = true })
        }
    ) {
        content()
        DropdownMenu(expanded = showingMenu, onDismissRequest = { showingMenu = false }, containerColor = AppColors.background(isDark)) {
            val choices = listOf(
                stringResource(R.string.open) to onOpen,
                stringResource(R.string.rename) to onRename,
                stringResource(R.string.duplicate) to onDuplicate,
                stringResource(R.string.add_to_collection) to onCollect,
                stringResource(R.string.share) to onShare
            )
            choices.forEach { (label, action) ->
                DropdownMenuItem(text = { Text(label) }, onClick = {
                    showingMenu = false
                    action()
                })
            }
            HorizontalDivider()
            DropdownMenuItem(text = { Text(stringResource(R.string.delete), color = AppColors.red(isDark)) }, onClick = {
                showingMenu = false
                onDelete()
            })
        }
    }
}

/** The draft's row, opened by a tap, with its menu on a touch and hold. */
@Composable
private fun DraftMenuBox(
    isDark: Boolean,
    onKeepWriting: () -> Unit,
    onDiscard: () -> Unit,
    onTap: () -> Unit,
    content: @Composable () -> Unit
) {
    var showingMenu by remember { mutableStateOf(false) }
    Box(modifier = Modifier.pointerInput(Unit) { detectTapGestures(onTap = { onTap() }, onLongPress = { showingMenu = true }) }) {
        content()
        DropdownMenu(expanded = showingMenu, onDismissRequest = { showingMenu = false }, containerColor = AppColors.background(isDark)) {
            DropdownMenuItem(text = { Text(stringResource(R.string.keep_writing)) }, onClick = {
                showingMenu = false
                onKeepWriting()
            })
            DropdownMenuItem(text = { Text(stringResource(R.string.discard), color = AppColors.red(isDark)) }, onClick = {
                showingMenu = false
                onDiscard()
            })
        }
    }
}

/** A date section's name, above its notes. */
@Composable
private fun GroupHeader(title: String, isDark: Boolean) {
    Text(
        text = title,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.textSecondary(isDark),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 22.dp, bottom = 2.dp)
            .semantics { heading() }
    )
}

/** The thin line under each script in the list. */
@Composable
private fun LibraryHairline(isDark: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(AppColors.textPrimary(isDark).copy(alpha = if (isDark) 0.14f else 0.12f))
    )
}

/** The yellow dot of what isn't kept safe yet, or saved yet. */
@Composable
private fun YellowDot(isDark: Boolean) {
    Box(
        modifier = Modifier
            .size(7.dp)
            .clip(CircleShape)
            .background(AppColors.yellow(isDark))
    )
}

/**
 * A script or deck in the list, with nothing around it but a line below: its
 * title, how it starts, a deck's card count and when it was edited, and the
 * takes recorded with it, which open from here.
 */
@Composable
private fun LibraryScriptRow(
    title: String,
    preview: String,
    detail: String,
    /** Draft or Unsaved, marked with a dot before the title. */
    hasBadge: Boolean,
    collection: LibraryCollectionTag?,
    takes: Int,
    recentTakes: List<Take>,
    library: TakesLibrary,
    isDark: Boolean,
    onTakes: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (hasBadge) YellowDot(isDark)
                Text(
                    text = title,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (preview.isNotEmpty()) {
                Text(
                    text = preview,
                    fontSize = 15.sp,
                    color = AppColors.textSecondary(isDark),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            LibraryMetaLine(detail = detail, collection = collection, isDark = isDark, modifier = Modifier.padding(top = 2.dp))
            if (takes > 0) {
                LibraryTakeStrip(
                    takes = takes,
                    recentTakes = recentTakes,
                    library = library,
                    frameWidth = 24.dp,
                    frameHeight = 32.dp,
                    cornerRadius = 6.dp,
                    isDark = isDark,
                    onTakes = onTakes,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
        LibraryHairline(isDark)
    }
}

/** The script open in the editor, larger, at the top of the list, opened to keep writing. */
@Composable
private fun LibraryHero(
    title: String,
    preview: String,
    detail: String,
    /** Draft or Unsaved, marked with a dot at the start of the details. */
    badge: String?,
    collection: LibraryCollectionTag?,
    takes: Int,
    recentTakes: List<Take>,
    library: TakesLibrary,
    isDark: Boolean,
    onTakes: () -> Unit
) {
    val secondary = AppColors.textSecondary(isDark)
    Column(modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
        Column(
            modifier = Modifier.padding(top = 6.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                badge?.let {
                    YellowDot(isDark)
                    Text(text = it, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = AppColors.yellow(isDark))
                    if (detail.isNotEmpty() || collection != null) Text(text = "·", fontSize = 12.sp, color = secondary)
                }
                LibraryMetaLine(detail = detail, collection = collection, isDark = isDark)
            }
            Text(
                text = title,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = AppColors.textPrimary(isDark),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            if (preview.isNotEmpty()) {
                Text(text = preview, fontSize = 15.sp, color = secondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            if (takes > 0) {
                LibraryTakeStrip(
                    takes = takes,
                    recentTakes = recentTakes,
                    library = library,
                    frameWidth = 30.dp,
                    frameHeight = 40.dp,
                    cornerRadius = 7.dp,
                    isDark = isDark,
                    onTakes = onTakes,
                    modifier = Modifier.padding(top = 10.dp)
                )
            }
        }
        LibraryHairline(isDark)
    }
}

/** A deck's card count and when it was edited, and its collection. */
@Composable
private fun LibraryMetaLine(detail: String, collection: LibraryCollectionTag?, isDark: Boolean, modifier: Modifier = Modifier) {
    val secondary = AppColors.textSecondary(isDark)
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (detail.isNotEmpty()) {
            Text(text = detail, fontSize = 12.sp, color = secondary, maxLines = 1)
        }
        collection?.let { tag ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(tag.color)
                )
                Text(text = tag.name, fontSize = 12.sp, color = secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Pictures of a script's newest takes, side by side, with how many more there are. Opens its takes. */
@Composable
private fun LibraryTakeStrip(
    takes: Int,
    recentTakes: List<Take>,
    library: TakesLibrary,
    frameWidth: Dp,
    frameHeight: Dp,
    cornerRadius: Dp,
    isDark: Boolean,
    onTakes: () -> Unit,
    modifier: Modifier = Modifier
) {
    val label = pluralStringResource(R.plurals.takes_count, takes, takes)
    val secondary = AppColors.textSecondary(isDark)
    Row(
        modifier = modifier
            .clickableWithoutRipple(onTakes)
            .semantics(mergeDescendants = true) { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        if (recentTakes.isEmpty()) {
            Icon(imageVector = Icons.Filled.VideoLibrary, contentDescription = null, tint = secondary, modifier = Modifier.size(14.dp))
            Text(text = "$takes", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondary)
        } else {
            recentTakes.forEach { take ->
                LibraryTakeThumbnail(take, library, frameWidth, frameHeight, cornerRadius)
            }
            if (takes > recentTakes.size) {
                Text(
                    text = "+${takes - recentTakes.size}",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = secondary,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
        }
    }
}

@Composable
private fun LibraryTakeThumbnail(take: Take, library: TakesLibrary, width: Dp, height: Dp, cornerRadius: Dp) {
    val density = LocalDensity.current
    val bitmap by produceState<Bitmap?>(null, take.id) {
        val (w, h) = with(density) { width.roundToPx() * 2 to height.roundToPx() * 2 }
        value = library.thumbnail(take, w, h)
    }
    Box(
        modifier = Modifier
            .size(width, height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(Color.Gray.copy(alpha = 0.25f))
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

@Composable
private fun EmptyState(query: String, kindName: String, isCards: Boolean, isDark: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = if (query.isNotEmpty()) {
                stringResource(R.string.no_results)
            } else {
                stringResource(if (isCards) R.string.no_decks_yet else R.string.no_scripts_yet)
            },
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary(isDark),
            textAlign = TextAlign.Center
        )
        Text(
            text = if (query.isNotEmpty()) {
                stringResource(R.string.nothing_matches, kindName.lowercase(Locale.getDefault()), query)
            } else {
                stringResource(if (isCards) R.string.tap_plus_deck else R.string.tap_plus_script)
            },
            fontSize = 15.sp,
            color = AppColors.textSecondary(isDark),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun LibrarySearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String,
    isDark: Boolean,
    onDone: () -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .height(48.dp)
            .glassed(Capsule, isDark),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier
                .padding(start = 14.dp, end = 8.dp)
                .size(18.dp)
        )
        Box(modifier = Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(text = placeholder, fontSize = 17.sp, color = AppColors.textSecondary(isDark), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = TextStyle(fontSize = 17.sp, color = AppColors.textPrimary(isDark)),
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, autoCorrectEnabled = false),
                keyboardActions = KeyboardActions(onDone = { onDone() }),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = placeholder }
            )
        }
        if (query.isNotEmpty()) {
            val clear = stringResource(R.string.clear_search)
            Box(
                modifier = Modifier
                    .size(44.dp, 48.dp)
                    .clickableWithoutRipple(onClear)
                    .semantics { contentDescription = clear },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Cancel,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier.size(18.dp)
                )
            }
        } else {
            Spacer(modifier = Modifier.width(14.dp))
        }
    }
}

// MARK: - Storage

/**
 * Says plainly that scripts are lost with the app until there's a storage
 * folder, and offers to choose one. Put away, it comes back every tenth time
 * the app is opened. With a folder that can't be reached, says that. Drawn like
 * a row of the list: no card, the yellow dot, and a line below.
 */
@Composable
private fun LibraryStorageBanner(isUnreachable: Boolean, isDark: Boolean, onChoose: () -> Unit, onDismiss: (() -> Unit)?) {
    val yellow = AppColors.yellow(isDark)
    val secondary = AppColors.textSecondary(isDark)
    Column(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.semantics(mergeDescendants = true) { heading() }
            ) {
                YellowDot(isDark)
                Text(
                    text = stringResource(if (isUnreachable) R.string.storage_folder_cant_be_reached else R.string.scripts_not_backed_up),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )
            }
            Text(
                text = stringResource(if (isUnreachable) R.string.storage_unreachable_detail else R.string.scripts_not_backed_up_detail),
                fontSize = 15.sp,
                color = secondary
            )
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.padding(top = 4.dp)) {
                Text(
                    text = stringResource(if (isUnreachable) R.string.choose_folder_again else R.string.choose_folder),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = yellow,
                    modifier = Modifier.clickableWithoutRipple(onChoose)
                )
                onDismiss?.let {
                    Text(
                        text = stringResource(R.string.not_now),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = secondary,
                        modifier = Modifier.clickableWithoutRipple(it)
                    )
                }
            }
        }
        LibraryHairline(isDark)
    }
}

/** Where scripts are kept, at the end of the library, with anything the storage folder couldn't take. */
@Composable
private fun LibraryFooter(
    hasFolder: Boolean,
    folderName: String?,
    oversizedFiles: List<String>,
    undeletedFiles: List<String>,
    isDark: Boolean,
    modifier: Modifier = Modifier
) {
    val oversized = when (oversizedFiles.size) {
        0 -> null
        1 -> stringResource(R.string.oversized_file, oversizedFiles.first())
        else -> stringResource(R.string.oversized_files, oversizedFiles.size)
    }
    val undeleted = when (undeletedFiles.size) {
        0 -> null
        1 -> stringResource(R.string.undeleted_file_warning, undeletedFiles.first())
        else -> stringResource(R.string.undeleted_files_warning, undeletedFiles.size)
    }
    val storage = when {
        folderName != null -> stringResource(R.string.scripts_stay_in_folder, folderName)
        hasFolder -> stringResource(R.string.scripts_stay_until_folder_back)
        else -> stringResource(R.string.scripts_stay_on_device)
    }
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        listOfNotNull(oversized, undeleted).forEach {
            FooterLine(text = it, icon = Icons.Filled.Warning, color = AppColors.yellow(isDark))
        }
        FooterLine(text = storage, icon = Icons.Filled.Lock, color = AppColors.textSecondary(isDark))
    }
}

@Composable
private fun FooterLine(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
        Text(text = text, fontSize = 12.sp, color = color, textAlign = TextAlign.Center, modifier = Modifier.weight(1f, fill = false))
    }
}

// MARK: - Takes

/** The takes of a script opened from the library, rather than the editor. */
@Composable
private fun ScriptTakes(scriptId: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val library = remember(scriptId) { TakesLibrary(context).also { it.load(scriptId) } }
    DisposableEffect(library) { onDispose { library.close() } }
    TakesView(library = library, onDismiss = onDismiss)
}

// MARK: - Text

object LibraryText {
    /** A script's words, without card breaks, images, anchors or emphasis markers, for searching and previews. */
    fun plain(content: String): String =
        RichText.plain(TeleprompterParser.removingAnchors(TeleprompterParser.removingImages(CueCards.removingSeparators(content))))

    /** The start of a script, on one line. */
    fun preview(content: String): String = plain(content).trim().take(160).replace("\n", " ")

    /**
     * When a script was edited, as told under its date section: the time today,
     * nothing yesterday, the weekday this past week, or the date.
     */
    internal fun date(date: Long, group: LibraryDateGroup): String? = when (group) {
        LibraryDateGroup.TODAY -> DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(date))
        LibraryDateGroup.YESTERDAY -> null
        LibraryDateGroup.WEEK -> SimpleDateFormat("EEEE", Locale.getDefault()).format(Date(date))
        LibraryDateGroup.MONTH, LibraryDateGroup.EARLIER -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(date))
    }

    /** The time today, Yesterday, or the date. */
    fun date(date: Long): String = when (LibraryDateGroup.of(date)) {
        LibraryDateGroup.TODAY -> DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(date))
        LibraryDateGroup.YESTERDAY -> com.thisisnsh.cuecard.android.AppStrings.get(R.string.yesterday)
        else -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(date))
    }
}

// MARK: - Sharing

/**
 * Hand a script to the share sheet as it would be written to a file, with cues
 * in `[…]` form — or, with images in it, as a TextPack, so they go with it.
 */
internal fun shareScript(context: Context, scope: CoroutineScope, title: String?, content: String, onError: (String) -> Unit) {
    val subject = title ?: context.getString(R.string.speech)
    if (TeleprompterParser.imageMatches(content).isNotEmpty()) {
        scope.launch {
            val send = runCatching {
                val file = withContext(Dispatchers.IO) { TextPack.write(context, title, content) }
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                Intent(Intent.ACTION_SEND)
                    .setType(TextPack.MIME_TYPE)
                    .putExtra(Intent.EXTRA_SUBJECT, subject)
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }.getOrNull()
            if (send == null) {
                onError(context.getString(R.string.script_couldnt_be_shared))
                return@launch
            }
            runCatching { context.startActivity(Intent.createChooser(send, null)) }
        }
        return
    }
    if (content.isBlank()) return
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, subject)
        .putExtra(Intent.EXTRA_TEXT, TeleprompterParser.normalizingTags(content))
    try {
        context.startActivity(Intent.createChooser(send, null))
    } catch (e: Exception) {
        // More text than one app can hand to another.
        onError(context.getString(R.string.script_too_long_to_share))
    }
}
