package com.thisisnsh.cuecard.android.views

import androidx.compose.material.icons.filled.Email
import java.util.Locale
import android.provider.Settings
import android.os.Build
import android.net.Uri
import com.thisisnsh.cuecard.android.R
import androidx.compose.ui.res.stringResource
import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.crashlytics.ktx.crashlytics
import com.google.firebase.ktx.Firebase
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.BuildConfig
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.ScriptMode
import com.thisisnsh.cuecard.android.models.RemoteNotification
import android.content.pm.PackageManager
import androidx.core.content.edit
import androidx.compose.ui.text.style.TextOverflow
import com.thisisnsh.cuecard.android.services.CameraCapabilities
import com.thisisnsh.cuecard.android.services.CameraOptions
import com.thisisnsh.cuecard.android.services.CameraSettings
import com.thisisnsh.cuecard.android.services.CardsSettings
import com.thisisnsh.cuecard.android.services.OverlayAspectRatio
import com.thisisnsh.cuecard.android.services.RemoteNotificationService
import com.thisisnsh.cuecard.android.services.SettingPreset
import com.thisisnsh.cuecard.android.services.SettingsService
import com.thisisnsh.cuecard.android.services.TeleprompterSettings
import com.thisisnsh.cuecard.android.services.ThemePreference
import kotlinx.coroutines.launch

// MARK: - Settings

private const val SETTINGS_SCREEN = "settings"

/**
 * The one Settings screen, opened from the library and the editor. It shows
 * every setting, in groups: the teleprompter's, the camera, the cards', then
 * the rest, each with a line on what it does. The teleprompter and the cards
 * each keep their own text sizes and cue color; the camera, the theme and the
 * language are the same for both.
 */
@Composable
fun SettingsView(
    settingsService: SettingsService,
    notifications: RemoteNotificationService,
    onDismiss: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val scope = rememberCoroutineScope()

    val settings by settingsService.settings.collectAsState()
    val payload by notifications.payload.collectAsState()
    val dismissedIds by notifications.dismissedIds.collectAsState()

    val settingsNotification = remember(payload, dismissedIds) {
        notifications.notification(RemoteNotification.Surface.SETTINGS_ROW)
    }

    fun update(change: (TeleprompterSettings) -> TeleprompterSettings) {
        scope.launch { settingsService.update(change) }
    }

    SettingsScreen(
        screen = SETTINGS_SCREEN,
        title = stringResource(R.string.settings),
        onDismiss = onDismiss
    ) {
        // A notice from the worker, if there's one meant for Settings.
        settingsNotification?.let { notification ->
            SettingsSection(isDark = isDark) {
                NotificationRow(
                    notification = notification,
                    notifications = notifications,
                    modifier = Modifier.padding(horizontal = 20.dp)
                )
            }
        }

        TeleprompterSection(settings = settings, isDark = isDark, update = ::update)
        CameraSection(settings = settings, isDark = isDark, update = ::update)
        CardsSection(settings = settings, isDark = isDark, update = ::update)
        LanguageSection(screen = SETTINGS_SCREEN, isDark = isDark)
        AboutSection(screen = SETTINGS_SCREEN, isDark = isDark)

        SettingsSection(isDark = isDark) {
            MenuPickerRow(
                label = stringResource(R.string.theme),
                detail = stringResource(R.string.theme_detail),
                options = ThemePreference.entries,
                selected = settings.themePreference,
                optionLabel = { it.displayName },
                isDark = isDark,
                onSelect = { theme ->
                    AnalyticsEvents.logButtonClick("settings_theme", SETTINGS_SCREEN)
                    update { it.copy(themePreference = theme) }
                }
            )
        }

        AdvancedSection(settingsService = settingsService, settings = settings, screen = SETTINGS_SCREEN, isDark = isDark) {
            val prompter = TeleprompterSettings.FONT_SIZE_RANGE
            val pip = TeleprompterSettings.PIP_FONT_SIZE_RANGE
            val editor = TeleprompterSettings.EDITOR_FONT_SIZE_RANGE
            NumberRow(
                label = stringResource(R.string.teleprompter_text_size),
                detail = stringResource(R.string.size_range, prompter.first, prompter.last),
                value = settings.fontSize,
                range = prompter,
                isDark = isDark,
                onCommit = { size -> update { it.copy(fontSize = size) } }
            )
            NumberRow(
                label = stringResource(R.string.teleprompter_editor_text_size),
                detail = stringResource(R.string.size_range, editor.first, editor.last),
                value = settings.editorFontSize,
                range = editor,
                isDark = isDark,
                onCommit = { size -> update { it.copy(editorFontSize = size) } }
            )
            NumberRow(
                label = stringResource(R.string.floating_window_text_size),
                detail = stringResource(R.string.size_range, pip.first, pip.last),
                value = settings.pipFontSize,
                range = pip,
                isDark = isDark,
                onCommit = { size -> update { it.copy(pipFontSize = size) } }
            )
            NumberRow(
                label = stringResource(R.string.card_text_size),
                detail = stringResource(R.string.size_range, prompter.first, prompter.last),
                value = settings.cards.fontSize,
                range = prompter,
                isDark = isDark,
                onCommit = { size -> update { it.copy(cards = it.cards.copy(fontSize = size)) } }
            )
            NumberRow(
                label = stringResource(R.string.cards_editor_text_size),
                detail = stringResource(R.string.size_range, editor.first, editor.last),
                value = settings.cards.editorFontSize,
                range = editor,
                isDark = isDark,
                onCommit = { size -> update { it.copy(cards = it.cards.copy(editorFontSize = size)) } }
            )
        }

        if (BuildConfig.DIAGNOSTICS) {
            SettingsSection(
                isDark = isDark,
                footer = stringResource(R.string.test_crash_footer)
            ) {
                Text(
                    text = stringResource(R.string.trigger_test_crash),
                    fontSize = 17.sp,
                    color = AppColors.red(isDark),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("test_crash", SETTINGS_SCREEN)
                            Firebase.crashlytics.log("Manually triggered test crash")
                            throw RuntimeException("Crashlytics test crash")
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp)
                )
            }
        }
    }
}

