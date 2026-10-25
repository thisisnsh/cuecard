package com.thisisnsh.cuecard.android.views

import android.content.ClipData
import android.content.ClipDescription
import android.content.Context
import android.net.Uri
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.services.ScriptImages

/**
 * The value-based Compose editor pastes through ClipboardManager, including
 * its selection menu, accessibility action and hardware keyboard shortcuts.
 * Keep ordinary text on that path, and hand image decoding to the editor.
 */
internal class ScriptClipboard(
    private val context: Context,
    private val delegate: ClipboardManager,
    private val pasteImages: (List<Uri>) -> Unit
) : ClipboardManager by delegate {
    private val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)

    override fun hasText(): Boolean =
        delegate.hasText() || clipboard.primaryClipDescription?.hasMimeType("image/*") == true

    override fun getText(): AnnotatedString? {
        val clip = clipboard.primaryClip ?: return null
        val images = mutableListOf<Uri>()
        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            val text = item.text?.toString().orEmpty()
            // Text copied here keeps its script tags. Elsewhere an image can
            // carry its source URL; paste that as a picture, as iOS does.
            if (text.isNotBlank() && text.toUri().scheme !in listOf("http", "https")) {
                return delegate.getText()
            }
            val uri = item.uri ?: continue
            if (uri.scheme == "content" && runCatching {
                    context.contentResolver.getType(uri)?.startsWith("image/") == true
                }.getOrDefault(false)) {
                images.add(uri)
            }
        }
        if (images.isEmpty()) return delegate.getText()
        pasteImages(images)
        return null
    }

    override fun setText(annotatedString: AnnotatedString) {
        val text = annotatedString.text.trim()
        val image = TeleprompterParser.imageMatches(text).singleOrNull()
        val file = image?.takeIf { it.range == text.indices }?.let { ScriptImages.file(it.name) }
        if (file == null || !file.exists()) {
            delegate.setText(annotatedString)
            return
        }

        // Include both representations: another CueCard editor gets script,
        // while other apps can request the image. Android grants access only
        // to this URI when the receiving app reads the clipboard.
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val mime = context.contentResolver.getType(uri) ?: "image/*"
        clipboard.setPrimaryClip(
            ClipData(
                "CueCard",
                arrayOf(ClipDescription.MIMETYPE_TEXT_PLAIN, mime),
                ClipData.Item(annotatedString.text, null, uri)
            )
        )
    }
}
