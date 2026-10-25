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
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.FormatBold
import androidx.compose.material.icons.filled.FormatItalic
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.KeyboardHide
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.mutableIntStateOf
import com.thisisnsh.cuecard.android.services.ScriptImages
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.models.CueCards
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.CueFontFamily
import com.thisisnsh.cuecard.android.models.Emphasis
import com.thisisnsh.cuecard.android.models.EmphasisStyle
import com.thisisnsh.cuecard.android.models.RichText
import com.thisisnsh.cuecard.android.models.spanStyle
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.models.WideScript
import com.thisisnsh.cuecard.android.models.hasWideScript
import com.thisisnsh.cuecard.android.modifiers.Capsule
import com.thisisnsh.cuecard.android.modifiers.glassed
import android.net.Uri
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    internal var onInsertAnchor: (() -> Unit)? = null
    internal var onToggleStyle: ((EmphasisStyle) -> Unit)? = null
    internal var onInsertImages: ((List<String>) -> Unit)? = null

    /** Images are on their way in, and a spinner shows on the line they'll go on. */
    var isAddingImages by mutableStateOf(false)
        private set

    fun beginAddingImages() {
        isAddingImages = true
    }

    /** Place images from the store at the caret, each on a line of its own. */
    fun insertImages(names: List<String>) {
        isAddingImages = false
        if (names.isNotEmpty()) onInsertImages?.invoke(names)
    }

    /** Drop an empty cue at the caret and leave the caret inside it. */
    fun insertCue() {
        onInsertCue?.invoke()
    }

    /** Drop an `[anchor]` at the caret, for the teleprompter to jump to. */
    fun insertAnchor() {
        onInsertAnchor?.invoke()
    }

    /**
     * Bold or italicize the selection — or the word at the caret — or take
     * that style back off if it has it.
     */
    fun toggle(style: EmphasisStyle) {
        onToggleStyle?.invoke(style)
    }
}