/** The teleprompter's reading, editor and floating window settings, and its mirror. */
@Composable
private fun TeleprompterSection(
    settings: TeleprompterSettings,
    isDark: Boolean,
    update: ((TeleprompterSettings) -> TeleprompterSettings) -> Unit
) {
    fun logged(button: String, change: (TeleprompterSettings) -> TeleprompterSettings) {
        AnalyticsEvents.logButtonClick(button, SETTINGS_SCREEN)
        update(change)
    }

    SettingsSection(title = stringResource(R.string.teleprompter), isDark = isDark) {
        NumberRow(
            label = stringResource(R.string.scroll_speed),
            detail = stringResource(R.string.scroll_speed_detail),
            unit = stringResource(R.string.lines_per_min),
            value = settings.linesPerMinute,
            range = TeleprompterSettings.LPM_RANGE,
            isDark = isDark,
            onCommit = { lines -> update { it.copy(linesPerMinute = lines) } }
        )

        SizePresetPicker(
            label = stringResource(R.string.viewer_text_size),
            detail = stringResource(R.string.viewer_text_size_detail),
            value = settings.fontSize,
            presets = TeleprompterSettings.FONT_SIZE_PRESETS,
            isDark = isDark,
            onSelect = { size -> logged("settings_text_size") { it.copy(fontSize = size) } }
        )

        SizePresetPicker(
            label = stringResource(R.string.editor_text_size),
            detail = stringResource(R.string.editor_text_size_detail),
            value = settings.editorFontSize,
            presets = TeleprompterSettings.EDITOR_FONT_SIZE_PRESETS,
            isDark = isDark,
            onSelect = { size -> logged("settings_editor_text_size") { it.copy(editorFontSize = size) } }
        )

        SizePresetPicker(
            label = stringResource(R.string.floating_window_text_size),
            detail = stringResource(R.string.floating_window_text_size_detail),
            value = settings.pipFontSize,
            presets = TeleprompterSettings.PIP_FONT_SIZE_PRESETS,
            isDark = isDark,
            onSelect = { size -> logged("settings_floating_text_size") { it.copy(pipFontSize = size) } }
        )

        MenuPickerRow(
            label = stringResource(R.string.floating_window_layout),
            detail = stringResource(R.string.floating_window_layout_detail),
            options = OverlayAspectRatio.entries,
            selected = settings.overlayAspectRatio,
            optionLabel = { it.label },
            isDark = isDark,
            onSelect = { ratio -> logged("settings_floating_layout") { it.copy(overlayAspectRatio = ratio) } }
        )

        CueColorPicker(
            detail = stringResource(R.string.cue_color_detail),
            selected = settings.cueColor,
            isDark = isDark,
            onSelect = { color -> logged("settings_cue_color") { it.copy(cueColor = color) } }
        )

        ToggleRow(
            label = stringResource(R.string.reading_guide_line),
            detail = stringResource(R.string.reading_guide_line_detail),
            isOn = settings.showsReadingGuide,
            isDark = isDark,
            onChange = { isOn -> logged("settings_reading_guide") { it.copy(showsReadingGuide = isOn) } }
        )

        ToggleRow(
            label = stringResource(R.string.flip_horizontally),
            detail = stringResource(R.string.flip_horizontally_detail),
            isOn = settings.mirrorsText,
            isDark = isDark,
            onChange = { isOn -> logged("settings_flip_horizontal") { it.copy(mirrorsText = isOn) } }
        )

        ToggleRow(
            label = stringResource(R.string.flip_vertically),
            detail = stringResource(R.string.flip_vertically_detail),
            isOn = settings.flipsTextVertically,
            isDark = isDark,
            onChange = { isOn -> logged("settings_flip_vertical") { it.copy(flipsTextVertically = isOn) } }
        )
    }
}

