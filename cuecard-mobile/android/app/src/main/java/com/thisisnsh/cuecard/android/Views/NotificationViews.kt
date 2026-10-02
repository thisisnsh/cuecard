package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
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

    Row(
        modifier = modifier
            .fillMaxWidth()
            .glassed(RoundedCornerShape(20.dp), isDark)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        NotificationIcon(severity = notification.severity, size = 30.dp, isDark = isDark)

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(top = if (notification.body == null) 5.dp else 0.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
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
                    fontSize = 13.sp,
                    color = AppColors.textSecondary(isDark)
                )
            }

            if (notification.actions.isNotEmpty()) {
                Row(
                    modifier = Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    notification.actions.forEachIndexed { index, action ->
                        NotificationAction(
                            label = action.label,
                            tint = accent,
                            isPrimary = index == 0,
                            isDark = isDark
                        ) { perform(action) }
                    }
                }
            }
        }

        if (notification.dismissible) {
            NotificationCloseButton(isDark = isDark) { notifications.dismiss(notification) }
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
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        NotificationIcon(severity = notification.severity, size = 28.dp, isDark = isDark)

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(top = if (notification.body == null) 4.dp else 0.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
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
                    fontSize = 13.sp,
                    color = AppColors.textSecondary(isDark)
                )
            }

            primaryAction?.let { action ->
                NotificationAction(
                    label = action.label,
                    tint = NotificationStyle.accent(notification.severity, isDark),
                    isPrimary = true,
                    isDark = isDark,
                    modifier = Modifier.padding(top = 8.dp)
                ) { perform(action) }
            }
        }

        if (notification.dismissible) {
            NotificationCloseButton(isDark = isDark) { notifications.dismiss(notification) }
        }
    }
}

/** The severity, as a symbol on a soft tint of its colour. */
@Composable
private fun NotificationIcon(severity: RemoteNotification.Severity, size: Dp, isDark: Boolean) {
    val accent = NotificationStyle.accent(severity, isDark)

    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(accent.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center
    ) {
        // Sized to the circle rather than to the reader's text size.
        Text(
            text = NotificationStyle.symbol(severity),
            fontSize = with(LocalDensity.current) { (size * 0.5f).toSp() },
            fontWeight = FontWeight.Bold,
            color = accent
        )
    }
}

@Composable
private fun NotificationCloseButton(isDark: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(24.dp)
            .clip(CircleShape)
            .background(AppColors.textSecondary(isDark).copy(alpha = 0.14f))
            .clickableWithoutRipple(onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.Close,
            contentDescription = "Dismiss",
            tint = AppColors.textSecondary(isDark),
            modifier = Modifier.size(12.dp)
        )
    }
}

/**
 * A small capsule: filled with a tint of the severity colour for the first
 * action, bare text for the second.
 */
@Composable
private fun NotificationAction(
    label: String,
    tint: Color,
    isPrimary: Boolean,
    isDark: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Text(
        text = label,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = if (isPrimary) tint else AppColors.textSecondary(isDark),
        modifier = modifier
            .clip(Capsule)
            .background(if (isPrimary) tint.copy(alpha = 0.16f) else Color.Transparent)
            .clickableWithoutRipple(onClick)
            .padding(horizontal = if (isPrimary) 12.dp else 4.dp, vertical = 6.dp)
    )
}

object NotificationStyle {
    fun symbol(severity: RemoteNotification.Severity): String = when (severity) {
        RemoteNotification.Severity.INFO -> "i"
        RemoteNotification.Severity.WARNING -> "!"
        RemoteNotification.Severity.CRITICAL -> "!!"
    }

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
