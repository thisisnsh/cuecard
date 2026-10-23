package com.thisisnsh.cuecard.android.views

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.MediaController
import android.widget.VideoView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.services.Take
import com.thisisnsh.cuecard.android.services.TakeDetails
import com.thisisnsh.cuecard.android.services.TakesLibrary
import com.thisisnsh.cuecard.android.services.VideoAccess
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

private const val TAKES_SCREEN = "takes"
private const val PLAYER_SCREEN = "take_player"

/** The longest a tag can be. */
private const val LONGEST_TAG = 30

private val takeDateFormat: DateFormat
    get() = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)

/** The button beside Play that opens the script's takes. */
@Composable
fun TakesButton(count: Int, isDark: Boolean, onClick: () -> Unit) {
    val description = if (count == 0) {
        stringResource(R.string.takes)
    } else {
        pluralStringResource(R.plurals.takes_count, count, count)
    }
    Box(
        modifier = Modifier
            .size(52.dp)
            .glassed(CircleShape, isDark)
            .clickableWithoutRipple(onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.VideoLibrary,
            contentDescription = null,
            tint = AppColors.textPrimary(isDark),
            modifier = Modifier.size(20.dp)
        )
    }
}

/**
 * Asks Android for the videos, and for the user's go-ahead on a change to one
 * CueCard didn't record. Shared by the list and the player.
 */
private class TakeRequests(
    val askForVideos: () -> Unit,
    val confirm: (android.content.IntentSender, onConfirmed: () -> Unit) -> Unit
)

@Composable
private fun rememberTakeRequests(library: TakesLibrary): TakeRequests {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var onConfirmed by remember { mutableStateOf<(() -> Unit)?>(null) }

    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val activity = context.findActivity()
        val canAskAgain = activity != null &&
            TakesLibrary.permissions.any { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
        library.markAsked()
        library.updateStatus(canAskAgain)
        scope.launch { library.reload() }
    }
    val confirmation = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) onConfirmed?.invoke()
        onConfirmed = null
        scope.launch { library.reload() }
    }

    return remember {
        TakeRequests(
            askForVideos = { permissions.launch(TakesLibrary.permissions) },
            confirm = { sender, then ->
                onConfirmed = then
                confirmation.launch(IntentSenderRequest.Builder(sender).build())
            }
        )
    }
}