/**
 * The floating camera, the same for both modes: whether the script is drawn
 * over it, whether the teleprompter plays and pauses with it, and how it
 * records. No camera is on here, so it offers what either of this device's
 * cameras has, given the other choices, and each camera records the nearest it
 * can. The reader's own choices are kept, for when another one makes them
 * possible again. Not on a device without a camera.
 */
@Composable
private fun CameraSection(
    settings: TeleprompterSettings,
    isDark: Boolean,
    update: ((TeleprompterSettings) -> TeleprompterSettings) -> Unit
) {
    val context = LocalContext.current
    val hasCamera = remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    if (!hasCamera) return

    var preferred by remember { mutableStateOf(CameraSettings.saved(context)) }
    var offered by remember { mutableStateOf(preferred to CameraOptions()) }
    LaunchedEffect(preferred) {
        offered = CameraCapabilities.offered(context, preferred)
    }
    val (shown, options) = offered

    fun change(name: String, value: Any, changed: (CameraSettings) -> CameraSettings) {
        AnalyticsEvents.logButtonClick(
            "camera_setting", SETTINGS_SCREEN, mapOf("setting" to name, "value" to value.toString())
        )
        preferred = changed(preferred)
        preferred.save(context)
    }

    SettingsSection(title = stringResource(R.string.camera), isDark = isDark) {
        ToggleRow(
            label = stringResource(R.string.text_above_camera),
            detail = stringResource(R.string.text_above_camera_detail),
            isOn = settings.showsTextAboveCamera,
            isDark = isDark,
            onChange = { isOn ->
                AnalyticsEvents.logButtonClick("settings_text_above_camera", SETTINGS_SCREEN)
                update { it.copy(showsTextAboveCamera = isOn) }
            }
        )

        ToggleRow(
            label = stringResource(R.string.sync_with_teleprompter),
            detail = stringResource(R.string.sync_with_teleprompter_detail),
            isOn = settings.syncsCamera,
            isDark = isDark,
            onChange = { isOn ->
                AnalyticsEvents.logButtonClick("settings_sync_camera", SETTINGS_SCREEN)
                update { it.copy(syncsCamera = isOn) }
            }
        )

        MenuPickerRow(
            label = stringResource(R.string.resolution),
            detail = stringResource(R.string.resolution_detail),
            options = options.resolutions,
            selected = shown.resolution,
            optionLabel = { it.label },
            isDark = isDark,
            onSelect = { value ->
                if (value != shown.resolution) change("resolution", value) { it.copy(resolution = value) }
            }
        )

        val fps = options.frameRates.associateWith { stringResource(R.string.frames_per_second, it) }
        MenuPickerRow(
            label = stringResource(R.string.frame_rate),
            detail = stringResource(R.string.frame_rate_detail),
            options = options.frameRates,
            selected = shown.frameRate,
            optionLabel = { fps[it] ?: it.toString() },
            isDark = isDark,
            onSelect = { value ->
                if (value != shown.frameRate) change("frame_rate", value) { it.copy(frameRate = value) }
            }
        )

        if (options.dynamicRanges.size > 1) {
            MenuPickerRow(
                label = stringResource(R.string.dynamic_range),
                detail = stringResource(R.string.dynamic_range_detail),
                options = options.dynamicRanges,
                selected = shown.dynamicRange,
                optionLabel = { it.label },
                isDark = isDark,
                onSelect = { value ->
                    if (value != shown.dynamicRange) change("dynamic_range", value) { it.copy(dynamicRange = value) }
                }
            )
        }

        if (options.stabilizations.size > 1) {
            val off = stringResource(R.string.off)
            val standard = stringResource(R.string.standard)
            MenuPickerRow(
                label = stringResource(R.string.stabilization),
                detail = stringResource(R.string.stabilization_detail),
                options = options.stabilizations,
                selected = shown.stabilization,
                optionLabel = { if (it == CameraSettings.Stabilization.OFF) off else standard },
                isDark = isDark,
                onSelect = { value ->
                    if (value != shown.stabilization) change("stabilization", value) { it.copy(stabilization = value) }
                }
            )
        }

        if (options.isFrontCamera) {
            ToggleRow(
                label = stringResource(R.string.mirror_front_camera),
                detail = stringResource(R.string.mirror_front_camera_detail),
                isOn = shown.mirrorsFrontCamera,
                isDark = isDark,
                onChange = { isOn -> change("mirror_front_camera", isOn) { it.copy(mirrorsFrontCamera = isOn) } }
            )
        }
    }
}

