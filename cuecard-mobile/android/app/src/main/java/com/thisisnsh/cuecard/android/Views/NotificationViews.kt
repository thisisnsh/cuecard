package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.RemoteNotification
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import com.thisisnsh.cuecard.android.services.RemoteNotificationService

/** A notice from the worker, shown as a card above the editor. */
@Composable
fun NotificationBanner(
    notification: RemoteNotification,
    notifications: RemoteNotificationService,
    modifier: Modifier = Modifier
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val accent = NotificationStyle.accent(notification.severity, isDark)

    LaunchedEffect(notification.id) {
        notifications.logImpression(notification)
    }

    fun perform(action: RemoteNotification.Action) {
        notifications.logAction(action, notification)

        when (action.kind) {
            RemoteNotification.Action.Kind.OPEN_URL -> action.url?.let { openLink(context, it) }
            RemoteNotification.Action.Kind.APP_STORE -> openLink(context, AppLinks.PLAY_STORE)
            RemoteNotification.Action.Kind.DISMISS -> notifications.dismiss(notification)
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
                    text = notification.title,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary(isDark)
                )

                notification.body?.let { body ->
                    Text(
                        text = body,
                        fontSize = 12.sp,
                        color = AppColors.textSecondary(isDark)
                    )
                }

                if (notification.actions.isNotEmpty()) {
                    Row(
                        modifier = Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        notification.actions.forEach { action ->
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

            if (notification.dismissible) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Dismiss",
                    tint = AppColors.textSecondary(isDark),
                    modifier = Modifier
                        .clickableWithoutRipple { notifications.dismiss(notification) }
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
fun NotificationRow(
    notification: RemoteNotification,
    notifications: RemoteNotificationService,
    modifier: Modifier = Modifier
) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current

    LaunchedEffect(notification.id) {
        notifications.logImpression(notification)
    }

    /**
     * A settings row has space for one thing to do; dismissal already has its own
     * control, so the X is the action we skip here.
     */
    val primaryAction = notification.actions.firstOrNull { it.kind != RemoteNotification.Action.Kind.DISMISS }

    fun perform(action: RemoteNotification.Action) {
        notifications.logAction(action, notification)

        when (action.kind) {
            RemoteNotification.Action.Kind.OPEN_URL -> action.url?.let { openLink(context, it) }
            RemoteNotification.Action.Kind.APP_STORE -> openLink(context, AppLinks.PLAY_STORE)
            RemoteNotification.Action.Kind.DISMISS -> notifications.dismiss(notification)
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
                text = notification.title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )

            notification.body?.let { body ->
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
                    color = NotificationStyle.accent(notification.severity, isDark),
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .clickableWithoutRipple { perform(action) }
                )
            }
        }

        if (notification.dismissible) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss",
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier
                    .clickableWithoutRipple { notifications.dismiss(notification) }
                    .size(11.dp)
            )
        }
    }
}

object NotificationStyle {
    fun accent(severity: RemoteNotification.Severity, isDark: Boolean): Color = when (severity) {
        RemoteNotification.Severity.INFO -> AppColors.blue(isDark)
        RemoteNotification.Severity.WARNING -> AppColors.yellow(isDark)
        RemoteNotification.Severity.CRITICAL -> AppColors.red(isDark)
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