/** Every take of the script, newest first, opening into playback and details. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TakesView(
    library: TakesLibrary,
    /** The saved note's title, while the script is one. */
    scriptTitle: String?,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val status by library.status.collectAsState()
    val takes by library.takes.collectAsState()
    val details by library.details.collectAsState()
    val requests = rememberTakeRequests(library)

    /** The take playing, by ID. */
    var playingId by remember { mutableStateOf<String?>(null) }
    val playing = takes.firstOrNull { it.id == playingId }

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(TAKES_SCREEN)
        library.reload()
    }

    fun play(take: Take) {
        AnalyticsEvents.logButtonClick("play_take", TAKES_SCREEN)
        playingId = take.id
    }

    fun delete(take: Take, screen: String, then: () -> Unit = {}) {
        AnalyticsEvents.logButtonClick("delete_take", screen)
        scope.launch {
            library.delete(take)?.let { request ->
                requests.confirm(request) {
                    scope.launch { library.forget(take) }
                    then()
                }
            }
        }
    }

    fun favorite(take: Take, screen: String) {
        AnalyticsEvents.logButtonClick("favorite_take", screen)
        scope.launch { library.setFavorite(!take.isFavorite, take)?.let { requests.confirm(it) {} } }
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(
                            text = stringResource(R.string.takes),
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                        scriptTitle?.let {
                            Text(
                                text = it,
                                fontSize = 11.sp,
                                color = AppColors.textSecondary(isDark),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
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
                                AnalyticsEvents.logButtonClick("done", TAKES_SCREEN)
                                onDismiss()
                            }
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background(isDark))
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when {
                status == VideoAccess.NOT_DETERMINED -> TakesMessage(
                    title = stringResource(R.string.find_your_takes),
                    detail = stringResource(R.string.find_takes_detail),
                    isDark = isDark
                ) {
                    Text(
                        text = stringResource(R.string.allow_access_to_videos),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (isDark) Color.Black else Color.White,
                        modifier = Modifier
                            .clip(Capsule)
                            .background(AppColors.green(isDark))
                            .clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("allow_videos", TAKES_SCREEN)
                                requests.askForVideos()
                            }
                            .padding(horizontal = 20.dp, vertical = 12.dp)
                    )
                }

                status == VideoAccess.DENIED -> TakesMessage(
                    title = stringResource(R.string.find_your_takes),
                    detail = stringResource(R.string.takes_denied),
                    isDark = isDark
                ) {
                    TextLink(stringResource(R.string.open_settings), isDark) {
                        AnalyticsEvents.logButtonClick("videos_settings", TAKES_SCREEN)
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                }

                takes.isEmpty() -> TakesMessage(
                    title = stringResource(R.string.no_takes_yet),
                    detail = stringResource(R.string.no_takes_detail),
                    isDark = isDark
                ) {
                    if (status == VideoAccess.LIMITED) LimitedAccessNote(isDark, requests.askForVideos)
                }

                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(takes.reversed(), key = { _, take -> take.id }) { _, take ->
                        TakeRow(
                            take = take,
                            details = details[take.id] ?: TakeDetails(),
                            library = library,
                            isDark = isDark,
                            onPlay = { play(take) },
                            onFavorite = { favorite(take, TAKES_SCREEN) },
                            onDelete = { delete(take, TAKES_SCREEN) }
                        )
                    }
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (status == VideoAccess.LIMITED) LimitedAccessNote(isDark, requests.askForVideos)
                            Text(
                                text = stringResource(R.string.takes_footer),
                                fontSize = 12.sp,
                                color = AppColors.textSecondary(isDark),
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                }
            }
        }
    }

    AnimatedVisibility(visible = playing != null, enter = fadeIn(), exit = fadeOut()) {
        // The take as it was opened, kept while the player fades away.
        val take = remember { playing } ?: return@AnimatedVisibility
        val current = takes.firstOrNull { it.id == take.id } ?: take
        TakePlayerView(
            take = current,
            library = library,
            onFavorite = { favorite(current, PLAYER_SCREEN) },
            onDelete = { delete(current, PLAYER_SCREEN) { playingId = null } },
            onDismiss = {
                AnalyticsEvents.logButtonClick("close", PLAYER_SCREEN)
                playingId = null
            }
        )
    }
}

/** Before the videos can be looked through, or with none to show: why, and what to do. */
@Composable
private fun TakesMessage(title: String, detail: String, isDark: Boolean, actions: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)
    ) {
        Icon(
            imageVector = Icons.Filled.VideoLibrary,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(48.dp)
        )
        Text(text = title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary(isDark))
        Text(text = detail, fontSize = 15.sp, color = AppColors.textSecondary(isDark), textAlign = TextAlign.Center)
        actions()
    }
}

@Composable
private fun LimitedAccessNote(isDark: Boolean, onChooseMore: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.takes_limited),
            fontSize = 12.sp,
            color = AppColors.textSecondary(isDark),
            textAlign = TextAlign.Center
        )
        TextLink(stringResource(R.string.choose_more_videos), isDark) {
            AnalyticsEvents.logButtonClick("choose_more_videos", TAKES_SCREEN)
            onChooseMore()
        }
    }
}

@Composable
private fun TextLink(title: String, isDark: Boolean, onClick: () -> Unit) {
    Text(
        text = title,
        fontSize = 15.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.blue(isDark),
        modifier = Modifier
            .clickableWithoutRipple(onClick)
            .padding(8.dp)
    )
}

