package com.thisisnsh.cuecard.android.views

import com.thisisnsh.cuecard.android.AppStrings
import androidx.annotation.StringRes
import com.thisisnsh.cuecard.android.R
import androidx.compose.ui.res.stringResource
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.FormatAlignLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.ViewCarousel
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.services.TakesLibrary
import com.thisisnsh.cuecard.android.services.WhatsNewService

// MARK: - Pages

/**
 * The screens with a help button. Every one shows the same help; the page only
 * tells analytics where it was opened.
 */
enum class HelpPage(val rawValue: String) {
    WRITING_TELEPROMPTER("home_teleprompter"),
    WRITING_CARDS("home_cards"),
    TELEPROMPTER("teleprompter"),
    CARDS("cards");

    companion object {
        /** The editor's page for the mode it's writing in. */
        fun writing(mode: ScriptMode): HelpPage =
            if (mode == ScriptMode.CARDS) WRITING_CARDS else WRITING_TELEPROMPTER
    }
}

private data class HelpTopic(@StringRes val titleRes: Int, @StringRes val detailRes: Int) {
    val title: String get() = AppStrings.get(titleRes)
    val detail: String get() = AppStrings.get(detailRes)

    fun matches(query: String): Boolean =
        title.contains(query, ignoreCase = true) || detail.contains(query, ignoreCase = true)
}

private data class HelpSection(
    /** Names the section in analytics, the same in every language. */
    val id: String,
    @StringRes val titleRes: Int,
    /** What's in it, under the title on the front page. */
    @StringRes val summaryRes: Int,
    val icon: ImageVector,
    val topics: List<HelpTopic>
) {
    val title: String get() = AppStrings.get(titleRes)
    val summary: String get() = AppStrings.get(summaryRes)

    /** The same section with only the topics that match `query`. */
    fun filtered(query: String): HelpSection = copy(topics = topics.filter { it.matches(query) })
}

// MARK: - Topics

private object AllHelp {
    val writing = HelpSection(
        "writing", R.string.help_writing, R.string.help_writing_summary, Icons.Filled.Edit,
        listOf(
            HelpTopic(R.string.help_pick_a_mode_title, R.string.help_pick_a_mode_detail),
            HelpTopic(R.string.help_add_cues_title, R.string.help_add_cues_detail),
            HelpTopic(R.string.help_bold_and_italic_title, R.string.help_bold_and_italic_detail),
            HelpTopic(R.string.help_add_cards_title, R.string.help_add_cards_detail)
        )
    )

    val notes = HelpSection(
        "notes", R.string.help_notes, R.string.help_notes_summary, Icons.Filled.Folder,
        listOf(
            HelpTopic(R.string.help_save_your_work_title, R.string.help_save_your_work_detail),
            HelpTopic(R.string.help_open_saved_notes_title, R.string.help_open_saved_notes_detail),
            HelpTopic(R.string.help_import_a_text_file_title, R.string.help_import_a_text_file_detail),
            HelpTopic(R.string.help_go_back_to_an_older_version_title, R.string.help_go_back_to_an_older_version_detail),
            HelpTopic(R.string.help_keep_notes_if_the_app_is_removed_title, R.string.help_keep_notes_if_the_app_is_removed_detail),
            HelpTopic(R.string.help_share_a_script_title, R.string.help_share_a_script_detail)
        )
    )

    val settings = HelpSection(
        "settings", R.string.help_settings, R.string.help_settings_summary, Icons.Filled.Settings,
        listOf(
            HelpTopic(R.string.help_change_text_size_and_colors_title, R.string.help_change_text_size_and_colors_detail),
            HelpTopic(R.string.help_set_a_timer_title, R.string.help_set_a_timer_detail),
            HelpTopic(R.string.help_count_down_title, R.string.help_count_down_detail),
            HelpTopic(R.string.help_change_language_title, R.string.help_change_language_detail)
        )
    )

    val teleprompter = HelpSection(
        "teleprompter", R.string.teleprompter, R.string.help_teleprompter_summary,
        Icons.AutoMirrored.Filled.FormatAlignLeft,
        listOf(
            HelpTopic(R.string.help_play_and_pause_title, R.string.help_play_and_pause_detail),
            HelpTopic(R.string.help_scroll_by_hand_title, R.string.help_scroll_by_hand_detail),
            HelpTopic(R.string.help_change_speed_title, R.string.help_change_speed_detail),
            HelpTopic(R.string.help_record_in_cuecard_title, R.string.help_record_in_cuecard_detail),
            HelpTopic(R.string.help_record_in_step_title, R.string.help_record_in_step_detail),
            HelpTopic(R.string.mirror_text, R.string.help_mirror_text_detail),
            HelpTopic(R.string.help_use_over_other_apps_title, R.string.help_use_over_other_apps_detail),
            HelpTopic(R.string.help_watch_the_timer_title, R.string.help_watch_the_timer_detail)
        )
    )

