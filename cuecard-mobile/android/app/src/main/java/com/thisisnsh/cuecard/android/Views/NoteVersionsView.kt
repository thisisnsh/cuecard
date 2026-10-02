package com.thisisnsh.cuecard.android.views

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.services.NoteVersion
import com.thisisnsh.cuecard.android.services.SettingsService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

/** A line-by-line comparison of two texts. */
object LineDiff {
    enum class Kind { SAME, ADDED, REMOVED }

    data class Line(val kind: Kind, val text: String)

    /** Lines added and removed going from `old` to `new`. */
    data class Counts(val added: Int, val removed: Int)

    /**
     * The most lines compared one against another. Past this the part that
     * changed is shown as taken out and put back whole, rather than worked
     * through in more memory than it's worth.
     */
    private const val MAX_COMPARISONS = 4_000_000L

    fun lines(old: String, new: String): List<Line> {
        val oldLines = split(old)
        val newLines = split(new)

        // Most of a script is the same from one save to the next, so what
        // matches at either end is set aside before anything is compared.
        var start = 0
        while (start < oldLines.size && start < newLines.size && oldLines[start] == newLines[start]) start++
        var oldEnd = oldLines.size
        var newEnd = newLines.size
        while (oldEnd > start && newEnd > start && oldLines[oldEnd - 1] == newLines[newEnd - 1]) {
            oldEnd--
            newEnd--
        }

        val result = ArrayList<Line>(maxOf(oldLines.size, newLines.size))
        for (index in 0 until start) result.add(Line(Kind.SAME, newLines[index]))

        val removed = oldEnd - start
        val added = newEnd - start
        if (removed.toLong() * added > MAX_COMPARISONS) {
            for (index in start until oldEnd) result.add(Line(Kind.REMOVED, oldLines[index]))
            for (index in start until newEnd) result.add(Line(Kind.ADDED, newLines[index]))
        } else {
            // How many lines the rest of each side still has in common, from
            // every pair of places in them.
            val width = added + 1
            val common = IntArray((removed + 1) * width)
            for (i in removed - 1 downTo 0) {
                for (j in added - 1 downTo 0) {
                    common[i * width + j] = if (oldLines[start + i] == newLines[start + j]) {
                        common[(i + 1) * width + j + 1] + 1
                    } else {
                        maxOf(common[(i + 1) * width + j], common[i * width + j + 1])
                    }
                }
            }

            // Lines left alone pair up in order, so walking both sides together
            // puts each change where it belongs.
            var i = 0
            var j = 0
            while (i < removed || j < added) {
                if (i < removed && j < added && oldLines[start + i] == newLines[start + j]) {
                    result.add(Line(Kind.SAME, newLines[start + j]))
                    i++
                    j++
                } else if (i < removed && (j == added || common[(i + 1) * width + j] >= common[i * width + j + 1])) {
                    result.add(Line(Kind.REMOVED, oldLines[start + i]))
                    i++
                } else {
                    result.add(Line(Kind.ADDED, newLines[start + j]))
                    j++
                }
            }
        }

        for (index in newEnd until newLines.size) result.add(Line(Kind.SAME, newLines[index]))
        return result
    }

    fun counts(old: String, new: String): Counts {
        val lines = lines(old, new)
        return Counts(
            added = lines.count { it.kind == Kind.ADDED },
            removed = lines.count { it.kind == Kind.REMOVED }
        )
    }

    private fun split(text: String): List<String> =
        if (text.isEmpty()) emptyList() else text.split("\n")
}

private const val VERSIONS_SCREEN = "note_versions"

/** Every version of a saved note, newest first, to compare and restore. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteVersionsView(
    noteId: String,
    settingsService: SettingsService,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val scope = rememberCoroutineScope()
    val versionCounts by settingsService.versionCounts.collectAsState()

    var versions by remember { mutableStateOf<List<NoteVersion>>(emptyList()) }
    var changes by remember { mutableStateOf<Map<Int, LineDiff.Counts>>(emptyMap()) }
    /** The version being compared, by number, or null while the list is showing. */
    var selected by remember { mutableStateOf<Int?>(null) }
    val dateFormat = remember {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(VERSIONS_SCREEN)
    }

    LaunchedEffect(noteId, versionCounts[noteId]) {
        val loaded = settingsService.versions(noteId)
        versions = loaded
        changes = withContext(Dispatchers.Default) {
            loaded.zipWithNext().associate { (previous, version) ->
                version.number to LineDiff.counts(previous.content, version.content)
            }
        }
    }

    BackHandler(enabled = selected != null) { selected = null }

    val version = versions.firstOrNull { it.number == selected }
    if (version != null) {
        VersionDiffView(
            version = version,
            previous = versions.lastOrNull { it.number < version.number },
            isCurrent = version.number == versions.lastOrNull()?.number,
            settingsService = settingsService,
            onBack = { selected = null },
            onRestore = {
                scope.launch {
                    settingsService.restoreVersion(version, noteId)
                    onDismiss()
                }
            }
        )
        return
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Version History",
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
                                AnalyticsEvents.logButtonClick("done", VERSIONS_SCREEN)
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            items(versions.asReversed(), key = { it.number }) { item ->
                VersionRow(
                    version = item,
                    isCurrent = item.number == versions.lastOrNull()?.number,
                    change = changes[item.number],
                    timestamp = dateFormat.format(Date(item.createdAt)),
                    isDark = isDark,
                    onClick = { selected = item.number }
                )
            }
        }
    }
}