/**
 * Script editor that renders `[cue …]` tags in the cue color while you type, and
 * writes the brackets for you: pressing `[` drops in a whole empty cue with the
 * caret inside it, so a cue is never left half-open — except inside a cue, where
 * there is nothing left for it to open.
 *
 * A card's editor is given the card's limit, and whatever runs past it is
 * marked in red.
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
    /** The text size the script is set in, from Settings. */
    fontSize: TextUnit,
    modifier: Modifier = Modifier,
    /** Room whatever floats over the bottom of the editor needs kept clear. */
    bottomOverlayHeight: androidx.compose.ui.unit.Dp = 0.dp,
    /** In a card, the characters it holds before the rest is marked. */
    cardLimit: Int? = null,
    /** Sized to its text, without scrolling, for a card in a list of them. */
    growsWithText: Boolean = false
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
    /**
     * Whether this field holds focus right now. Only the field that has it gives
     * it up, so a card losing focus to another card doesn't take it off that one.
     */
    var hasFocus by remember { mutableStateOf(false) }

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
        } else if (hasFocus) {
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

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isPastingImages by remember { mutableStateOf(false) }
    var pasteFailed by remember { mutableStateOf(false) }
    val onPasteImages = rememberUpdatedState<(List<Uri>) -> Unit> { uris ->
        if (!isPastingImages) {
            val insertionPoint = value
            isPastingImages = true
            scope.launch {
                try {
                    val names = withContext(Dispatchers.IO) {
                        uris.mapNotNull { ScriptImages.add(context, it) }
                    }
                    // An image belongs to the editor where Paste was used,
                    // even if another card gets focus while it is decoded.
                    // Never overwrite typing or a note loaded in the meantime.
                    if (value.text == insertionPoint.text) {
                        if (names.isNotEmpty()) apply(insertingImages(insertionPoint, names))
                        pasteFailed = names.size != uris.size
                    } else {
                        pasteFailed = true
                    }
                } finally {
                    isPastingImages = false
                }
            }
        }
    }
    val systemClipboard = LocalClipboardManager.current
    val scriptClipboard = remember(context, systemClipboard) {
        ScriptClipboard(context, systemClipboard) { onPasteImages.value(it) }
    }

    if (pasteFailed) {
        AlertDialog(
            onDismissRequest = { pasteFailed = false },
            text = { Text(stringResource(R.string.image_not_added)) },
            confirmButton = {
                TextButton(onClick = { pasteFailed = false }) { Text(stringResource(R.string.ok)) }
            }
        )
    }

    // With a card editor for every card, the cue bar writes into the one being
    // typed in.
    if (isFocused || controller.onInsertCue == null) {
        bindController(controller, { value }, ::apply, isFocused, onFocusChange) { value = it }
    }

    val isWide = remember(value.text) { value.text.hasWideScript }
    val density = LocalDensity.current
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    var fieldWidth by remember { mutableIntStateOf(0) }
    // The tallest an image is shown while writing: enough to tell what it
    // is, without pushing the words around it out of view.
    val maxImageHeight = with(density) { (if (growsWithText) 200.dp else 260.dp).toPx() }
    val images = remember(value.text, fieldWidth, maxImageHeight) {
        editorImages(value.text, fieldWidth.takeIf { it > 0 } ?: with(density) { 300.dp.roundToPx() }, maxImageHeight)
    }
    val baseStyle = TextStyle(
        fontSize = fontSize,
        fontWeight = FontWeight.Medium,
        color = AppColors.textPrimary(isDark),
        lineHeight = if (isWide) WideScript.lineHeight(fontSize.value).sp else TextUnit.Unspecified
    )

    val field: @Composable (Modifier) -> Unit = { fieldModifier ->
        CompositionLocalProvider(LocalClipboardManager provides scriptClipboard) {
            BasicTextField(
                value = value,
                onValueChange = { candidate -> apply(keepingImagesWhole(value, rewritingBrackets(value, candidate))) },
                onTextLayout = { layout = it },
                modifier = fieldModifier
                    .fillMaxWidth()
                    .onSizeChanged { fieldWidth = it.width }
                    // Each image over the line its tag holds open for it.
                    .drawWithContent {
                        drawContent()
                        val laidOut = layout ?: return@drawWithContent
                        for (image in images) drawEditorImage(image, laidOut)
                    }
                    .focusRequester(focusRequester)
                    // Ctrl+B and Ctrl+I on a hardware keyboard write the markers too.
                    .onPreviewKeyEvent { event ->
                        if (event.type != KeyEventType.KeyDown || !event.isCtrlPressed) return@onPreviewKeyEvent false
                        val style = when (event.key) {
                            Key.B -> EmphasisStyle.BOLD
                            Key.I -> EmphasisStyle.ITALIC
                            else -> return@onPreviewKeyEvent false
                        }
                        toggledEmphasis(value, style)?.let(::apply)
                        true
                    }
                    .onFocusChanged { state ->
                        hasFocus = state.isFocused
                        if (state.isFocused != isFocused) {
                            onFocusChange(state.isFocused)
                        }
                    },
                textStyle = baseStyle,
                cursorBrush = SolidColor(AppColors.textPrimary(isDark)),
                visualTransformation = { original ->
                    androidx.compose.ui.text.input.TransformedText(
                        highlighted(original.text, cueColor, isDark, fontSize, cardLimit, images, density),
                        androidx.compose.ui.text.input.OffsetMapping.Identity
                    )
                }
            )
        }
    }

    // A small spinner at the start of the line images are on their way to:
    // the line below, when the caret is partway along one.
    val withProgress: @Composable (Modifier) -> Unit = { fieldModifier ->
        Box(modifier = fieldModifier) {
            field(Modifier)
            val laidOut = layout
            if ((isPastingImages || (controller.isAddingImages && isFocused)) && laidOut != null) {
                val location = imageLocation(value)
                val line = laidOut.getLineForOffset(location.coerceIn(0, value.text.length))
                val atLineStart = location == 0 || value.text.getOrNull(location - 1) == '\n'
                val top = if (atLineStart) laidOut.getLineTop(line) else laidOut.getLineBottom(line)
                CircularProgressIndicator(
                    color = AppColors.textSecondary(isDark),
                    strokeWidth = 2.dp,
                    modifier = Modifier
                        .offset { IntOffset(0, top.toInt() + 2.dp.roundToPx()) }
                        .size(16.dp)
                )
            }
        }
    }

    // A card's editor grows with its text and leaves scrolling to the list it
    // sits in.
    if (growsWithText) {
        withProgress(modifier)
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .imePadding()
            .padding(bottom = bottomOverlayHeight)
            .verticalScroll(rememberScrollState())
    ) {
        Spacer(modifier = Modifier.height(CUE_EDITOR_EDGE_FADE))

        withProgress(Modifier.padding(horizontal = 20.dp))

        Spacer(modifier = Modifier.height(CUE_EDITOR_EDGE_FADE))
    }
}

