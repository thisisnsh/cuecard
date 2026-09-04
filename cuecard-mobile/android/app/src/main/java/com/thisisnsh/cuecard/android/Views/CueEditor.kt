package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardHide
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed

/** Size of the text in the editor. */
private val EDITOR_FONT_SIZE = 16.sp

/**
 * How far the script fades into the background at the top and bottom edges.
 * The text starts and ends this far in, so no line sits inside a fade.
 */
val CUE_EDITOR_EDGE_FADE = 28.dp

/**
 * A handle on the editor, so the cue bar can insert at the caret.
 *
 * Inserting through the text binding instead would rewrite the whole document,
 * which parks the caret at the end — the cue has to go in the same way typing
 * does, or it lands in the right place and the caret doesn't.
 */
class CueEditorController {
    internal var onInsertCue: (() -> Unit)? = null

    /** Drop an empty cue at the caret and leave the caret inside it. */
    fun insertCue() {
        onInsertCue?.invoke()
    }
}

/**
 * Script editor that renders `[cue …]` tags in the cue color while you type, and
 * writes the brackets for you: pressing `[` drops in a whole empty cue with the
 * caret inside it, so a cue is never left half-open — except inside a cue, where
 * there is nothing left for it to open.
 */
@Composable
fun CueTextEditor(
    text: String,
    onTextChange: (String) -> Unit,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    controller: CueEditorController,
    cueColor: CueColor,
    isDark: Boolean,
    modifier: Modifier = Modifier,
    /** Room whatever floats over the bottom of the editor needs kept clear. */
    bottomOverlayHeight: androidx.compose.ui.unit.Dp = 0.dp
) {
    var value by remember { mutableStateOf(TextFieldValue(text)) }
    /**
     * The last text this editor handed out. The script is saved as it's typed and
     * comes back through the store a moment later, so what arrives is usually one
     * of our own keystrokes catching up — and taking that as an outside edit would
     * put the caret back where the text was two letters ago.
     */
    var lastEmitted by remember { mutableStateOf(text) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current

    // The text can change from outside the editor — loading a note, importing a
    // file, adding the sample script.
    LaunchedEffect(text) {
        if (text != lastEmitted) {
            lastEmitted = text
            value = TextFieldValue(text, TextRange(text.length))
        }
    }

    LaunchedEffect(isFocused) {
        if (isFocused) {
            focusRequester.requestFocus()
        } else {
            focusManager.clearFocus()
            keyboard?.hide()
        }
    }

    fun apply(newValue: TextFieldValue) {
        value = newValue
        if (newValue.text != lastEmitted) {
            lastEmitted = newValue.text
            onTextChange(newValue.text)
        }
    }

    controller.onInsertCue = {
        // Past the end of a selection, so a cue never eats the words it's next
        // to — and past the end of the cue the caret is in, since cues don't nest.
        var location = value.selection.max
        TeleprompterParser.cueTagContaining(location, value.text)?.let {
            location = it.range.last + 1
        }
        val insertion = emptyCueInsertion(value.text, location)

        apply(
            TextFieldValue(
                text = value.text.replaceRange(location, location, insertion.first),
                selection = TextRange(location + insertion.second)
            )
        )

        if (!isFocused) {
            onFocusChange(true)
        }
    }

    val baseStyle = TextStyle(
        fontSize = EDITOR_FONT_SIZE,
        fontWeight = FontWeight.Medium,
        color = AppColors.textPrimary(isDark)
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .imePadding()
            .padding(bottom = bottomOverlayHeight)
            .verticalScroll(rememberScrollState())
    ) {
        Spacer(modifier = Modifier.height(CUE_EDITOR_EDGE_FADE))

        BasicTextField(
            value = value,
            onValueChange = { candidate -> apply(rewritingBrackets(value, candidate)) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .focusRequester(focusRequester)
                .onFocusChanged { state ->
                    if (state.isFocused != isFocused) {
                        onFocusChange(state.isFocused)
                    }
                },
            textStyle = baseStyle,
            cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
            visualTransformation = { original ->
                androidx.compose.ui.text.input.TransformedText(
                    highlighted(original.text, cueColor, isDark),
                    androidx.compose.ui.text.input.OffsetMapping.Identity
                )
            }
        )

        Spacer(modifier = Modifier.height(CUE_EDITOR_EDGE_FADE))
    }
}

/**
 * Color the closed cue tags. A cue being typed stays plain text until its
 * bracket lands.
 */
private fun highlighted(text: String, cueColor: CueColor, isDark: Boolean): AnnotatedString {
    val tagColor = cueColor.color(isDark)

    return androidx.compose.ui.text.buildAnnotatedString {
        append(text)

        for (match in TeleprompterParser.cueMatches(text)) {
            // The tag syntax stays visible — and editable — but recedes.
            addStyle(
                SpanStyle(color = tagColor.copy(alpha = 0.45f), fontWeight = FontWeight.Medium),
                match.range.first,
                match.range.last + 1
            )

            val contentStart = match.contentRange.first
            val contentEnd = match.contentRange.last + 1
            if (contentEnd > contentStart) {
                addStyle(
                    SpanStyle(color = tagColor, fontWeight = FontWeight.SemiBold),
                    contentStart,
                    contentEnd
                )
            }
        }
    }
}

/**
 * Writes both brackets on `[`, and takes them both back away again on the
 * backspace that follows, so a `[` meant literally costs one extra keystroke
 * instead of six.
 */
private fun rewritingBrackets(old: TextFieldValue, candidate: TextFieldValue): TextFieldValue {
    val oldText = old.text
    val newText = candidate.text

    // A single `[` typed at a collapsed caret.
    if (newText.length == oldText.length + 1 && candidate.selection.collapsed) {
        val insertedAt = candidate.selection.start - 1
        if (insertedAt >= 0 && newText.getOrNull(insertedAt) == '[' &&
            newText.removeRange(insertedAt, insertedAt + 1) == oldText
        ) {
            // Cues don't nest, and in here both brackets are already written,
            // so `[` has nothing left to do.
            if (TeleprompterParser.cueTagContaining(insertedAt, oldText) != null) {
                return old
            }

            return TextFieldValue(
                text = oldText.replaceRange(insertedAt, insertedAt, TeleprompterParser.EMPTY_CUE_TAG),
                selection = TextRange(insertedAt + TeleprompterParser.CUE_TAG_PREFIX.length)
            )
        }
    }

    // The backspace deleting the trailing space of an untouched `[cue ]`.
    if (newText.length == oldText.length - 1 && candidate.selection.collapsed) {
        val deletedAt = candidate.selection.start
        if (deletedAt >= 0 && deletedAt < oldText.length &&
            oldText.removeRange(deletedAt, deletedAt + 1) == newText
        ) {
            val start = deletedAt - (TeleprompterParser.CUE_TAG_PREFIX.length - 1)
            val end = start + TeleprompterParser.EMPTY_CUE_TAG.length
            if (start >= 0 && end <= oldText.length &&
                oldText.substring(start, end) == TeleprompterParser.EMPTY_CUE_TAG
            ) {
                return TextFieldValue(
                    text = oldText.replaceRange(start, end, "["),
                    selection = TextRange(start + 1)
                )
            }
        }
    }

    return candidate
}

/**
 * The text to splice in for an empty cue at `location`, spaced so it doesn't
 * collide with the words either side of it, and how far into that text the caret
 * belongs — between the brackets, ready for the cue to be typed.
 */
private fun emptyCueInsertion(text: String, location: Int): Pair<String, Int> {
    val previous = if (location > 0) text[location - 1] else null
    val next = if (location < text.length) text[location] else null

    val needsLeadingSpace = previous != null && !previous.isWhitespace()
    val needsTrailingSpace = next != null && !next.isWhitespace()

    val leading = if (needsLeadingSpace) " " else ""
    val insertion = leading + TeleprompterParser.EMPTY_CUE_TAG + (if (needsTrailingSpace) " " else "")
    val caretOffset = leading.length + TeleprompterParser.CUE_TAG_PREFIX.length

    return insertion to caretOffset
}

// MARK: - Cue bar

/**
 * The strip above the keyboard while a script is being written: one button to
 * drop a cue in at the caret, and one to get the keyboard out of the way.
 */
val CUE_BAR_HEIGHT = 54.dp

@Composable
fun CueBar(
    isDark: Boolean,
    onAddCue: () -> Unit,
    onDismissKeyboard: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(CUE_BAR_HEIGHT)
            .background(AppColors.background(isDark).copy(alpha = 0.94f))
            .drawBehind {
                drawRect(
                    color = AppColors.textSecondary(isDark).copy(alpha = 0.15f),
                    size = Size(size.width, 0.5.dp.toPx())
                )
            }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier
                .height(34.dp)
                .glassed(Capsule, isDark)
                .clickableWithoutRipple(onAddCue)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = null,
                tint = AppColors.textPrimary(isDark),
                modifier = Modifier.size(13.dp)
            )
            Text(
                text = "Add Cue",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark)
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        Box(
            modifier = Modifier
                .size(34.dp)
                .glassed(CircleShape, isDark)
                .clickableWithoutRipple(onDismissKeyboard),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.KeyboardHide,
                contentDescription = "Hide keyboard",
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier.size(15.dp)
            )
        }
    }
}

/** SwiftUI buttons don't ripple; these shouldn't either. */
@Composable
internal fun Modifier.clickableWithoutRipple(onClick: () -> Unit): Modifier =
    this.clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        onClick = onClick
    )
