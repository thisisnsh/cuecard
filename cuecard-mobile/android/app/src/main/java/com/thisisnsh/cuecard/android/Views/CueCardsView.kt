package com.thisisnsh.cuecard.android.views

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.models.annotated
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.floor

private const val CARDS_SCREEN = "cards"

/** How far a card has to be dragged to count as a swipe. */
private val SWIPE_DISTANCE = 90.dp

/** How far below the top card each card behind it peeks out. */
private val PEEK = 14.dp

private val CARD_CORNER_RADIUS = 28.dp

/** The deck's spring: the SwiftUI one with a 0.4 s response and 0.84 damping. */
private fun <T> deckSpring() = spring<T>(dampingRatio = 0.84f, stiffness = 247f)

/** Cards mode: one card at a time, with a timer running from when the deck opened. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CueCardsView(
    cards: List<String>,
    title: String,
    settings: TeleprompterSettings,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val scope = rememberCoroutineScope()

    var index by remember { mutableIntStateOf(0) }
    /**
     * Where the deck is, in cards: the index at rest, and between two while a
     * card is being dragged or is settling. Every card is placed from it.
     */
    val position = remember { Animatable(0f) }
    /** A pull past either end of the deck, which gives a little and settles. */
    var rubberBand by remember { mutableFloatStateOf(0f) }
    var showingHelp by remember { mutableStateOf(false) }

    // The timer as it was set when the deck was opened, running from then.
    val startedAt = remember { System.currentTimeMillis() }
    val timerDuration = remember { settings.cards.timerDurationSeconds }
    val timerStyle = remember { settings.cards.timerStyle }
    var now by remember { mutableLongStateOf(startedAt) }

    val isFinished = index >= cards.size

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(CARDS_SCREEN)
        AnalyticsEvents.logEvent("cards_open", mapOf("count" to cards.size))
    }

    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000 - (now - startedAt) % 1000)
        }
    }

    fun show(newIndex: Int) {
        index = newIndex.coerceIn(0, cards.size)
        scope.launch { position.animateTo(index.toFloat(), deckSpring()) }
    }

    fun next() {
        if (index < cards.size) show(index + 1)
    }

    fun previous() {
        if (index > 0) show(index - 1)
    }

    fun close() {
        AnalyticsEvents.logButtonClick("close", CARDS_SCREEN)
        onDismiss()
    }

    BackHandler(enabled = !showingHelp) { close() }

    val elapsed = ((now - startedAt) / 1000).toInt()
    val seconds = if (timerDuration > 0) timerDuration - elapsed else elapsed
    val timerColor = timerStyle.color(remaining = timerDuration - elapsed, duration = timerDuration).color(isDark)
    val progress = if (isFinished) "Done" else "${index + 1} of ${cards.size}"

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background(isDark),
            topBar = {
                CenterAlignedTopAppBar(
                    title = {
                        // The dots show where the deck is, so the title bar is the timer's.
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                            modifier = Modifier.semantics(mergeDescendants = true) {
                                contentDescription = "${TeleprompterParser.formatTime(seconds)}, $title, $progress"
                            }
                        ) {
                            Text(
                                text = " ${TeleprompterParser.formatTime(seconds)} ",
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace,
                                color = timerColor
                            )
                            Text(
                                text = title,
                                fontSize = 12.sp,
                                color = AppColors.textSecondary(isDark),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    },
                    navigationIcon = {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = "Close",
                            tint = AppColors.textPrimary(isDark),
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .size(18.dp)
                                .clickableWithoutRipple { close() }
                        )
                    },
                    actions = {
                        HelpButton(page = HelpPage.CARDS, isDark = isDark) { showingHelp = true }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
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
                PageDots(
                    count = cards.size,
                    index = index,
                    isDark = isDark,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .padding(top = 12.dp)
                )

                BoxWithConstraints(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 12.dp, bottom = PEEK * 2)
                ) {
                    val density = LocalDensity.current
                    val widthPx = with(density) { maxWidth.toPx() }
                    val swipePx = with(density) { SWIPE_DISTANCE.toPx() }

                    Deck(
                        cards = cards,
                        position = position.value,
                        rubberBand = rubberBand,
                        isFinished = isFinished,
                        widthPx = widthPx,
                        settings = settings,
                        isDark = isDark,
                        modifier = Modifier
                            .fillMaxSize()
                            .pointerInput(cards.size) {
                                var drag = 0f
                                val velocity = VelocityTracker()
                                detectHorizontalDragGestures(
                                    onDragStart = {
                                        drag = 0f
                                        velocity.resetTracking()
                                    },
                                    onDragCancel = {
                                        drag = 0f
                                        rubberBand = 0f
                                        show(index)
                                    },
                                    onDragEnd = {
                                        // Where a fling would carry the card, like SwiftUI's
                                        // predicted end translation.
                                        val predicted = drag + velocity.calculateVelocity().x * 0.25f
                                        rubberBand = 0f
                                        when {
                                            (drag < -swipePx || predicted < -widthPx / 2) && index < cards.size -> {
                                                AnalyticsEvents.logEvent("cards_next", mapOf("source" to "swipe"))
                                                next()
                                            }
                                            (drag > swipePx || predicted > widthPx / 2) && index > 0 -> {
                                                AnalyticsEvents.logEvent("cards_previous", mapOf("source" to "swipe"))
                                                previous()
                                            }
                                            else -> show(index)
                                        }
                                    },
                                    onHorizontalDrag = { change, amount ->
                                        change.consume()
                                        velocity.addPosition(change.uptimeMillis, change.position)
                                        drag += amount
                                        // Swiped left, the top card follows the finger away.
                                        // Swiped right, the card before it comes back in
                                        // twice as fast, so it is well in view by the time
                                        // the swipe counts.
                                        val travel = if (drag < 0) -drag / widthPx else -2 * drag / widthPx
                                        val target = index + travel
                                        val clamped = target.coerceIn(0f, cards.size.toFloat())
                                        rubberBand = (target - clamped) * widthPx * 0.15f
                                        scope.launch { position.snapTo(clamped) }
                                    }
                                )
                            }
                    )
                }

                // How to move through the deck.
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp)
                        .padding(horizontal = 32.dp)
                        .padding(top = 12.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (!isFinished) {
                        Text(
                            text = "Swipe to turn the card",
                            fontSize = 13.sp,
                            color = AppColors.textSecondary(isDark)
                        )
                    }
                }

                Controls(
                    index = index,
                    count = cards.size,
                    isDark = isDark,
                    onBack = {
                        AnalyticsEvents.logButtonClick("previous_card", CARDS_SCREEN)
                        previous()
                    },
                    onNext = {
                        if (isFinished) {
                            AnalyticsEvents.logButtonClick("restart_cards", CARDS_SCREEN)
                            show(0)
                        } else {
                            AnalyticsEvents.logButtonClick("next_card", CARDS_SCREEN)
                            next()
                        }
                    },
                    modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 16.dp)
                )
            }
        }

        HelpOverlay(page = HelpPage.CARDS, visible = showingHelp, onDismiss = { showingHelp = false })
    }
}