@Composable
private fun VersionRow(
    version: NoteVersion,
    isCurrent: Boolean,
    change: LineDiff.Counts?,
    timestamp: String,
    isDark: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple(onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "Version ${version.number}",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )

                if (isCurrent) {
                    Text(
                        text = "Current",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.green(isDark),
                        modifier = Modifier
                            .clip(Capsule)
                            .background(AppColors.green(isDark).copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                }

                Spacer(modifier = Modifier.weight(1f))

                change?.let {
                    Text(
                        text = "+${it.added}",
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = AppColors.green(isDark)
                    )
                    Text(
                        text = "−${it.removed}",
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = AppColors.red(isDark)
                    )
                }
            }

            Text(
                text = timestamp,
                fontSize = 12.sp,
                color = AppColors.textSecondary(isDark)
            )

            version.restoredFrom?.let { restored ->
                Text(
                    text = "Restored from Version $restored",
                    fontSize = 12.sp,
                    color = AppColors.textSecondary(isDark).copy(alpha = 0.7f)
                )
            }
        }

        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark).copy(alpha = 0.6f),
            modifier = Modifier.size(18.dp)
        )
    }
}

/** What a version is compared with. */
private enum class Comparison { PREVIOUS, EDITOR }

/** A line to show, or a run of unchanged ones folded away. */
private sealed class DiffItem {
    data class Shown(val index: Int, val line: LineDiff.Line) : DiffItem()
    data class Folded(val start: Int, val count: Int) : DiffItem()
}

/** Unchanged lines kept on show either side of a change. */
private const val DIFF_CONTEXT = 2

private fun diffItems(lines: List<LineDiff.Line>, expanded: Set<Int>): List<DiffItem> {
    val shown = BooleanArray(lines.size)
    lines.forEachIndexed { index, line ->
        if (line.kind != LineDiff.Kind.SAME) {
            for (near in maxOf(0, index - DIFF_CONTEXT)..minOf(lines.size - 1, index + DIFF_CONTEXT)) {
                shown[near] = true
            }
        }
    }

    val items = mutableListOf<DiffItem>()
    var index = 0
    while (index < lines.size) {
        if (shown[index]) {
            items.add(DiffItem.Shown(index, lines[index]))
            index++
            continue
        }
        var end = index
        while (end < lines.size && !shown[end]) end++
        val count = end - index
        if (count > 1 && index !in expanded) {
            items.add(DiffItem.Folded(index, count))
        } else {
            for (i in index until end) items.add(DiffItem.Shown(i, lines[i]))
        }
        index = end
    }
    return items
}

