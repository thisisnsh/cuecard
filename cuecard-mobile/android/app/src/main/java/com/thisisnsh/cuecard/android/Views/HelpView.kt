package com.thisisnsh.cuecard.android.views

import com.thisisnsh.cuecard.android.AppStrings
import androidx.annotation.StringRes
import com.thisisnsh.cuecard.android.R
import androidx.compose.ui.res.stringResource
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Email
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

private data class HelpSection(@StringRes val titleRes: Int, val topics: List<HelpTopic>) {
    val title: String get() = AppStrings.get(titleRes)
}

// MARK: - Topics

private object AllHelp {
    val general = HelpSection(
        R.string.help_general,
        listOf(
            HelpTopic(R.string.help_pick_a_mode_title, R.string.help_pick_a_mode_detail),
            HelpTopic(R.string.help_add_cues_title, R.string.help_add_cues_detail),
            HelpTopic(R.string.help_bold_and_italic_title, R.string.help_bold_and_italic_detail),
            HelpTopic(R.string.help_set_a_timer_title, R.string.help_set_a_timer_detail),
            HelpTopic(R.string.help_save_your_work_title, R.string.help_save_your_work_detail),
            HelpTopic(R.string.help_open_saved_notes_title, R.string.help_open_saved_notes_detail),
            HelpTopic(R.string.help_import_a_text_file_title, R.string.help_import_a_text_file_detail),
            HelpTopic(R.string.help_go_back_to_an_older_version_title, R.string.help_go_back_to_an_older_version_detail),
            HelpTopic(R.string.help_keep_notes_if_the_app_is_removed_title, R.string.help_keep_notes_if_the_app_is_removed_detail),
            HelpTopic(R.string.help_share_a_script_title, R.string.help_share_a_script_detail),
            HelpTopic(R.string.help_change_text_size_and_colors_title, R.string.help_change_text_size_and_colors_detail)
        )
    )

    val teleprompter = HelpSection(
        R.string.teleprompter,
        listOf(
            HelpTopic(R.string.help_play_and_pause_title, R.string.help_play_and_pause_detail),
            HelpTopic(R.string.help_scroll_by_hand_title, R.string.help_scroll_by_hand_detail),
            HelpTopic(R.string.help_change_speed_title, R.string.help_change_speed_detail),
            HelpTopic(R.string.help_use_over_other_apps_title, R.string.help_use_over_other_apps_detail),
            HelpTopic(R.string.help_watch_the_timer_title, R.string.help_watch_the_timer_detail)
        )
    )

    val cards = HelpSection(
        R.string.cards,
        listOf(
            HelpTopic(R.string.help_add_cards_title, R.string.help_add_cards_detail),
            HelpTopic(R.string.help_turn_cards_title, R.string.help_turn_cards_detail),
            HelpTopic(R.string.help_watch_the_timer_title, R.string.help_watch_the_timer_cards_detail)
        )
    )

    val sections = listOf(general, teleprompter, cards)
}

// MARK: - Help Screen

private const val HELP_SCREEN = "help"

/** The same help on every page, grouped by part of the app. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpView(page: HelpPage, onDismiss: () -> Unit) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val whatsNew = remember { WhatsNewService.getInstance(context) }
    val release = whatsNew.release

    var query by remember { mutableStateOf("") }
    var showingWhatsNew by remember { mutableStateOf(false) }

    val trimmed = query.trim()
    val sections = if (trimmed.isEmpty()) {
        AllHelp.sections
    } else {
        AllHelp.sections
            .map { section -> section.copy(topics = section.topics.filter { it.matches(trimmed) }) }
            .filter { it.topics.isNotEmpty() }
    }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logEvent(
            "screen_view",
            mapOf("screen_name" to HELP_SCREEN, "screen_class" to "HelpView", "page" to page.rawValue)
        )
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.help),
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
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("done", HELP_SCREEN)
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
        ) {
            SearchField(query = query, onQueryChange = { query = it }, isDark = isDark)

            if (sections.isEmpty()) {
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
                if (query.isEmpty()) {
                    item {
                        Spacer(modifier = Modifier.height(8.dp))
                        if (release != null) {
                            LinkRow(
                                title = stringResource(R.string.whats_new_in, whatsNew.version),
                                icon = Icons.Filled.AutoAwesome,
                                isDark = isDark
                            ) {
                                AnalyticsEvents.logButtonClick("whats_new", HELP_SCREEN)
                                showingWhatsNew = true
                            }
                        }
                        LinkRow(title = stringResource(R.string.email_support), icon = Icons.Filled.Email, isDark = isDark) {
                            AnalyticsEvents.logButtonClick("email_support", HELP_SCREEN)
                            openLink(context, AppLinks.SUPPORT_EMAIL)
                        }
                        HorizontalDivider(
                            color = AppColors.textSecondary(isDark).copy(alpha = 0.15f),
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                }

                sections.forEach { section ->
                    item(key = section.title) {
                        Text(
                            text = section.title,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textSecondary(isDark),
                            modifier = Modifier.padding(start = 20.dp, top = 24.dp, bottom = 4.dp)
                        )
                    }
                    items(section.topics, key = { section.title + it.title }) { topic ->
                        TopicRow(topic, isDark)
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

@Composable
private fun TopicRow(topic: HelpTopic, isDark: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(text = topic.title, fontSize = 17.sp, color = AppColors.textPrimary(isDark))
        Text(text = topic.detail, fontSize = 13.sp, color = AppColors.textSecondary(isDark))
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
