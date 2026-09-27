package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.TimerStyle
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import kotlinx.coroutines.launch
import java.util.Locale

private const val TIMER_SCREEN = "timer"

/** The height of a row of wheels, and of the wheels in it. */
private val WHEEL_ROW_HEIGHT = 88.dp

/**
 * The timer for the mode being written in: how long it runs, when it warns, the
 * countdown before it, and the colors it turns.
 */
@Composable
fun TimerSheet(
    settingsService: SettingsService,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val scope = rememberCoroutineScope()
    val settings by settingsService.settings.collectAsState()

    fun update(change: (TeleprompterSettings) -> TeleprompterSettings) {
        scope.launch { settingsService.update(change) }
    }

    val duration = settings.activeTimerDurationSeconds
    val style = settings.activeTimerStyle
    /** Only the teleprompter has a countdown. */
    val isTeleprompter = settings.scriptMode == ScriptMode.TELEPROMPTER

    fun setStyle(newStyle: TimerStyle) = update { it.withActiveTimerStyle(newStyle) }

    // Keep the warning short of a duration that was shortened under it.
    val openedDuration = remember { duration }
    LaunchedEffect(duration) {
        if (duration == openedDuration) return@LaunchedEffect
        val latest = maxOf(duration - 1, 0)
        if (style.warningSeconds > latest) setStyle(style.copy(warningSeconds = latest))
    }

    val footer = buildList {
        if (duration > 0) add("0:00 turns off the timer.")
        if (isTeleprompter) add("Countdown is the time before the script starts scrolling.")
    }.joinToString(" ")

    SettingsScreen(
        screen = TIMER_SCREEN,
        title = if (isTeleprompter) "Teleprompter Timer" else "Cards Timer",
        onDismiss = onDismiss
    ) {
        SettingsSection(isDark = isDark) {
            TimerPreview(duration = duration, style = style, isDark = isDark)
        }

        SettingsSection(isDark = isDark, footer = footer.ifEmpty { null }) {
            TimeRow(
                title = "Duration",
                minutes = duration / 60,
                minuteRange = 0..59,
                onMinutes = { minutes -> update { it.withActiveTimer(minutes, duration % 60) } },
                seconds = duration % 60,
                secondRange = 0..59,
                onSeconds = { seconds -> update { it.withActiveTimer(duration / 60, seconds) } },
                isDark = isDark
            )

            if (duration > 1) {
                WarningRow(duration = duration, style = style, isDark = isDark, onStyle = ::setStyle)
            }

            if (isTeleprompter) {
                CountdownRow(
                    seconds = settings.countdownSeconds,
                    isDark = isDark,
                    onSeconds = { seconds -> update { it.copy(countdownSeconds = seconds) } }
                )
            }
        }

        TimerColorsSection(
            style = style,
            showsCountdown = isTeleprompter && settings.countdownSeconds > 0,
            isTimed = duration > 0,
            isDark = isDark,
            onStyle = ::setStyle
        )
    }
}

/**
 * The timer at each of its colors: at the start, at the warning, and at zero.
 * Untimed, just the count up from zero.
 */
@Composable
private fun TimerPreview(duration: Int, style: TimerStyle, isDark: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 16.dp)
    ) {
        if (duration == 0) {
            TimerStage("Counts Up", seconds = 0, color = style.normalColor, isDark = isDark)
        } else {
            TimerStage("Start", seconds = duration, color = style.normalColor, isDark = isDark)
            if (style.warningSeconds > 0) {
                TimerStage("Warning", seconds = style.warningSeconds, color = style.warningColor, isDark = isDark)
            }
            TimerStage("Overtime", seconds = 0, color = style.overtimeColor, isDark = isDark)
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TimerStage(
    title: String,
    seconds: Int,
    color: CueColor,
    isDark: Boolean
) {
    Column(
        modifier = Modifier
            .weight(1f)
            .semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = formatTimer(seconds),
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = color.color(isDark)
        )
        Text(
            text = title,
            fontSize = 12.sp,
            color = AppColors.textSecondary(isDark)
        )
    }
}

/** The time left to warn at, always short of the duration. 0:00 is off. */
@Composable
private fun WarningRow(duration: Int, style: TimerStyle, isDark: Boolean, onStyle: (TimerStyle) -> Unit) {
    val latest = maxOf(duration - 1, 0)
    val warning = style.warningSeconds
    TimeRow(
        title = "Warn in Last",
        minutes = warning / 60,
        minuteRange = 0..(latest / 60),
        onMinutes = { onStyle(style.copy(warningSeconds = minOf(it * 60 + warning % 60, latest))) },
        seconds = warning % 60,
        secondRange = if (warning / 60 == latest / 60) 0..(latest % 60) else 0..59,
        onSeconds = { onStyle(style.copy(warningSeconds = minOf(warning / 60 * 60 + it, latest))) },
        isDark = isDark
    )
}

/** Seconds of countdown before the script scrolls. Zero starts at once. */
@Composable
private fun CountdownRow(seconds: Int, isDark: Boolean, onSeconds: (Int) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(WHEEL_ROW_HEIGHT)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        RowTitle("Countdown", isDark)
        Spacer(modifier = Modifier.weight(1f))
        WheelPicker(
            label = "Countdown seconds",
            range = TeleprompterSettings.COUNTDOWN_RANGE,
            selected = seconds,
            onSelect = onSeconds,
            format = { it.toString() },
            isDark = isDark
        )
        WheelUnit("sec", isDark)
    }
}