/** The cards' reading and editor settings. */
@Composable
private fun CardsSection(
    settings: TeleprompterSettings,
    isDark: Boolean,
    update: ((TeleprompterSettings) -> TeleprompterSettings) -> Unit
) {
    fun updateCards(button: String, change: (CardsSettings) -> CardsSettings) {
        AnalyticsEvents.logButtonClick(button, SETTINGS_SCREEN)
        update { it.copy(cards = change(it.cards)) }
    }

    SettingsSection(title = stringResource(R.string.cards), isDark = isDark) {
        SizePresetPicker(
            label = stringResource(R.string.viewer_text_size),
            detail = stringResource(R.string.cards_viewer_text_size_detail),
            value = settings.cards.fontSize,
            presets = TeleprompterSettings.FONT_SIZE_PRESETS,
            isDark = isDark,
            onSelect = { size -> updateCards("settings_cards_text_size") { it.copy(fontSize = size) } }
        )

        SizePresetPicker(
            label = stringResource(R.string.editor_text_size),
            detail = stringResource(R.string.cards_editor_text_size_detail),
            value = settings.cards.editorFontSize,
            presets = TeleprompterSettings.EDITOR_FONT_SIZE_PRESETS,
            isDark = isDark,
            onSelect = { size -> updateCards("settings_cards_editor_text_size") { it.copy(editorFontSize = size) } }
        )

        CueColorPicker(
            detail = stringResource(R.string.cards_cue_color_detail),
            selected = settings.cards.cueColor,
            isDark = isDark,
            onSelect = { color -> updateCards("settings_cards_cue_color") { it.copy(cueColor = color) } }
        )
    }
}

// MARK: - Shared Sections

/** The list Settings and the timer are built on, with a Done button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsScreen(
    screen: String,
    title: String,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val screenFocusManager = LocalFocusManager.current

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView(screen)
    }

    Scaffold(
        containerColor = AppColors.background(isDark),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = title,
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
                                AnalyticsEvents.logButtonClick("done", screen)
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
                .verticalScroll(rememberScrollState())
                // A tap that no control claimed puts the keyboard away, so a
                // number being typed has a way out anywhere on the screen.
                .pointerInput(Unit) {
                    detectTapGestures { screenFocusManager.clearFocus() }
                }
        ) {
            content()
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * The app's language, which lives in the system Settings app, and a way to
 * report a mistake in its translation.
 */
