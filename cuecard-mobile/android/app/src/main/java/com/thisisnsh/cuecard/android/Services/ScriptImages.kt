package com.thisisnsh.cuecard.android.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.util.LruCache
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The images placed in scripts, one file each in the app's own storage on
 * this device. A file is named for what's in it, so the same picture added
 * twice, or brought back in with an import, is only kept once.
 *
 * A script holds `[image name]` where the image goes. Files that nothing still
 * places — no script being written, saved note or version — are deleted at
 * launch.
 *
 * Everything here reads or writes files, so it's called off the main thread,
 * except `bitmap`, which is cached once read.
 */
object ScriptImages {
    /**
     * The longest side an image is kept at. Plenty for any screen it's read
     * on, and small enough that a script full of photos still shares easily.
     */
    const val MAX_PIXEL_SIZE = 2048

    private val namePattern = Regex("^[A-Za-z0-9-]+\\.[A-Za-z0-9]+$")
    private lateinit var directory: File
    private val cache = object : LruCache<String, Bitmap>(64 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun init(context: Context) {
        directory = File(context.filesDir, "ScriptImages")
    }

    /**
     * Whether `name` could be one of the store's files: letters, digits and
     * dashes, then an extension, as an `[image …]` tag allows.
     */
    fun isValidName(name: String): Boolean = namePattern.matches(name)

    /** Where an image is kept. Null for a name that isn't a plain file name. */
    fun file(name: String): File? = if (isValidName(name)) File(directory, name) else null

    fun contains(name: String): Boolean = file(name)?.exists() == true

    fun data(name: String): ByteArray? = file(name)?.takeIf { it.exists() }?.let { runCatching { it.readBytes() }.getOrNull() }

    /** The picture, read once and kept in memory. */
    fun bitmap(name: String): Bitmap? {
        cache.get(name)?.let { return it }
        val file = file(name)?.takeIf { it.exists() } ?: return null
        val bitmap = BitmapFactory.decodeFile(file.path) ?: return null
        cache.put(name, bitmap)
        return bitmap
    }

    /** How tall the picture is for its width; a missing one is 4:3. */
    fun aspectRatio(name: String): Float {
        val bitmap = bitmap(name) ?: return 0.75f
        return if (bitmap.width > 0 && bitmap.height > 0) bitmap.height.toFloat() / bitmap.width else 0.75f
    }

    /**
     * Lines of reading time the image takes in the teleprompter, so the script
     * doesn't race past it: more for a tall picture than a wide one.
     */
    fun readingLines(name: String): Int = (4 * aspectRatio(name)).roundToInt().coerceIn(2, 8)

    /**
     * Keep the picture at `uri`, scaled down to `MAX_PIXEL_SIZE` and turned
     * upright, and return its name. Null if it isn't an image or couldn't be kept.
     */
    fun add(context: Context, uri: Uri): String? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        runCatching { resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        // Decoded no larger than it needs to be, then scaled the rest of the way.
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PIXEL_SIZE) sample *= 2
        val decoded = runCatching {
            resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            }
        }.getOrNull() ?: return null
        val orientation = runCatching {
            resolver.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
        }.getOrNull() ?: ExifInterface.ORIENTATION_NORMAL
        return add(upright(decoded, orientation))
    }

    /** Keep a picture, scaled down to `MAX_PIXEL_SIZE`, and return its name. */
    fun add(bitmap: Bitmap): String? {
        val longest = max(bitmap.width, bitmap.height)
        val scaled = if (longest > MAX_PIXEL_SIZE) {
            val scale = MAX_PIXEL_SIZE.toFloat() / longest
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).roundToInt(), (bitmap.height * scale).roundToInt(), true)
        } else {
            bitmap
        }

        // Photos as JPEG; anything with see-through parts as PNG, to keep them.
        val isPNG = scaled.hasAlpha()
        val encoded = ByteArrayOutputStream()
        val format = if (isPNG) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
        if (!scaled.compress(format, 85, encoded)) return null

        val data = encoded.toByteArray()
        val hash = MessageDigest.getInstance("SHA-256").digest(data).take(16).joinToString("") { "%02x".format(it) }
        val name = "$hash.${if (isPNG) "png" else "jpg"}"
        return if (write(data, name)) name else null
    }

    private fun upright(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    /**
     * Keep `data` as `name`, a file from the notes folder or a TextPack,
     * without changing it. False if the name isn't one the store uses, or the
     * data isn't an image.
     */
    fun add(data: ByteArray, name: String): Boolean {
        if (!isValidName(name)) return false
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0) return false
        return write(data, name)
    }

    private fun write(data: ByteArray, name: String): Boolean {
        val file = file(name) ?: return false
        if (file.exists()) return true
        return runCatching {
            directory.mkdirs()
            val temporary = File(directory, "$name.tmp")
            temporary.writeBytes(data)
            temporary.renameTo(file)
        }.getOrDefault(false)
    }

    /**
     * Delete every image not in `names`. An image added in the last day is
     * kept whatever, so one placed while this runs is never caught by it.
     */
    fun removeUnused(keeping: Set<String>) {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        for (file in directory.listFiles().orEmpty()) {
            if (file.name in keeping || file.lastModified() >= cutoff) continue
            file.delete()
            cache.remove(file.name)
        }
    }

    fun removeAll() {
        directory.deleteRecursively()
        cache.evictAll()
    }
}