/** Point the cue bar's buttons at this editor. */
private fun bindController(
    controller: CueEditorController,
    currentValue: () -> TextFieldValue,
    apply: (TextFieldValue) -> Unit,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    setValue: (TextFieldValue) -> Unit
) {
    controller.onInsertCue = {
        val value = currentValue()
        val location = tagLocation(value)
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

    controller.onInsertAnchor = {
        val value = currentValue()
        val location = tagLocation(value)
        val insertion = spacedInsertion(value.text, TeleprompterParser.ANCHOR_TAG, location).first

        apply(
            TextFieldValue(
                text = value.text.replaceRange(location, location, insertion),
                selection = TextRange(location + insertion.length)
            )
        )

        if (!isFocused) {
            onFocusChange(true)
        }
    }

    controller.onToggleStyle = { style ->
        toggledEmphasis(currentValue(), style)?.let(apply)
        if (!isFocused) {
            onFocusChange(true)
        }
    }

    controller.onInsertImages = { names ->
        apply(insertingImages(currentValue(), names))
        if (!isFocused) {
            onFocusChange(true)
        }
    }
}

/** Insert pictures on their own lines, after the selection or enclosing cue. */
internal fun insertingImages(value: TextFieldValue, names: List<String>): TextFieldValue {
    if (names.isEmpty()) return value
    val text = value.text
    val location = imageLocation(value)
    val insertion = buildString {
        if (location > 0 && text[location - 1] != '\n') append('\n')
        append(names.joinToString("\n") { TeleprompterParser.imageTag(it) })
        if (location == text.length || text[location] != '\n') append('\n')
    }
    val endsLine = location < text.length && text[location] == '\n'
    val caret = location + insertion.length + (if (endsLine) 1 else 0)
    return TextFieldValue(
        text = text.replaceRange(location, location, insertion),
        selection = TextRange(caret.coerceAtMost(text.length + insertion.length))
    )
}

/**
 * Style the script as it reads: cues apart from the words, and emphasis applied
 * with its markers left showing, quieter, so they can be edited.
 */
private fun highlighted(
    text: String,
    cueColor: CueColor,
    isDark: Boolean,
    fontSize: TextUnit,
    cardLimit: Int?,
    images: List<EditorImage>,
    density: Density
): AnnotatedString {
    val tagColor = cueColor.color(isDark)
    val secondary = AppColors.textSecondary(isDark)
    val cues = TeleprompterParser.cueMatches(text)
    val emphases = RichText.emphases(text, skipping = cues.map { it.range })

    return androidx.compose.ui.text.buildAnnotatedString {
        append(text)

        // Separators show in either mode, quieter than the words, so a script
        // written as cards reads as one in the teleprompter's editor too.
        // Anchors are set the same way: marks in the script, not words of it.
        val anchors = TeleprompterParser.anchorRanges(text)
        for (separator in CueCards.separatorRanges(text) + anchors) {
            addStyle(
                SpanStyle(
                    color = secondary,
                    fontSize = fontSize * 0.8f,
                    fontWeight = FontWeight.Bold
                ),
                separator.first,
                separator.last + 1
            )
        }

        // Each stretch takes every style written around it; an emphasis still
        // open shows its style already, as far as it has been typed.
        for (emphasis in emphases) {
            if (!emphasis.content.isEmpty()) {
                addStyle(emphasis.style.spanStyle(), emphasis.content.first, emphasis.content.last + 1)
            }
            for (marker in listOfNotNull(emphasis.open, emphasis.close)) {
                addStyle(SpanStyle(color = secondary), marker.first, marker.last + 1)
            }
        }

        // Only closed tags are colored, so a cue being typed stays plain text
        // until its bracket lands. Cues are set smaller and narrower than the
        // script, so they never read as part of it.
        for (match in cues) {
            // The tag syntax stays visible — and editable — but recedes.
            addStyle(
                SpanStyle(
                    color = tagColor.copy(alpha = 0.45f),
                    fontWeight = FontWeight.Medium,
                    fontFamily = CueFontFamily,
                    fontSize = fontSize * 0.85f
                ),
                match.range.first,
                match.range.last + 1
            )

            val contentStart = match.contentRange.first
            val contentEnd = match.contentRange.last + 1
            if (contentEnd > contentStart) {
                addStyle(
                    SpanStyle(color = tagColor, fontWeight = FontWeight.SemiBold, fontFamily = CueFontFamily),
                    contentStart,
                    contentEnd
                )
            }
        }

        // An image's tag holds its line open, as tall as the picture drawn
        // over it, and is itself out of sight. A tag sharing its line with
        // words just reads quieter.
        for (match in TeleprompterParser.imageMatches(text)) {
            val image = images.firstOrNull { it.range == match.range }
            if (image == null) {
                addStyle(SpanStyle(color = secondary), match.range.first, match.range.last + 1)
                continue
            }
            addStyle(SpanStyle(color = Color.Transparent, fontSize = 1.sp), match.range.first, match.range.last + 1)
            addStyle(
                ParagraphStyle(
                    lineHeight = with(density) { image.size.height.toSp() },
                    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None)
                ),
                match.range.first,
                match.range.last + 1
            )
        }

        // What a card holds past its limit, marked so it's plain where the card
        // has to end and a new one begin.
        if (cardLimit != null) {
            val red = AppColors.red(isDark)
            val markers = emphases.filter { it.isClosed }.flatMap { listOf(it.open, it.close!!) }
            val imageRanges = TeleprompterParser.imageMatches(text).map { it.range }
            for (card in CueCards.cardRanges(text)) {
                val overflow = CueCards.measure(card, text, cues, markers, imageRanges, anchors, cardLimit).overflow ?: continue
                addStyle(
                    SpanStyle(color = red, background = red.copy(alpha = 0.14f)),
                    overflow.first,
                    overflow.last + 1
                )
            }
        }
    }
}