@Composable
private fun LanguageSection(screen: String, isDark: Boolean) {
    val context = LocalContext.current
    // The language the app is showing, as its code: each translation names
    // its own, so a phone in a language CueCard doesn't have reads "en".
    val languageCode = stringResource(R.string.language_code)
    val locale = Locale.forLanguageTag(languageCode)
    val languageName = locale.getDisplayName(locale).replaceFirstChar { it.titlecase(locale) }
    // Android 13 gave each app a language of its own. Before that, apps follow
    // the phone's.
    val hasAppLanguage = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    SettingsSection(title = stringResource(R.string.language), isDark = isDark) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickableWithoutRipple {
                    AnalyticsEvents.logButtonClick("language", screen)
                    openLanguageSettings(context, hasAppLanguage)
                }
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SettingLabel(
                title = stringResource(R.string.language),
                detail = stringResource(if (hasAppLanguage) R.string.language_detail else R.string.language_detail_phone),
                isDark = isDark,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = languageName,
                fontSize = 17.sp,
                color = AppColors.textSecondary(isDark)
            )
            Icon(
                imageVector = Icons.Filled.ArrowOutward,
                contentDescription = null,
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier
                    .padding(start = 6.dp)
                    .size(14.dp)
            )
        }

        // English is the original, so there's no translation to get wrong.
        if (languageCode != "en") {
            LinkRow(title = stringResource(R.string.report_translation_mistake), icon = Icons.Filled.Email, isDark = isDark) {
                AnalyticsEvents.logButtonClick("report_translation", screen)
                openLink(context, AppLinks.translationReport(languageCode))
            }
        }
    }
}

/**
 * The system's page for CueCard's language where there is one, opened on
 * CueCard; choosing one there restarts the app in it. Otherwise the phone's
 * own languages.
 */
private fun openLanguageSettings(context: Context, hasAppLanguage: Boolean) {
    val appLanguage = Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.fromParts("package", context.packageName, null))
    val phoneLanguage = Intent(Settings.ACTION_LOCALE_SETTINGS)
    runCatching { context.startActivity(if (hasAppLanguage) appLanguage else phoneLanguage) }
        .recoverCatching { context.startActivity(phoneLanguage) }
}

/** Share and review. */
@Composable
private fun AboutSection(screen: String, isDark: Boolean) {
    val context = LocalContext.current

    SettingsSection(isDark = isDark) {
        LinkRow(title = stringResource(R.string.share_cuecard), icon = Icons.Filled.Share, isDark = isDark) {
            AnalyticsEvents.logButtonClick("share_app", screen)
            shareApp(context)
        }

        LinkRow(title = stringResource(R.string.review_on_google_play), icon = Icons.Filled.ArrowOutward, isDark = isDark) {
            AnalyticsEvents.logButtonClick("rate_app", screen)
            openLink(context, AppLinks.PLAY_STORE)
        }
    }
}

/** A row that leaves Settings for something else, with an icon saying where. */
@Composable
internal fun LinkRow(title: String, icon: ImageVector, isDark: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple(onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )
        Spacer(modifier = Modifier.weight(1f))
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(14.dp)
        )
    }
}

/** Hand the app's link to the system share sheet. */
private fun shareApp(context: Context) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, AppLinks.shareMessage)
    context.startActivity(Intent.createChooser(send, null))
}

