package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.RemoteMessage
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.services.RemoteConfigService

/** A notice from the worker, shown as a card above the editor. */
@Composable
fun RemoteMessageBanner(
    message: RemoteMessage,
    remoteConfig: RemoteConfigService,
    modifier: Modifier = Modifier
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val accent = RemoteMessageStyle.accent(message.severity, isDark)

    LaunchedEffect(message.id) {
        remoteConfig.logImpression(message)
    }

    fun perform(action: RemoteMessage.Action) {
        remoteConfig.logAction(action, message)

        when (action.kind) {
            RemoteMessage.Action.Kind.OPEN_URL -> action.url?.let { openLink(context, it) }
            RemoteMessage.Action.Kind.APP_STORE -> openLink(context, AppLinks.PLAY_STORE)
            RemoteMessage.Action.Kind.DISMISS -> remoteConfig.dismiss(message)
        }
    }

    Box(modifier = modifier.glassed(RoundedCornerShape(16.dp), isDark)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
                .padding(start = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = message.title,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )

                message.body?.let { body ->
                    Text(
                        text = body,
                        fontSize = 12.sp,
                        color = AppColors.textSecondary(isDark)
                    )
                }

                if (message.actions.isNotEmpty()) {
                    Row(
                        modifier = Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        message.actions.forEach { action ->
                            Text(
                                text = action.label,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = accent,
                                modifier = Modifier.clickableWithoutRipple { perform(action) }
                            )
                        }
                    }
                }
            }

            if (message.dismissible) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Dismiss",
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier
                        .clickableWithoutRipple { remoteConfig.dismiss(message) }
                        .padding(6.dp)
                        .size(11.dp)
                )
            }
        }

        // The severity stripe runs down the leading edge of the card. It matches
        // the card's own size rather than taking part in measuring it, so it
        // can't stretch the card down the screen next to the editor.
        Box(modifier = Modifier.matchParentSize().padding(10.dp)) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .width(3.dp)
                    .fillMaxHeight()
                    .clip(Capsule)
                    .background(accent)
            )
        }
    }
}

/**
 * The same notice in a quieter place: a row at the top of Settings. Used for
 * anything not worth interrupting someone's script for.
 */
@Composable
fun RemoteMessageRow(
    message: RemoteMessage,
    remoteConfig: RemoteConfigService,
    modifier: Modifier = Modifier
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current

    LaunchedEffect(message.id) {
        remoteConfig.logImpression(message)
    }

    /**
     * A settings row has space for one thing to do; dismissal already has its own
     * control, so the X is the action we skip here.
     */
    val primaryAction = message.actions.firstOrNull { it.kind != RemoteMessage.Action.Kind.DISMISS }

    fun perform(action: RemoteMessage.Action) {
        remoteConfig.logAction(action, message)

        when (action.kind) {
            RemoteMessage.Action.Kind.OPEN_URL -> action.url?.let { openLink(context, it) }
            RemoteMessage.Action.Kind.APP_STORE -> openLink(context, AppLinks.PLAY_STORE)
            RemoteMessage.Action.Kind.DISMISS -> remoteConfig.dismiss(message)
        }
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = message.title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )

            message.body?.let { body ->
                Text(
                    text = body,
                    fontSize = 12.sp,
                    color = AppColors.textSecondary(isDark)
                )
            }

            primaryAction?.let { action ->
                Text(
                    text = action.label,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = RemoteMessageStyle.accent(message.severity, isDark),
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .clickableWithoutRipple { perform(action) }
                )
            }
        }

        if (message.dismissible) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss",
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier
                    .clickableWithoutRipple { remoteConfig.dismiss(message) }
                    .size(11.dp)
            )
        }
    }
}

/**
 * Shown instead of the app when the worker says this build is below the floor.
 * There is deliberately no way past it — it exists for the case where a shipped
 * build is doing real damage and every other lever is a release away.
 */
@Composable
fun UpdateRequiredScreen(remoteConfig: RemoteConfigService) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("update_required")
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.background(isDark)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Image(
                painter = painterResource(id = R.mipmap.ic_launcher),
                contentDescription = "CueCard",
                modifier = Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(16.dp))
            )

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = "Update CueCard",
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.textPrimary(isDark)
                )

                Text(
                    text = "This version can't run anymore. Grab the latest one from Google Play — your notes are safe on this device.",
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center,
                    color = AppColors.textSecondary(isDark)
                )
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(AppColors.green(isDark))
                    .clickableWithoutRipple {
                        AnalyticsEvents.logButtonClick("update_app", "update_required")
                        openLink(context, remoteConfig.updateURL)
                    },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Open Google Play",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) Color.Black else Color.White
                )
            }
        }
    }
}

object RemoteMessageStyle {
    fun accent(severity: RemoteMessage.Severity, isDark: Boolean): Color = when (severity) {
        RemoteMessage.Severity.INFO -> AppColors.blue(isDark)
        RemoteMessage.Severity.WARNING -> AppColors.yellow(isDark)
        RemoteMessage.Severity.CRITICAL -> AppColors.red(isDark)
    }
}

/** Open a link in the browser, the parallel to SwiftUI's `openURL`. */
internal fun openLink(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(
            android.content.Intent(android.content.Intent.ACTION_VIEW, url.toUri())
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