// MARK: - Images

/** An image tag on a line of its own, and the size it's drawn at, in pixels. */
private data class EditorImage(val range: IntRange, val name: String, val size: Size)

/**
 * The images the editor draws: every image tag alone on its line, as wide as
 * the line and no taller than `maxHeight`.
 */
private fun editorImages(text: String, width: Int, maxHeight: Float): List<EditorImage> =
    TeleprompterParser.imageMatches(text).mapNotNull { match ->
        val startsLine = match.range.first == 0 || text[match.range.first - 1] == '\n'
        val endsLine = match.range.last + 1 == text.length || text[match.range.last + 1] == '\n'
        if (!startsLine || !endsLine) return@mapNotNull null
        val aspect = ScriptImages.aspectRatio(match.name)
        var size = Size(width.toFloat(), width * aspect)
        if (size.height > maxHeight) size = Size(maxHeight / aspect, maxHeight)
        EditorImage(match.range, match.name, size)
    }

/** The picture, rounded, on its line; a missing one as an empty frame. */
private fun DrawScope.drawEditorImage(image: EditorImage, layout: TextLayoutResult) {
    val line = layout.getLineForOffset(image.range.first)
    val top = layout.getLineTop(line) + (layout.getLineBottom(line) - layout.getLineTop(line) - image.size.height) / 2
    val radius = minOf(12.dp.toPx(), image.size.width * 0.04f)
    val path = Path().apply {
        addRoundRect(RoundRect(Rect(Offset(0f, top), image.size), CornerRadius(radius)))
    }
    clipPath(path) {
        val bitmap = ScriptImages.bitmap(image.name)
        if (bitmap != null) {
            drawImage(
                bitmap.asImageBitmap(),
                dstOffset = IntOffset(0, top.toInt()),
                dstSize = IntSize(image.size.width.toInt(), image.size.height.toInt())
            )
        } else {
            drawRect(Color.Gray.copy(alpha = 0.2f), Offset(0f, top), image.size)
        }
    }
}