/** A setting's name, with one short line below it on what it does. */
@Composable
internal fun SettingLabel(title: String, detail: String?, isDark: Boolean, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(text = title, fontSize = 17.sp, color = AppColors.textPrimary(isDark))
        detail?.let {
            Text(
                text = it,
                fontSize = 13.sp,
                color = AppColors.textSecondary(isDark),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** One grouped section of the settings list, with its heading and footnote. */
@Composable
internal fun SettingsSection(
    isDark: Boolean,
    title: String? = null,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        title?.let {
            Text(
                text = it,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textSecondary(isDark),
                modifier = Modifier.padding(start = 20.dp, top = 24.dp, bottom = 8.dp)
            )
        }

        if (title == null) {
            Spacer(modifier = Modifier.height(16.dp))
        }

        content()

        footer?.let {
            Text(
                text = it,
                fontSize = 12.sp,
                color = AppColors.textSecondary(isDark),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
            )
        }

        HorizontalDivider(
            color = AppColors.textSecondary(isDark).copy(alpha = 0.15f),
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

/**
 * A labelled row holding a number the user types, rather than drags. A figure
 * within range takes effect as it's typed; leaving the field holds whatever is
 * there to the range, so a half-typed figure is never clamped mid-typing.
 */
@Composable
private fun NumberRow(
    label: String,
    /** A line below the label on what it does, or the range it takes. */
    detail: String? = null,
    /** Left out for text sizes, which read as bare numbers. */
    unit: String? = null,
    value: Int,
    range: IntRange,
    isDark: Boolean,
    onCommit: (Int) -> Unit
) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    var isFocused by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }

    fun commit() {
        val typed = text.filter { it.isDigit() }.toIntOrNull()
        val committed = typed?.coerceIn(range.first, range.last) ?: value
        text = committed.toString()
        if (committed != value) onCommit(committed)
    }

    Row(
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingLabel(title = label, detail = detail, isDark = isDark, modifier = Modifier.weight(1f))
        Spacer(modifier = Modifier.width(8.dp))

        // The number and its unit share one filled box, and the whole box is
        // the target: tapping the unit starts editing, same as the digits.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(16.dp))
                .background(AppColors.textSecondary(isDark).copy(alpha = 0.12f))
                .clickableWithoutRipple { focusRequester.requestFocus() }
                .padding(horizontal = 14.dp, vertical = 8.dp)
        ) {
            BasicTextField(
                value = text,
                onValueChange = { entered ->
                    text = entered.filter { it.isDigit() }.take(3)
                    // A figure within range takes effect as it's typed, so a
                    // size can be watched changing.
                    text.toIntOrNull()?.let { if (it in range && it != value) onCommit(it) }
                },
                singleLine = true,
                textStyle = TextStyle(
                    fontSize = 15.sp,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.End,
                    color = AppColors.textPrimary(isDark)
                ),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Done
                ),
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                modifier = Modifier
                    .width(34.dp)
                    .focusRequester(focusRequester)
                    .onFocusChanged { state ->
                        if (isFocused && !state.isFocused) commit()
                        isFocused = state.isFocused
                    }
            )
            unit?.let {
                Spacer(modifier = Modifier.width(5.dp))
                Text(
                    text = it,
                    fontSize = 15.sp,
                    color = AppColors.textSecondary(isDark)
                )
            }
        }
    }
}

/** A labelled switch, with a line below its name on what it does. */
@Composable
internal fun ToggleRow(label: String, detail: String? = null, isOn: Boolean, isDark: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(value = isOn, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingLabel(title = label, detail = detail, isDark = isDark, modifier = Modifier.weight(1f))
        Spacer(modifier = Modifier.width(8.dp))
        Switch(
            checked = isOn,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = AppColors.green(isDark),
                checkedBorderColor = AppColors.green(isDark)
            )
        )
    }
}