    val cards = HelpSection(
        "cards", R.string.cards, R.string.help_cards_summary, Icons.Filled.ViewCarousel,
        listOf(
            HelpTopic(R.string.help_turn_cards_title, R.string.help_turn_cards_detail),
            HelpTopic(R.string.help_record_with_cards_title, R.string.help_record_with_cards_detail),
            HelpTopic(R.string.help_count_up_title, R.string.help_watch_the_timer_cards_detail)
        )
    )

    val takes = HelpSection(
        "takes", R.string.takes, R.string.help_takes_summary, Icons.Filled.VideoLibrary,
        listOfNotNull(
            HelpTopic(R.string.find_your_takes, R.string.help_find_your_takes_detail),
            HelpTopic(R.string.help_move_camera_title, R.string.help_move_camera_detail),
            HelpTopic(R.string.help_play_a_take_title, R.string.help_play_a_take_detail),
            // Favorites are kept on a video from Android 11.
            if (TakesLibrary.canFavorite) {
                HelpTopic(R.string.help_favorite_a_take_title, R.string.help_favorite_a_take_detail)
            } else {
                null
            },
            HelpTopic(R.string.help_delete_a_take_title, R.string.help_delete_a_take_detail),
            HelpTopic(R.string.help_where_takes_are_kept_title, R.string.help_where_takes_are_kept_detail)
        )
    )

    val sections = listOf(writing, notes, settings, teleprompter, cards, takes)
}

// MARK: - Help Screen

private const val HELP_SCREEN = "help"

/**
 * The same help on every page: a front page of sections, each opening to its
 * topics, with a search across all of them.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpView(page: HelpPage, onDismiss: () -> Unit) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val whatsNew = remember { WhatsNewService.getInstance(context) }
    val release = whatsNew.release

    var query by remember { mutableStateOf("") }
    var showingWhatsNew by remember { mutableStateOf(false) }
    /** The section open on its own page, or null on the front page. */
    var openSectionId by remember { mutableStateOf<String?>(null) }
    val openSection = AllHelp.sections.firstOrNull { it.id == openSectionId }

    val trimmed = query.trim()
    // The sections with a topic that matches the search.
    val results = AllHelp.sections.map { it.filtered(trimmed) }.filter { it.topics.isNotEmpty() }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logEvent(
            "screen_view",
            mapOf("screen_name" to HELP_SCREEN, "screen_class" to "HelpView", "page" to page.rawValue)
        )
    }

    BackHandler(enabled = openSection != null) { openSectionId = null }

    /** Closes the whole of Help, from the front page or a section. */
    fun close() {
        AnalyticsEvents.logButtonClick("done", HELP_SCREEN)
        onDismiss()
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                navigationIcon = {
                    if (openSection != null) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .size(20.dp)
                                .clickableWithoutRipple { openSectionId = null }
                        )
                    }
                },
                title = {
                    Text(
                        text = openSection?.title ?: stringResource(R.string.help),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                },
                actions = {
                    Text(
                        text = stringResource(R.string.done),
                        fontSize = 17.sp,
                        color = AppColors.blue(isDark),
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .clickableWithoutRipple(::close)
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
        ) {
            if (openSection != null) {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    item { Spacer(modifier = Modifier.height(8.dp)) }
                    items(openSection.topics, key = { it.titleRes }) { topic ->
                        TopicRow(topic, isDark)
                    }
                    item { Spacer(modifier = Modifier.height(32.dp)) }
                }
                return@Column
            }

            SearchField(query = query, onQueryChange = { query = it }, isDark = isDark)

            if (trimmed.isNotEmpty() && results.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.no_results_for, trimmed),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textPrimary(isDark)
                    )
                }
                return@Column
            }

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                if (trimmed.isEmpty()) {
                    item {
                        Spacer(modifier = Modifier.height(8.dp))
                        LinkRow(title = stringResource(R.string.report_a_bug), icon = Icons.Filled.BugReport, isDark = isDark) {
                            AnalyticsEvents.logButtonClick("report_bug", HELP_SCREEN)
                            openLink(context, AppLinks.bugReport)
                        }
                        LinkRow(title = stringResource(R.string.request_a_feature), icon = Icons.Filled.Lightbulb, isDark = isDark) {
                            AnalyticsEvents.logButtonClick("request_feature", HELP_SCREEN)
                            openLink(context, AppLinks.featureRequest)
                        }
                        HelpDivider(isDark)
                        if (release != null) {
                            LinkRow(
                                title = stringResource(R.string.whats_new_in, whatsNew.version),
                                icon = Icons.Filled.AutoAwesome,
                                isDark = isDark
                            ) {
                                AnalyticsEvents.logButtonClick("whats_new", HELP_SCREEN)
                                showingWhatsNew = true
                            }
                            HelpDivider(isDark)
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                    items(AllHelp.sections, key = { it.id }) { section ->
                        SectionRow(section, isDark) {
                            AnalyticsEvents.logButtonClick("section_${section.id}", HELP_SCREEN)
                            openSectionId = section.id
                        }
                    }
                } else {
                    results.forEach { section ->
                        item(key = section.id) {
                            Text(
                                text = section.title,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.textSecondary(isDark),
                                modifier = Modifier.padding(start = 20.dp, top = 24.dp, bottom = 4.dp)
                            )
                        }
                        // Search results start open, so the match shows.
                        items(section.topics, key = { section.id + it.titleRes }) { topic ->
                            TopicRow(topic, isDark, initiallyExpanded = true)
                        }
                    }
                }

                item { Spacer(modifier = Modifier.height(32.dp)) }
            }
        }
    }

    if (showingWhatsNew && release != null) {
        WhatsNewDialog(release = release, version = whatsNew.version, onDismiss = { showingWhatsNew = false })
    }
}

