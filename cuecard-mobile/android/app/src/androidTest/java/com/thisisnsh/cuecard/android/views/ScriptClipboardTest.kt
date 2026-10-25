package com.thisisnsh.cuecard.android.views

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.thisisnsh.cuecard.android.models.CueColor
import com.thisisnsh.cuecard.android.models.TeleprompterParser
import com.thisisnsh.cuecard.android.services.ScriptImages
import com.thisisnsh.cuecard.android.services.WhatsNewService
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

@OptIn(ExperimentalTestApi::class)
class ScriptClipboardTest {
    @get:Rule val compose = createComposeRule()
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val clipboard = context.getSystemService(ClipboardManager::class.java)
    private val script = mutableStateOf("")

    private fun editor(initial: String, cards: Boolean = false) {
        script.value = initial
        compose.setContent {
            val focused = remember { mutableStateOf(false) }
            MaterialTheme {
                CueTextEditor(
                    text = script.value,
                    onTextChange = { script.value = it },
                    isFocused = focused.value,
                    onFocusChange = { focused.value = it },
                    controller = remember { CueEditorController() },
                    cueColor = CueColor.DEFAULT,
                    isDark = false,
                    fontSize = 16.sp,
                    growsWithText = cards
                )
            }
        }
        compose.onNode(hasSetTextAction()).performClick()
    }

    private fun image(color: Int): Pair<String, Uri> {
        val bitmap = Bitmap.createBitmap(16, 12, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(color)
        val name = requireNotNull(ScriptImages.add(bitmap))
        bitmap.recycle()
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", ScriptImages.file(name)!!)
        return name to uri
    }

    private fun paste(clip: ClipData, selection: TextRange) {
        compose.onNode(hasSetTextAction()).performTextInputSelection(selection)
        compose.runOnIdle { clipboard.setPrimaryClip(clip) }
        compose.onNode(hasSetTextAction()).performSemanticsAction(SemanticsActions.PasteText) { it() }
    }

    @Test fun plainTextStillReplacesTheSelection() {
        editor("Hello world")
        paste(ClipData.newPlainText("text", "everyone"), TextRange(6, 11))
        compose.runOnIdle { assertEquals("Hello everyone", script.value) }
    }

    @Test fun pictureWithSourceLinkGoesAfterTheCueWithoutChangingItsText() {
        val (name, uri) = image(android.graphics.Color.RED)
        editor("Hi [cue smile] there")
        val clip = ClipData("image", arrayOf("image/png", "text/plain"),
            ClipData.Item("https://example.com/photo", null, uri))
        paste(clip, TextRange(9))
        compose.waitUntil(5_000) { script.value.contains("[image") }
        compose.runOnIdle {
            assertEquals("Hi [cue smile]\n[image $name]\n there", script.value)
        }
    }

    @Test fun multipleImagesPasteIntoCardsInOrder() {
        val first = image(android.graphics.Color.RED)
        val second = image(android.graphics.Color.BLUE)
        editor("Card", cards = true)
        val clip = ClipData.newUri(context.contentResolver, "images", first.second)
        clip.addItem(ClipData.Item(second.second))
        paste(clip, TextRange(4))
        compose.waitUntil(5_000) { TeleprompterParser.imageMatches(script.value).size == 2 }
        compose.runOnIdle {
            assertEquals("Card\n[image ${first.first}]\n[image ${second.first}]\n", script.value)
        }
    }

    @Test fun copyingAnImageProvidesBothScriptAndReadableImageData() {
        val (name, _) = image(android.graphics.Color.GREEN)
        val tag = TeleprompterParser.imageTag(name)
        editor(tag)
        compose.onNode(hasSetTextAction()).performTextInputSelection(TextRange(0, tag.length))
        compose.onNode(hasSetTextAction()).performSemanticsAction(SemanticsActions.CopyText) { it() }
        lateinit var copied: ClipData
        compose.runOnIdle {
            copied = clipboard.primaryClip!!
            assertEquals(tag, copied.getItemAt(0).text.toString())
            assertTrue(copied.description.hasMimeType("image/*"))
            assertNotNull(copied.getItemAt(0).uri)
        }
        val bytes = context.contentResolver.openInputStream(copied.getItemAt(0).uri)!!.use { it.readBytes() }
        assertArrayEquals(ScriptImages.data(name), bytes)

        // Pasting back into CueCard uses the text representation, including
        // normal replacement of a selected image, rather than adding another.
        paste(copied, TextRange(0, tag.length))
        compose.runOnIdle { assertEquals(tag, script.value) }
    }

    @Test fun textWithAnImageAttachmentRemainsText() {
        val (_, uri) = image(android.graphics.Color.YELLOW)
        editor("Before")
        val clip = ClipData("text", arrayOf("text/plain", "image/png"),
            ClipData.Item(" words", null, uri))
        paste(clip, TextRange(6))
        compose.runOnIdle { assertEquals("Before words", script.value) }
    }

    @Test fun unavailableImageDoesNotInsertItsUriOrEraseTheScript() {
        editor("Keep this")
        val missing = File(context.filesDir, "ScriptImages/missing-clipboard-test.png")
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", missing)
        paste(ClipData.newUri(context.contentResolver, "missing", uri), TextRange(0, 9))
        compose.waitUntil(5_000) {
            compose.onAllNodes(androidx.compose.ui.test.hasText(context.getString(com.thisisnsh.cuecard.android.R.string.image_not_added)))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.runOnIdle { assertEquals("Keep this", script.value) }
    }

    @Test fun firstReleaseHasNoWhatsNew() {
        assertEquals("{}", context.assets.open("WhatsNew.json").bufferedReader().use { it.readText().trim() })
        val service = WhatsNewService.getInstance(context)
        assertNull(service.release)
        service.presentIfUnseen(hasSeenWelcome = true)
        assertFalse(service.isPresented.value)
    }
}