/** A title, and small minute and second wheels beside it. */
@Composable
private fun TimeRow(
    title: String,
    minutes: Int,
    minuteRange: IntRange,
    onMinutes: (Int) -> Unit,
    seconds: Int,
    secondRange: IntRange,
    onSeconds: (Int) -> Unit,
    isDark: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(WHEEL_ROW_HEIGHT)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        RowTitle(title, isDark)
        Spacer(modifier = Modifier.weight(1f))
        WheelPicker(
            label = "$title minutes",
            range = minuteRange,
            selected = minutes,
            onSelect = onMinutes,
            format = { it.toString() },
            isDark = isDark
        )
        WheelUnit("min", isDark)
        WheelPicker(
            label = "$title seconds",
            range = secondRange,
            selected = seconds,
            onSelect = onSeconds,
            format = { String.format(Locale.US, "%02d", it) },
            isDark = isDark
        )
        WheelUnit("sec", isDark)
    }
}

@Composable
private fun RowTitle(text: String, isDark: Boolean) {
    Text(text = text, fontSize = 17.sp, color = AppColors.textPrimary(isDark))
}

/** What a wheel beside it counts, lined up across the rows. */
@Composable
private fun WheelUnit(text: String, isDark: Boolean) {
    Text(
        text = text,
        fontSize = 15.sp,
        color = AppColors.textSecondary(isDark),
        modifier = Modifier.width(28.dp)
    )
}

/**
 * The colors the mode's timer turns, from the countdown before it to running
 * over. Only the ones it will use are shown: untimed, there's no Warning or
 * Overtime, and each of Countdown and Warning goes when it's off.
 */
@Composable
private fun TimerColorsSection(
    style: TimerStyle,
    showsCountdown: Boolean,
    isTimed: Boolean,
    isDark: Boolean,
    onStyle: (TimerStyle) -> Unit
) {
    // The colors as they come, keeping the warning time.
    val defaultColors = TimerStyle.DEFAULT.copy(warningSeconds = style.warningSeconds)

    SettingsSection(title = "Timer Colors", isDark = isDark) {
        if (showsCountdown) {
            ColorSwatchRow("Countdown", style.countdownColor, isDark) { onStyle(style.copy(countdownColor = it)) }
        }
        ColorSwatchRow("Normal", style.normalColor, isDark) { onStyle(style.copy(normalColor = it)) }
        if (isTimed) {
            if (style.warningSeconds > 0) {
                ColorSwatchRow("Warning", style.warningColor, isDark) { onStyle(style.copy(warningColor = it)) }
            }
            ColorSwatchRow("Overtime", style.overtimeColor, isDark) { onStyle(style.copy(overtimeColor = it)) }
        }

        if (style != defaultColors) {
            Text(
                text = "Reset Timer Colors",
                fontSize = 17.sp,
                color = AppColors.blue(isDark),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickableWithoutRipple {
                        AnalyticsEvents.logButtonClick("reset_timer_colors", TIMER_SCREEN)
                        onStyle(defaultColors)
                    }
                    .padding(horizontal = 20.dp, vertical = 12.dp)
            )
        }
    }
}

/** Time the way the timer button shows it: 1:00, 0:10. */
internal fun formatTimer(seconds: Int): String =
    String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)

/**
 * A wheel of numbers to pick one from.
 *
 * SwiftUI has a wheel picker; Compose does not, so this is a snapping list three
 * items tall with the chosen value in the middle. A new range starts it over, so
 * it never scrolls past the values it now holds.
 */
@Composable
private fun WheelPicker(
    label: String,
    range: IntRange,
    selected: Int,
    onSelect: (Int) -> Unit,
    format: (Int) -> String,
    isDark: Boolean
) {
    key(range) {
        RangeWheel(label, range, selected, onSelect, format, isDark)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RangeWheel(
    label: String,
    range: IntRange,
    selected: Int,
    onSelect: (Int) -> Unit,
    format: (Int) -> String,
    isDark: Boolean
) {
    val itemHeight = WHEEL_ROW_HEIGHT / 3
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
            .width(56.dp)
            .height(WHEEL_ROW_HEIGHT)
            .semantics { contentDescription = "$label, ${format(selected)}" }
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