@Composable
private fun HelpDivider(isDark: Boolean) {
    HorizontalDivider(
        color = AppColors.textSecondary(isDark).copy(alpha = 0.15f),
        modifier = Modifier.padding(vertical = 8.dp)
    )
}

/** A section on the front page: its icon, title and what's in it. */
@Composable
private fun SectionRow(section: HelpSection, isDark: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple(onClick)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Icon(
            imageVector = section.icon,
            contentDescription = null,
            tint = AppColors.textPrimary(isDark),
            modifier = Modifier.size(22.dp)
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text = section.title, fontSize = 17.sp, color = AppColors.textPrimary(isDark))
            Text(text = section.summary, fontSize = 13.sp, color = AppColors.textSecondary(isDark))
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
internal fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    isDark: Boolean,
    placeholder: String = stringResource(R.string.search_help)
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(AppColors.textSecondary(isDark).copy(alpha = 0.12f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(18.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Box(modifier = Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(text = placeholder, fontSize = 17.sp, color = AppColors.textSecondary(isDark))
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = TextStyle(fontSize = 17.sp, color = AppColors.textPrimary(isDark)),
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

/** A topic's title, and its explanation once opened. */
@Composable
private fun TopicRow(topic: HelpTopic, isDark: Boolean, initiallyExpanded: Boolean = false) {
    var isExpanded by remember(topic.titleRes) { mutableStateOf(initiallyExpanded) }
    val rotation by animateFloatAsState(if (isExpanded) 180f else 0f, tween(250), label = "chevron")

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple { isExpanded = !isExpanded }
            .padding(horizontal = 20.dp, vertical = 10.dp)
            .animateContentSize(tween(250)),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = topic.title,
                fontSize = 17.sp,
                color = AppColors.textPrimary(isDark),
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier
                    .size(18.dp)
                    .rotate(rotation)
            )
        }
        if (isExpanded) {
            Text(text = topic.detail, fontSize = 13.sp, color = AppColors.textSecondary(isDark))
        }
    }
}

// MARK: - Help Button

/** The question mark at the top right of a page. */
@Composable
fun HelpButton(page: HelpPage, isDark: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Icon(
        imageVector = Icons.Filled.QuestionMark,
        contentDescription = stringResource(R.string.help),
        tint = AppColors.textPrimary(isDark),
        modifier = modifier
            .padding(horizontal = 12.dp)
            .size(20.dp)
            .clickableWithoutRipple {
                AnalyticsEvents.logButtonClick("help", page.rawValue)
                onClick()
            }
    )
}

/**
 * The help screen for `page`, sliding up over the page like its other screens.
 * Kept on the page rather than the button, so it stays up if the button fades.
 */
@Composable
fun HelpOverlay(page: HelpPage, visible: Boolean, onDismiss: () -> Unit) {
    AnimatedVisibility(
        visible = visible,
        enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
        exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
    ) {
        HelpView(page = page, onDismiss = onDismiss)
    }
}