/**
 * What a version changed, against the one before it or against the editor,
 * with a way to bring it back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VersionDiffView(
    version: NoteVersion,
    previous: NoteVersion?,
    isCurrent: Boolean,
    settingsService: SettingsService,
    onBack: () -> Unit,
    onRestore: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val notes by settingsService.notes.collectAsState()

    var comparison by remember { mutableStateOf(Comparison.PREVIOUS) }
    var expanded by remember(comparison) { mutableStateOf(emptySet<Int>()) }
    var confirmingRestore by remember { mutableStateOf(false) }

    // Null while the comparison is being worked out.
    val lines by produceState<List<LineDiff.Line>?>(null, comparison, version, previous, notes) {
        value = withContext(Dispatchers.Default) {
            when (comparison) {
                Comparison.PREVIOUS -> LineDiff.lines(previous?.content ?: "", version.content)
                Comparison.EDITOR -> LineDiff.lines(version.content, notes)
            }
        }
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                navigationIcon = {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = AppColors.textPrimary(isDark),
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .size(20.dp)
                            .clickableWithoutRipple(onBack)
                    )
                },
                title = {
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(
                            text = "Compare Changes",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                        Text(
                            text = "Version ${version.number}",
                            fontSize = 11.sp,
                            color = AppColors.textSecondary(isDark)
                        )
                    }
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
        ) {
            SegmentedPicker(
                options = listOf(
                    previous?.let { "Version ${it.number}" } ?: "Nothing Before",
                    "Current Edit"
                ),
                selected = comparison.ordinal,
                isDark = isDark,
                onSelect = { comparison = Comparison.entries[it] },
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp)
            )

            val shownLines = lines
            when {
                shownLines == null -> Spacer(modifier = Modifier.weight(1f))

                shownLines.all { it.kind == LineDiff.Kind.SAME } -> Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(top = 24.dp),
                    contentAlignment = Alignment.TopCenter
                ) {
                    Text(
                        text = "No changes",
                        fontSize = 15.sp,
                        color = AppColors.textSecondary(isDark)
                    )
                }

                else -> {
                    val items = remember(shownLines, expanded) { diffItems(shownLines, expanded) }
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(
                            items = items,
                            key = { item ->
                                when (item) {
                                    is DiffItem.Shown -> item.index
                                    is DiffItem.Folded -> -item.start - 1
                                }
                            }
                        ) { item ->
                            when (item) {
                                is DiffItem.Shown -> DiffLine(item.line, isDark)
                                is DiffItem.Folded -> Text(
                                    text = "⋯ ${item.count} unchanged lines",
                                    fontSize = 12.sp,
                                    color = AppColors.textSecondary(isDark),
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickableWithoutRipple { expanded = expanded + item.start }
                                        .padding(vertical = 8.dp)
                                )
                            }
                        }
                    }
                }
            }

            if (!isCurrent) {
                Text(
                    text = "Restore This Version",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    color = if (isDark) Color.Black else Color.White,
                    modifier = Modifier
                        .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 12.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(AppColors.green(isDark))
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("restore_version", VERSIONS_SCREEN)
                            if (settingsService.hasUnsavedChanges) {
                                confirmingRestore = true
                            } else {
                                onRestore()
                            }
                        }
                        .padding(vertical = 14.dp)
                )
            }
        }
    }

    if (confirmingRestore) {
        AlertDialog(
            onDismissRequest = { confirmingRestore = false },
            title = { Text("Discard Unsaved Changes?") },
            text = {
                Text("The editor has changes that aren't saved. Restoring replaces them with this version.")
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmingRestore = false
                    onRestore()
                }) {
                    Text("Restore Version ${version.number}", color = AppColors.red(isDark))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingRestore = false }) {
                    Text("Cancel", color = AppColors.blue(isDark))
                }
            },
            containerColor = AppColors.background(isDark)
        )
    }
}

@Composable
private fun DiffLine(line: LineDiff.Line, isDark: Boolean) {
    val color = when (line.kind) {
        LineDiff.Kind.SAME -> Color.Transparent
        LineDiff.Kind.ADDED -> AppColors.green(isDark)
        LineDiff.Kind.REMOVED -> AppColors.red(isDark)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (line.kind == LineDiff.Kind.SAME) Color.Transparent else color.copy(alpha = 0.15f))
            .padding(horizontal = 16.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = when (line.kind) {
                LineDiff.Kind.SAME -> " "
                LineDiff.Kind.ADDED -> "+"
                LineDiff.Kind.REMOVED -> "−"
            },
            fontSize = 16.sp,
            color = color,
            modifier = Modifier.width(12.dp)
        )
        Text(
            text = line.text.ifEmpty { " " },
            fontSize = 16.sp,
            textDecoration = if (line.kind == LineDiff.Kind.REMOVED) TextDecoration.LineThrough else null,
            color = if (line.kind == LineDiff.Kind.SAME) {
                AppColors.textSecondary(isDark)
            } else {
                AppColors.textPrimary(isDark)
            },
            modifier = Modifier.weight(1f)
        )
    }
}

/** Two or more choices side by side, the one picked lifted off the rest. */
@Composable
private fun SegmentedPicker(
    options: List<String>,
    selected: Int,
    isDark: Boolean,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val track = AppColors.textSecondary(isDark).copy(alpha = 0.12f)
    val thumb = AppColors.textPrimary(isDark)
        .copy(alpha = if (isDark) 0.22f else 0.0f)
        .compositeOver(if (isDark) AppColors.background(isDark) else Color.White)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(9.dp))
            .background(track)
            .padding(2.dp)
    ) {
        options.forEachIndexed { index, label ->
            Text(
                text = label,
                fontSize = 13.sp,
                fontWeight = if (index == selected) FontWeight.SemiBold else FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 1,
                color = AppColors.textPrimary(isDark),
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (index == selected) thumb else Color.Transparent)
                    .clickableWithoutRipple { onSelect(index) }
                    .padding(vertical = 7.dp)
            )
        }
    }
}