/**
 * An image is one thing to the user, though the script holds its tag: a
 * backspace into one takes the whole tag, and the caret never rests inside one.
 */
private fun keepingImagesWhole(old: TextFieldValue, candidate: TextFieldValue): TextFieldValue {
    if (!old.text.contains("[image") && !candidate.text.contains("[image")) return candidate

    if (candidate.text.length == old.text.length - 1 && candidate.selection.collapsed) {
        val deletedAt = candidate.selection.start
        val tag = TeleprompterParser.imageMatches(old.text).firstOrNull { deletedAt in it.range }
        if (tag != null && old.text.removeRange(deletedAt, deletedAt + 1) == candidate.text) {
            return TextFieldValue(
                text = old.text.removeRange(tag.range.first, tag.range.last + 1),
                selection = TextRange(tag.range.first)
            )
        }
    }

    fun outside(offset: Int): Int {
        val tag = TeleprompterParser.imageMatches(candidate.text)
            .firstOrNull { offset > it.range.first && offset <= it.range.last } ?: return offset
        return tag.range.last + 1
    }
    val selection = candidate.selection
    val moved = TextRange(outside(selection.start), outside(selection.end))
    return if (moved == selection) candidate else candidate.copy(selection = moved)
}

/** Where images go: after the selection, or after the cue the caret is in. */
private fun imageLocation(value: TextFieldValue): Int {
    val location = value.selection.max
    return TeleprompterParser.cueTagContaining(location, value.text)?.let { it.range.last + 1 } ?: location
}

/**
 * Wrap the selection — or the word at the caret — in `style`'s Markdown, or
 * unwrap it if it's already set that way. With no word at the caret, the
 * markers go in with the caret between them. Null where there's nothing it can
 * do: across a cue, or across lines.
 */