// MARK: - Deck

/**
 * The card before the top one waits just off the left edge, ready to be swiped
 * back in. The next two sit behind the top card, peeking out below. Every card
 * is placed from the deck's position, so a swipe and a button move the deck the
 * same way.
 */
@Composable
private fun Deck(
    cards: List<String>,
    position: Float,
    rubberBand: Float,
    isFinished: Boolean,
    widthPx: Float,
    settings: TeleprompterSettings,
    isDark: Boolean,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val peekPx = with(density) { PEEK.toPx() }
    val finishedAlpha by animateFloatAsState(
        targetValue = if (isFinished) 1f else 0f,
        animationSpec = tween(250),
        label = "finished"
    )

    Box(modifier = modifier) {
        if (finishedAlpha > 0f) {
            FinishedCard(isDark = isDark, modifier = Modifier.alpha(finishedAlpha))
        }

        val lower = maxOf(floor(position).toInt() - 1, 0)
        val upper = minOf(ceil(position).toInt() + 3, cards.size)
        for (cardIndex in lower until upper) {
            key(cardIndex) {
                val offset = cardIndex - position
                val isTop = cardIndex == Math.round(position)
                CardFace(
                    card = cards[cardIndex],
                    settings = settings,
                    isDark = isDark,
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(if (offset < 0) 2f else -offset)
                        .graphicsLayer {
                            transformOrigin = TransformOrigin(0.5f, 1f)
                            if (offset < 0) {
                                // Leaving to the left, or coming back in from there.
                                val x = offset * (widthPx + with(density) { 60.dp.toPx() })
                                translationX = x
                                rotationZ = x / with(density) { 25.dp.toPx() }
                            } else {
                                // Cards behind move up into place as the top one leaves.
                                translationX = if (isTop) rubberBand else 0f
                                rotationZ = if (isTop) rubberBand / with(density) { 25.dp.toPx() } else 0f
                                translationY = peekPx * offset
                                scaleX = 1 - 0.05f * offset
                                scaleY = 1 - 0.05f * offset
                                alpha = (3 - offset).coerceIn(0f, 1f)
                            }
                        }
                        // Only the card on top is read out.
                        .then(if (isTop) Modifier else Modifier.clearAndSetSemantics {})
                )
            }
        }
    }
}