/**
 * One take: its picture and length, its number and date, its tags and notes,
 * and its heart. A tap plays it, a swipe from the trailing edge deletes it,
 * and a long press opens a menu.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun TakeRow(
    take: Take,
    details: TakeDetails,
    library: TakesLibrary,
    isDark: Boolean,
    onPlay: () -> Unit,
    onFavorite: () -> Unit,
    onDelete: () -> Unit
) {
    var showingMenu by remember { mutableStateOf(false) }
    // The row springs back: it's gone once Android has asked and the video is deleted.
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
            false
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(AppColors.red(isDark))
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Text(text = stringResource(R.string.delete), color = Color.White, fontWeight = FontWeight.SemiBold)
            }
        }
    ) {
        Box {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AppColors.background(isDark))
                    .combinedClickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onPlay,
                        onLongClick = { showingMenu = true }
                    )
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(contentAlignment = Alignment.BottomEnd) {
                    TakeThumbnail(take, library, width = 54.dp, height = 72.dp)
                    Text(
                        text = TeleprompterParser.formatTime(((take.duration + 500) / 1000).toInt()),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White,
                        modifier = Modifier
                            .padding(4.dp)
                            .clip(Capsule)
                            .background(Color.Black.copy(alpha = 0.55f))
                            .padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = stringResource(R.string.take_number, take.number),
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppColors.textPrimary(isDark)
                        )
                        Text(
                            text = takeDateFormat.format(Date(take.recordedAt)),
                            fontSize = 12.sp,
                            color = AppColors.textSecondary(isDark)
                        )
                    }

                    if (details.tags.isNotEmpty()) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            details.tags.forEach { TagLabel(it, isDark) }
                        }
                    }

                    if (details.note.isNotEmpty()) {
                        Text(
                            text = details.note,
                            fontSize = 12.sp,
                            color = AppColors.textSecondary(isDark),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                if (TakesLibrary.canFavorite) {
                    FavoriteButton(take.isFavorite, size = 36.dp, isDark = isDark, onClick = onFavorite)
                }
            }

            DropdownMenu(
                expanded = showingMenu,
                onDismissRequest = { showingMenu = false },
                containerColor = AppColors.background(isDark)
            ) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.play)) },
                    onClick = {
                        showingMenu = false
                        onPlay()
                    }
                )
                if (TakesLibrary.canFavorite) {
                    DropdownMenuItem(
                        text = { Text(stringResource(if (take.isFavorite) R.string.unfavorite else R.string.favorite)) },
                        onClick = {
                            showingMenu = false
                            onFavorite()
                        }
                    )
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.delete), color = AppColors.red(isDark)) },
                    onClick = {
                        showingMenu = false
                        onDelete()
                    }
                )
            }
        }
    }
}

/** A take's picture, filled in once the device hands it over. */
@Composable
private fun TakeThumbnail(take: Take, library: TakesLibrary, width: Dp, height: Dp) {
    val density = LocalDensity.current
    val image by produceState<android.graphics.Bitmap?>(null, take.id) {
        value = with(density) { library.thumbnail(take, width.roundToPx(), height.roundToPx()) }
    }
    Box(
        modifier = Modifier
            .size(width, height)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Gray.copy(alpha = 0.2f)),
        contentAlignment = Alignment.Center
    ) {
        val bitmap = image
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Icon(
                imageVector = Icons.Filled.Videocam,
                contentDescription = null,
                tint = Color.Gray,
                modifier = Modifier.size(minOf(width, height) * 0.3f)
            )
        }
    }
}