private fun toggledEmphasis(value: TextFieldValue, style: EmphasisStyle): TextFieldValue? {
    val text = value.text
    val selectionStart = value.selection.min
    val selectionEnd = value.selection.max
    val hasSelection = selectionEnd > selectionStart
    val cues = TeleprompterParser.cueMatches(text)
    val styled = RichText.emphases(text, skipping = cues.map { it.range })
        .filter { it.isClosed && it.style == style }

    // Already set that way: take the markers back off.
    styled.firstOrNull { it.isAround(selectionStart, selectionEnd) }?.let { existing ->
        val content = existing.content
        val start = maxOf(content.first, selectionStart) - existing.open.count()
        val length = minOf(selectionEnd - selectionStart, content.count())
        return TextFieldValue(
            text = text.replaceRange(existing.range.first, existing.range.last + 1, text.substring(content)),
            selection = TextRange(start, start + length)
        )
    }

    var (targetStart, targetEnd) = if (hasSelection) selectionStart to selectionEnd else wordRange(text, selectionStart)
    while (targetStart < targetEnd && text[targetStart].isWhitespace()) targetStart += 1
    while (targetEnd > targetStart && text[targetEnd - 1].isWhitespace()) targetEnd -= 1
    val marker = style.marker

    if (targetEnd <= targetStart) {
        // Nothing to wrap: open and close it at the caret, ready to type into.
        return TextFieldValue(
            text = text.replaceRange(selectionStart, selectionEnd, marker + marker),
            selection = TextRange(selectionStart + marker.length)
        )
    }

    // Cues are drawn apart from the script and take no emphasis, and emphasis
    // doesn't run across lines.
    fun overlaps(range: IntRange) = range.first < targetEnd && range.last + 1 > targetStart
    if (cues.any { overlaps(it.range) } || text.substring(targetStart, targetEnd).contains('\n')) return null

    // Partly set that way already: take that emphasis in and set the lot.
    val overlapping = styled.filter { overlaps(it.range) }
    val spanStart = overlapping.minOfOrNull { it.range.first }?.coerceAtMost(targetStart) ?: targetStart
    val spanEnd = overlapping.maxOfOrNull { it.range.last + 1 }?.coerceAtLeast(targetEnd) ?: targetEnd
    val inner = StringBuilder(text.substring(spanStart, spanEnd))
    for (emphasis in overlapping.sortedByDescending { it.open.first }) {
        val close = emphasis.close!!
        inner.delete(close.first - spanStart, close.last + 1 - spanStart)
        inner.delete(emphasis.open.first - spanStart, emphasis.open.last + 1 - spanStart)
    }

    // A selection stays on the words; a caret at the end of its word carries
    // on after the closing marker, ready for plain text.
    val wrapped = marker + inner + marker
    val selection = when {
        hasSelection -> TextRange(spanStart + marker.length, spanStart + marker.length + inner.length)
        selectionStart >= targetEnd -> TextRange(spanStart + wrapped.length)
        else -> TextRange(selectionStart + marker.length)
    }
    return TextFieldValue(text = text.replaceRange(spanStart, spanEnd, wrapped), selection = selection)
}

/** The word the caret is in or just after, as start and end; empty if none. */
private fun wordRange(text: String, location: Int): Pair<Int, Int> {
    fun isWordCharacter(character: Char) = character.isLetterOrDigit() || character == '\''
    var start = location
    while (start > 0 && isWordCharacter(text[start - 1])) start -= 1
    var end = location
    while (end < text.length && isWordCharacter(text[end])) end += 1
    return start to end
}

/**
 * Whether the selection sits within what this styles — a caret touching
 * either end of the words counts.
 */
private fun Emphasis.isAround(selectionStart: Int, selectionEnd: Int): Boolean {
    val contentEnd = content.last + 1
    if (selectionStart == selectionEnd) {
        return content.first <= selectionStart && selectionStart <= contentEnd
    }
    return range.first <= selectionStart && selectionEnd <= range.last + 1 &&
        selectionStart < contentEnd && selectionEnd > content.first
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
    val (insertion, tagOffset) = spacedInsertion(text, TeleprompterParser.EMPTY_CUE_TAG, location)
    return insertion to tagOffset + TeleprompterParser.CUE_TAG_PREFIX.length
}

/**
 * Where a tag goes in at the caret: past the end of a selection, so it never
 * eats the words it's next to — and past the end of the cue the caret is in,
 * since nothing goes inside a cue.
 */
private fun tagLocation(value: TextFieldValue): Int {
    val location = value.selection.max
    return TeleprompterParser.cueTagContaining(location, value.text)?.let { it.range.last + 1 } ?: location
}

/**
 * The text to splice in for `tag` at `location`, spaced so it doesn't collide
 * with the words either side of it, and how far into that text the tag starts.
 */
private fun spacedInsertion(text: String, tag: String, location: Int): Pair<String, Int> {
    val previous = if (location > 0) text[location - 1] else null
    val next = if (location < text.length) text[location] else null

    val needsLeadingSpace = previous != null && !previous.isWhitespace()
    val needsTrailingSpace = next != null && !next.isWhitespace()

    val leading = if (needsLeadingSpace) " " else ""
    return leading + tag + (if (needsTrailingSpace) " " else "") to leading.length
}

