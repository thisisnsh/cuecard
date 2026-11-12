package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors

/**
 * A dialog asking for a name: a script's title or a collection's. What's typed
 * is held to `maxLength`, the most a title is saved with.
 */
@Composable
internal fun TextFieldDialog(
    title: String,
    message: String?,
    confirmLabel: String,
    initialValue: String,
    placeholder: String,
    isDark: Boolean,
    maxLength: Int? = null,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var value by remember { mutableStateOf(initialValue) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                message?.let { Text(it, fontSize = 14.sp, color = AppColors.textSecondary(isDark)) }
                BasicTextField(
                    value = value,
                    onValueChange = { value = maxLength?.let(it::take) ?: it },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 16.sp, color = AppColors.textPrimary(isDark)),
                    cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { onConfirm(value) }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focus)
                        .clip(RoundedCornerShape(8.dp))
                        .background(AppColors.textSecondary(isDark).copy(alpha = 0.12f))
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    decorationBox = { field ->
                        if (value.isEmpty()) {
                            Text(placeholder, fontSize = 16.sp, color = AppColors.textSecondary(isDark))
                        }
                        field()
                    }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(value) }) {
                Text(confirmLabel, color = AppColors.blue(isDark))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.cancel), color = AppColors.blue(isDark))
            }
        },
        containerColor = AppColors.background(isDark)
    )
}

/** A dialog asking before something that can't be taken back. */
@Composable
internal fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    isDark: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel, color = AppColors.red(isDark))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.cancel), color = AppColors.blue(isDark))
            }
        },
        containerColor = AppColors.background(isDark)
    )
}

/** Something that didn't work, with an OK to put it away. */
@Composable
internal fun ErrorDialog(message: String, isDark: Boolean, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.something_went_wrong)) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.ok), color = AppColors.blue(isDark))
            }
        },
        containerColor = AppColors.background(isDark)
    )
}

/** One of a dialog's choices, when it has more than two. */
data class DialogChoice(val label: String, val isDestructive: Boolean = false, val action: () -> Unit)

/** A question with several answers, stacked one above the other, the last one to cancel. */
@Composable
internal fun ChoiceDialog(
    title: String,
    message: String,
    choices: List<DialogChoice>,
    isDark: Boolean,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                choices.forEach { choice ->
                    TextButton(onClick = choice.action) {
                        Text(choice.label, color = if (choice.isDestructive) AppColors.red(isDark) else AppColors.blue(isDark))
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.cancel), color = AppColors.blue(isDark))
                }
            }
        },
        containerColor = AppColors.background(isDark)
    )
}