/** A row of the app's colors to pick one from. */
@Composable
internal fun ColorSwatchRow(title: String, selected: CueColor, isDark: Boolean, onSelect: (CueColor) -> Unit) {
    Column(
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = title,
            fontSize = 17.sp,
            color = AppColors.textPrimary(isDark)
        )

        val colorLabels = CueColor.entries.associateWith { stringResource(R.string.labeled_value, title, it.displayName) }
        fun colorLabel(option: CueColor) = colorLabels.getValue(option)

        Row(
            modifier = Modifier.padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            CueColor.entries.forEach { option ->
                val isSelected = option == selected
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clickableWithoutRipple { onSelect(option) }
                        .semantics {
                            contentDescription = colorLabel(option)
                            this.selected = isSelected
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .border(
                                width = if (isSelected) 2.dp else 0.dp,
                                color = if (isSelected) AppColors.textPrimary(isDark) else Color.Transparent,
                                shape = CircleShape
                            )
                    )
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(option.color(isDark)),
                        contentAlignment = Alignment.Center
                    ) {
                        if (isSelected) {
                            Icon(
                                imageVector = Icons.Filled.Check,
                                contentDescription = null,
                                tint = AppColors.background(isDark),
                                modifier = Modifier.size(12.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * A setting picked from a menu, with the current choice in grey at the trailing
 * edge — the parallel to a SwiftUI menu picker.
 */
@Composable
private fun <T> MenuPickerRow(
    label: String,
    detail: String? = null,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    isDark: Boolean,
    /** A dot of each option's color, before its name. */
    optionColor: ((T) -> Color)? = null,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickableWithoutRipple { expanded = true }
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingLabel(title = label, detail = detail, isDark = isDark, modifier = Modifier.weight(1f))
        Spacer(modifier = Modifier.width(8.dp))

        Box {
            Row(verticalAlignment = Alignment.CenterVertically) {
                optionColor?.let { color ->
                    ColorDot(color(selected))
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(
                    text = optionLabel(selected),
                    fontSize = 17.sp,
                    color = AppColors.textSecondary(isDark)
                )
                Icon(
                    imageVector = Icons.Filled.UnfoldMore,
                    contentDescription = null,
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier
                        .padding(start = 4.dp)
                        .size(16.dp)
                )
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                containerColor = AppColors.background(isDark)
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = optionLabel(option),
                                color = AppColors.textPrimary(isDark)
                            )
                        },
                        leadingIcon = optionColor?.let { color -> { ColorDot(color(option)) } },
                        trailingIcon = {
                            if (option == selected) {
                                Icon(
                                    imageVector = Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = AppColors.textPrimary(isDark),
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        },
                        onClick = {
                            expanded = false
                            onSelect(option)
                        }
                    )
                }
            }
        }
    }
}

/**
 * A text size picked from a menu of presets, the same kind of row as Theme. A
 * size typed in Advanced that matches no preset shows as its own entry, so the
 * row never reads blank.
 */
@Composable
private fun SizePresetPicker(
    label: String,
    detail: String? = null,
    value: Int,
    presets: List<SettingPreset>,
    isDark: Boolean,
    onSelect: (Int) -> Unit
) {
    val sizes = presets.map { it.value }.let { if (value in it) it else it + value }
    val customLabels = sizes.associateWith { stringResource(R.string.custom_size, it) }
    MenuPickerRow(
        label = label,
        detail = detail,
        options = sizes,
        selected = value,
        optionLabel = { size -> presets.find { it.value == size }?.label ?: customLabels.getValue(size) },
        isDark = isDark,
        onSelect = onSelect
    )
}

/** The cue color, from a menu of the app's colors, each with a dot of it: a row as tall as the others. */
@Composable
private fun CueColorPicker(detail: String, selected: CueColor, isDark: Boolean, onSelect: (CueColor) -> Unit) {
    MenuPickerRow(
        label = stringResource(R.string.cue_color),
        detail = detail,
        options = CueColor.entries,
        selected = selected,
        optionLabel = { it.displayName },
        isDark = isDark,
        optionColor = { it.color(isDark) },
        onSelect = onSelect
    )
}

@Composable
private fun ColorDot(color: Color) {
    Box(
        modifier = Modifier
            .size(14.dp)
            .clip(CircleShape)
            .background(color)
    )
}

/**
 * The last group: typed sizes for anyone who wants one the presets don't
 * offer, hidden until asked for, and Reset to Defaults. Whether the sizes show
 * is remembered.
 */
@Composable
private fun AdvancedSection(
    settingsService: SettingsService,
    settings: TeleprompterSettings,
    screen: String,
    isDark: Boolean,
    fields: @Composable () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val prefs = remember { context.getSharedPreferences(ADVANCED_PREFS, Context.MODE_PRIVATE) }
    var showAdvanced by remember { mutableStateOf(prefs.getBoolean(SHOW_ADVANCED_KEY, false)) }

    SettingsSection(isDark = isDark) {
        AnimatedVisibility(visible = showAdvanced) {
            Column { fields() }
        }

        Text(
            text = if (showAdvanced) stringResource(R.string.hide_advanced_settings) else stringResource(R.string.show_advanced_settings),
            fontSize = 17.sp,
            color = AppColors.blue(isDark),
            modifier = Modifier
                .fillMaxWidth()
                .clickableWithoutRipple {
                    AnalyticsEvents.logButtonClick(
                        if (showAdvanced) "hide_advanced" else "show_advanced",
                        screen
                    )
                    // Leave the field being typed in first, so its figure is
                    // committed before hiding takes the field away.
                    focusManager.clearFocus()
                    showAdvanced = !showAdvanced
                    prefs.edit { putBoolean(SHOW_ADVANCED_KEY, showAdvanced) }
                }
                .padding(horizontal = 20.dp, vertical = 12.dp)
        )

        // Greyed out once there's nothing left to reset, so a tap that changes
        // nothing never looks like one that didn't register.
        val canReset = settingsService.canResetSettings(settings)
        Text(
            text = stringResource(R.string.reset_to_defaults),
            fontSize = 17.sp,
            color = if (canReset) AppColors.blue(isDark) else AppColors.textSecondary(isDark).copy(alpha = 0.5f),
            modifier = Modifier
                .fillMaxWidth()
                .clickableWithoutRipple {
                    if (!canReset) return@clickableWithoutRipple
                    AnalyticsEvents.logButtonClick("reset_to_defaults", screen)
                    scope.launch { settingsService.resetSettings() }
                }
                .padding(horizontal = 20.dp, vertical = 12.dp)
        )
    }
}

private const val ADVANCED_PREFS = "cuecard_settings_ui"
private const val SHOW_ADVANCED_KEY = "settings.showAdvancedSettings"
