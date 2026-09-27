package com.thisisnsh.cuecard.android.views

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
    SAVED_CONTENT("saved_notes"),
    TELEPROMPTER("teleprompter"),
    CARDS("cards");

    companion object {
        /** The editor's page for the mode it's writing in. */
        fun writing(mode: ScriptMode): HelpPage =
            if (mode == ScriptMode.CARDS) WRITING_CARDS else WRITING_TELEPROMPTER
    }
}

private data class HelpTopic(val title: String, val detail: String) {
    fun matches(query: String): Boolean =
        title.contains(query, ignoreCase = true) || detail.contains(query, ignoreCase = true)
}

private data class HelpSection(val title: String, val topics: List<HelpTopic>)

// MARK: - Topics

private object AllHelp {
    val general = HelpSection(
        "General",
        listOf(
            HelpTopic(
                "Pick a Mode",
                "Tap the mode name at the top left. Teleprompter scrolls your whole script. " +
                    "Cards shows it one card at a time."
            ),
            HelpTopic(
                "Add Cues",
                "Cues are reminders like [cue pause], shown in color and not meant to be read out. " +
                    "Type [ (square bracket) or tap Add Cue above the keyboard to add one."
            ),
            HelpTopic(
                "Set a Timer",
                "Tap the timer next to Play and choose how long you have to speak " +
                    "and when it warns you. It shows while you present."
            ),
            HelpTopic(
                "Save and Open",
                "Use the ⋮ menu to save your script or deck, or open one you saved. " +
                    "Import or export text files there too."
            ),
            HelpTopic(
                "Rename or Delete",
                "Everything you save is in Saved Content. " +
                    "Swipe right on one to rename it, or swipe left to delete it."
            ),
            HelpTopic(
                "Change Text Size",
                "Each mode keeps its own text size and colors in Settings. " +
                    "Tap Show Advanced Settings to type an exact size."
            ),
            HelpTopic(
                "Change Colors",
                "Pick colors that are easy for you to tell apart. " +
                    "Set the cue color in Settings, and the timer colors in the timer."
            )
        )
    )

    val teleprompter = HelpSection(
        "Teleprompter",
        listOf(
            HelpTopic(
                "Play and Pause",
                "The buttons fade while the script scrolls so they stay out of the way. " +
                    "Tap the screen to show them again."
            ),
            HelpTopic(
                "Scroll by Hand",
                "Drag the script to go back or skip ahead. " +
                    "It keeps scrolling from where you leave it."
            ),
            HelpTopic(
                "Change Speed",
                "Scroll Speed in Settings sets how many lines pass each minute. " +
                    "Set a Countdown in the timer to get a few seconds before it starts."
            ),
            HelpTopic(
                "Use Over Other Apps",
                "Leave CueCard while the teleprompter is open and your script keeps going " +
                    "in a floating window, handy on video calls."
            ),
            HelpTopic(
                "Watch the Timer",
                "The timer changes color when you're near the end " +
                    "and again once you're over time. Pick the colors in the timer."
            )
        )
    )

    val cards = HelpSection(
        "Cards",
        listOf(
            HelpTopic(
                "Add Cards",
                "Each box in the editor is one card. " +
                    "Tap Create New Card to add another."
            ),
            HelpTopic(
                "Turn Cards",
                "Swipe, or tap Back and Next. " +
                    "The dots at the top show which card you're on."
            ),
            HelpTopic(
                "Watch the Timer",
                "The time at the top counts down your timer. " +
                    "With no timer set, it counts up from when you started."
            )
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
                        text = "Help",
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
                        text = "No Results for “$trimmed”",
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
                                title = "What's New in ${whatsNew.version}",
                                icon = Icons.Filled.AutoAwesome,
                                isDark = isDark
                            ) {
                                AnalyticsEvents.logButtonClick("whats_new", HELP_SCREEN)
                                showingWhatsNew = true
                            }
                        }
                        LinkRow(title = "Email Support", icon = Icons.Filled.Email, isDark = isDark) {
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
private fun SearchField(query: String, onQueryChange: (String) -> Unit, isDark: Boolean) {
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
                Text(text = "Search Help", fontSize = 17.sp, color = AppColors.textSecondary(isDark))
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
        contentDescription = "Help",
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