/** A heart that marks the take as a favorite, or takes the mark off. */
@Composable
private fun FavoriteButton(
    isFavorite: Boolean,
    size: Dp,
    isDark: Boolean,
    /** The empty heart's color, where the usual gray would be lost. */
    unfilledColor: Color? = null,
    onClick: () -> Unit
) {
    val description = stringResource(if (isFavorite) R.string.unfavorite else R.string.favorite)
    Box(
        modifier = Modifier
            .size(size)
            .clickableWithoutRipple(onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = null,
            tint = if (isFavorite) AppColors.red(isDark) else unfilledColor ?: AppColors.textSecondary(isDark),
            modifier = Modifier.size(if (size > 40.dp) 24.dp else 20.dp)
        )
    }
}

/** A tag on a take, as it shows in the list. */
@Composable
private fun TagLabel(tag: String, isDark: Boolean) {
    Text(
        text = tag,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        maxLines = 1,
        color = AppColors.blue(isDark),
        modifier = Modifier
            .clip(Capsule)
            .background(AppColors.blue(isDark).copy(alpha = 0.15f))
            .padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

/** A tag to take off, or a suggested one to put on. */
@Composable
private fun TagButton(tag: String, isSuggestion: Boolean, description: String, isDark: Boolean, onClick: () -> Unit) {
    val color = if (isSuggestion) AppColors.textSecondary(isDark) else AppColors.blue(isDark)
    Row(
        modifier = Modifier
            .heightIn(min = 44.dp)
            .clickableWithoutRipple(onClick)
            .semantics(mergeDescendants = true) { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            modifier = Modifier
                .clip(Capsule)
                .background(color.copy(alpha = if (isSuggestion) 0.12f else 0.15f))
                .padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(text = tag, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = color, maxLines = 1)
            Text(text = if (isSuggestion) "+" else "×", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = color)
        }
    }
}

// MARK: - Player

/**
 * A take full screen on black, with its number and date above it, and the
 * heart, its tags and notes, and the bin below it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TakePlayerView(
    take: Take,
    library: TakesLibrary,
    onFavorite: () -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit
) {
    var showingDetails by remember { mutableStateOf(false) }
    var videoView by remember { mutableStateOf<VideoView?>(null) }

    BackHandler(onBack = onDismiss)

    LaunchedEffect(Unit) { AnalyticsEvents.logScreenView(PLAYER_SCREEN) }

    DisposableEffect(Unit) {
        onDispose { videoView?.stopPlayback() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            // Taps around the video don't reach the list underneath.
            .clickableWithoutRipple {}
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .glassed(CircleShape, isDark = true)
                    .clickableWithoutRipple(onDismiss),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.close),
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }

            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 60.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(1.dp)
            ) {
                Text(
                    text = stringResource(R.string.take_number, take.number),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    maxLines = 1
                )
                Text(
                    text = takeDateFormat.format(Date(take.recordedAt)),
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.6f),
                    maxLines = 1
                )
            }
        }

        AndroidView(
            factory = { context ->
                VideoView(context).apply {
                    val controller = MediaController(context)
                    controller.setAnchorView(this)
                    setMediaController(controller)
                    setVideoURI(take.uri)
                    setOnPreparedListener { start() }
                    videoView = this
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        )

        // What can be done with the take, floating under the video: the heart
        // and the bin on their own, the details between them.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (TakesLibrary.canFavorite) {
                Box(modifier = Modifier.glassed(CircleShape, isDark = true)) {
                    FavoriteButton(take.isFavorite, size = 48.dp, isDark = true, unfilledColor = Color.White, onClick = onFavorite)
                }
            } else {
                Spacer(modifier = Modifier.size(48.dp))
            }

            Spacer(modifier = Modifier.weight(1f))

            val tagsAndNotes = stringResource(R.string.tags_and_notes)
            Row(
                modifier = Modifier
                    .height(48.dp)
                    .glassed(Capsule, isDark = true)
                    .clickableWithoutRipple {
                        AnalyticsEvents.logButtonClick("take_details", PLAYER_SCREEN)
                        showingDetails = true
                    }
                    .semantics(mergeDescendants = true) { contentDescription = tagsAndNotes }
                    .padding(horizontal = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(imageVector = Icons.Filled.Sell, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                Text(text = tagsAndNotes, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
            }

            Spacer(modifier = Modifier.weight(1f))

            Box(
                modifier = Modifier
                    .size(48.dp)
                    .glassed(CircleShape, isDark = true)
                    .clickableWithoutRipple {
                        videoView?.pause()
                        onDelete()
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.delete),
                    tint = AppColors.red(isDark = true),
                    modifier = Modifier.size(22.dp)
                )
            }
        }
    }

    if (showingDetails) {
        ModalBottomSheet(
            onDismissRequest = { showingDetails = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = AppColors.background(isDark = true)
        ) {
            TakeDetailsSheet(take, library)
        }
    }
}

/** The take's tags and notes, kept as they change. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TakeDetailsSheet(take: Take, library: TakesLibrary) {
    val isDark = true
    var details by remember { mutableStateOf(library.details(take)) }
    var newTag by remember { mutableStateOf("") }

    fun update(changed: TakeDetails) {
        details = changed
        library.setDetails(changed, take)
    }

    fun add(tag: String) {
        val trimmed = tag.trim().take(LONGEST_TAG)
        newTag = ""
        if (trimmed.isEmpty() || details.tags.any { it.equals(trimmed, ignoreCase = true) }) return
        AnalyticsEvents.logButtonClick("tag_take", PLAYER_SCREEN)
        update(details.copy(tags = details.tags + trimmed))
    }

    // Tags on the script's other takes, leaving out any this take already has.
    val suggestions = library.usedTags
        .filter { used -> details.tags.none { it.equals(used, ignoreCase = true) } }
        .take(8)
    val secondary = AppColors.textSecondary(isDark)
    val field = AppColors.textSecondary(isDark).copy(alpha = 0.12f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(R.string.take_number, take.number),
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textPrimary(isDark),
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )

        Text(text = stringResource(R.string.tags), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = secondary)

        if (details.tags.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                details.tags.forEach { tag ->
                    TagButton(tag, isSuggestion = false, description = stringResource(R.string.remove_tag, tag), isDark = isDark) {
                        update(details.copy(tags = details.tags - tag))
                    }
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(field)
                    .padding(horizontal = 12.dp, vertical = 12.dp)
            ) {
                if (newTag.isEmpty()) {
                    Text(text = stringResource(R.string.add_a_tag), fontSize = 16.sp, color = secondary)
                }
                BasicTextField(
                    value = newTag,
                    onValueChange = { newTag = it },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 16.sp, color = AppColors.textPrimary(isDark)),
                    cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { add(newTag) }),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            val canAdd = newTag.isNotBlank()
            Icon(
                imageVector = Icons.Filled.AddCircle,
                contentDescription = stringResource(R.string.add_a_tag),
                tint = AppColors.blue(isDark).copy(alpha = if (canAdd) 1f else 0.4f),
                modifier = Modifier
                    .size(44.dp)
                    .clickableWithoutRipple { if (canAdd) add(newTag) }
                    .padding(8.dp)
            )
        }

        if (suggestions.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                suggestions.forEach { tag ->
                    TagButton(tag, isSuggestion = true, description = stringResource(R.string.add_tag, tag), isDark = isDark) {
                        add(tag)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
        Text(text = stringResource(R.string.notes), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = secondary)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 96.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(field)
                .padding(12.dp)
        ) {
            if (details.note.isEmpty()) {
                Text(text = stringResource(R.string.take_notes_placeholder), fontSize = 16.sp, color = secondary)
            }
            val notesLabel = stringResource(R.string.notes)
            BasicTextField(
                value = details.note,
                onValueChange = { update(details.copy(note = it)) },
                textStyle = TextStyle(fontSize = 16.sp, color = AppColors.textPrimary(isDark)),
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = notesLabel }
            )
        }
    }
}