// MARK: - Cue bar

/**
 * The strip above the keyboard while a script is being written: buttons to drop
 * a cue, an anchor or an image in at the caret and to bold or italicize, and
 * one to get the keyboard out of the way.
 */
val CUE_BAR_HEIGHT = 54.dp

@Composable
fun CueBar(
    isDark: Boolean,
    onAddCue: () -> Unit,
    /** Null where anchors aren't used, which leaves the button out. */
    onAddAnchor: (() -> Unit)?,
    onAddImage: () -> Unit,
    onFormat: (EmphasisStyle) -> Unit,
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
        // The buttons don't fit a small phone with their full names, so they
        // shorten when they have to.
        FirstThatFits(
            modifier = Modifier.weight(1f),
            full = { CueBarButtons(isDark, short = false, onAddCue, onAddAnchor, onAddImage, onFormat) },
            short = { CueBarButtons(isDark, short = true, onAddCue, onAddAnchor, onAddImage, onFormat) }
        )

        Box(
            modifier = Modifier
                .size(34.dp)
                .glassed(CircleShape, isDark)
                .clickableWithoutRipple(onDismissKeyboard),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.KeyboardHide,
                contentDescription = stringResource(R.string.hide_keyboard),
                tint = AppColors.textSecondary(isDark),
                modifier = Modifier.size(15.dp)
            )
        }
    }
}

@Composable
private fun CueBarButtons(
    isDark: Boolean,
    short: Boolean,
    onAddCue: () -> Unit,
    onAddAnchor: (() -> Unit)?,
    onAddImage: () -> Unit,
    onFormat: (EmphasisStyle) -> Unit
) {
    val addCue = stringResource(R.string.add_cue)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier
                .height(34.dp)
                .glassed(Capsule, isDark)
                .clickableWithoutRipple(onAddCue)
                .semantics(mergeDescendants = true) { contentDescription = addCue }
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
                text = if (short) stringResource(R.string.cue_short) else addCue,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.textPrimary(isDark),
                maxLines = 1,
                softWrap = false
            )
        }

        // Bold and italic, sharing one capsule.
        Row(
            modifier = Modifier
                .height(34.dp)
                .glassed(Capsule, isDark)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            FormatButton(Icons.Filled.FormatBold, stringResource(R.string.bold), isDark) {
                onFormat(EmphasisStyle.BOLD)
            }
            FormatButton(Icons.Filled.FormatItalic, stringResource(R.string.italic), isDark) {
                onFormat(EmphasisStyle.ITALIC)
            }
        }

        // An anchor and an image share a capsule too, so the bar still fits a
        // small phone with the anchor in.
        Row(
            modifier = Modifier
                .height(34.dp)
                .glassed(Capsule, isDark)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (onAddAnchor != null) {
                FormatButton(Icons.Filled.BookmarkBorder, stringResource(R.string.add_anchor), isDark, onAddAnchor)
            }
            FormatButton(Icons.Filled.Image, stringResource(R.string.add_image), isDark, onAddImage)
        }
    }
}

@Composable
private fun FormatButton(icon: ImageVector, label: String, isDark: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .width(32.dp)
            .height(34.dp)
            .clickableWithoutRipple(onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = AppColors.textPrimary(isDark),
            modifier = Modifier.size(18.dp)
        )
    }
}

/** `full` where it fits the width it's given, otherwise `short`. */
@Composable
private fun FirstThatFits(
    modifier: Modifier = Modifier,
    full: @Composable () -> Unit,
    short: @Composable () -> Unit
) {
    SubcomposeLayout(modifier) { constraints ->
        val loose = constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity)
        val fullPlaceable = subcompose("full", full).first().measure(loose)
        val placeable = if (fullPlaceable.width <= constraints.maxWidth) {
            fullPlaceable
        } else {
            subcompose("short", short).first().measure(constraints.copy(minWidth = 0))
        }
        layout(constraints.maxWidth, placeable.height) {
            placeable.placeRelative(0, 0)
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