/** One card of the deck, cues drawn in their color. */
@Composable
private fun CardFace(card: String, settings: TeleprompterSettings, isDark: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(CARD_CORNER_RADIUS)
    val runs = remember(card) { CueCards.runs(card) }
    val text = remember(runs, settings.cards.cueColor, isDark) {
        runs.annotated(primary = AppColors.textPrimary(isDark), cue = settings.cards.cueColor.color(isDark))
    }
    val fontSize = settings.cards.fontSize

    Box(
        modifier = modifier
            .shadow(16.dp, shape, ambientColor = Color.Black.copy(alpha = if (isDark) 0.5f else 0.1f))
            .clip(shape)
            .background(cardBackground(isDark))
            .border(0.7.dp, AppColors.textSecondary(isDark).copy(alpha = 0.2f), shape)
            .verticalScroll(rememberScrollState())
    ) {
        Text(
            text = text,
            fontSize = fontSize.sp,
            lineHeight = (fontSize * 1.2f + 4).sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp)
        )
    }
}

/** A card's fill: white on the light page, a lifted grey on the dark one. */
internal fun cardBackground(isDark: Boolean): Color =
    if (isDark) Color(0xFF1C1C1C) else Color.White

@Composable
private fun FinishedCard(isDark: Boolean, modifier: Modifier = Modifier) {
    val outline = AppColors.textSecondary(isDark).copy(alpha = 0.3f)
    Column(
        modifier = modifier
            .fillMaxSize()
            .drawBehind {
                val radius = CARD_CORNER_RADIUS.toPx()
                drawRoundRect(
                    color = outline,
                    cornerRadius = CornerRadius(radius, radius),
                    style = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 6.dp.toPx()))
                    )
                )
            }
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
    ) {
        Icon(
            imageVector = Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = AppColors.green(isDark),
            modifier = Modifier.size(44.dp)
        )
        Text(
            text = "All cards done",
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary(isDark)
        )
        Text(
            text = "Swipe right to bring the last card back, or start over.",
            fontSize = 15.sp,
            color = AppColors.textSecondary(isDark),
            textAlign = TextAlign.Center
        )
    }
}

// MARK: - Page dots

private const val MAX_VISIBLE_DOTS = 9

/**
 * Where the deck is, a dot a card. A long deck shows the dots around the card on
 * top, the ones at either edge shrunk to say there are more.
 */
@Composable
private fun PageDots(count: Int, index: Int, isDark: Boolean, modifier: Modifier = Modifier) {
    val window = if (count <= MAX_VISIBLE_DOTS) {
        0 until count
    } else {
        val start = (index - MAX_VISIBLE_DOTS / 2).coerceIn(0, count - MAX_VISIBLE_DOTS)
        start until start + MAX_VISIBLE_DOTS
    }

    Row(
        modifier = modifier.height(7.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        for (dot in window) {
            // The card on top in green, and every card once the deck is done.
            val color = if (dot == index || index >= count) {
                AppColors.green(isDark)
            } else {
                AppColors.textSecondary(isDark).copy(alpha = 0.35f)
            }
            val moreBefore = window.first > 0 && dot == window.first
            val moreAfter = window.last < count - 1 && dot == window.last
            Box(
                modifier = Modifier
                    .size(7.dp)
                    .scale(if (moreBefore || moreAfter) 0.55f else 1f)
                    .clip(CircleShape)
                    .background(color)
            )
        }
    }
}

// MARK: - Controls

/** Back and Next, each sized to its label like Read Cards on the editor. */
@Composable
private fun Controls(
    index: Int,
    count: Int,
    isDark: Boolean,
    onBack: () -> Unit,
    onNext: () -> Unit,
    modifier: Modifier = Modifier
) {
    val isFinished = index >= count
    val isLast = index == count - 1
    val nextLabel = when {
        isFinished -> "Start Over"
        isLast -> "Finish"
        else -> "Next Card"
    }

    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            modifier = Modifier
                .height(52.dp)
                .alpha(if (index == 0) 0.4f else 1f)
                .glassed(Capsule, isDark)
                .clickableWithoutRipple { if (index > 0) onBack() }
                .semantics { contentDescription = "Previous Card" }
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.ChevronLeft,
                contentDescription = null,
                tint = AppColors.textPrimary(isDark),
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = "Back",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        val onGreen = if (isDark) Color.Black else Color.White
        Row(
            modifier = Modifier
                .height(52.dp)
                .glassed(Capsule, isDark, tint = AppColors.green(isDark))
                .clickableWithoutRipple(onNext)
                .semantics { contentDescription = nextLabel }
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = nextLabel,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = onGreen,
                maxLines = 1
            )
            Icon(
                imageVector = when {
                    isFinished -> Icons.Filled.Refresh
                    isLast -> Icons.Filled.Check
                    else -> Icons.AutoMirrored.Filled.ArrowForward
                },
                contentDescription = null,
                tint = onGreen,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}
