package com.kyoiryi.anivault

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val mediaPickerChannel = "anivault/media_picker"
    private val pickVideosRequestCode = 4101
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaPickerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideos" -> pickVideos(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickVideos(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICKER_BUSY", "A media picker is already open.", null)
            return
        }

        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "video/mp4",
                    "video/x-matroska",
                    "video/webm",
                    "video/avi",
                    "video/quicktime",
                    "application/octet-stream",
                ),
            )
        }
        startActivityForResult(intent, pickVideosRequestCode)
    }

    @Deprecated("Deprecated in Android API; FlutterActivity still supports this callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickVideosRequestCode) return

        val result = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        val uris = mutableListOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clipData ->
            for (index in 0 until clipData.itemCount) {
                uris.add(clipData.getItemAt(index).uri)
            }
        }

        Thread {
            try {
                val paths = uris.distinct().map { copyUriToLibrary(it) }
                runOnUiThread { result.success(paths) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "MEDIA_IMPORT_FAILED",
                        error.message ?: "Failed to import selected media.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyUriToLibrary(uri: Uri): String {
        val importDir = File(filesDir, "ImportedVideos")
        if (!importDir.exists()) importDir.mkdirs()

        val displayName = displayNameFor(uri)
        val target = uniqueTarget(importDir, displayName)

        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Could not open selected media." }
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                }
                output.flush()
            }
        }

        return target.absolutePath
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        return sanitizeFileName(cursor.getString(index))
                    }
                }
            }
        return "video-${UUID.nameUUIDFromBytes(uri.toString().toByteArray())}.mp4"
    }

    private fun sanitizeFileName(rawName: String?): String {
        val fallback = "video-${System.currentTimeMillis()}.mp4"
        val name = rawName?.substringAfterLast('/')?.replace("..", "_") ?: fallback
        return name.ifBlank { fallback }
    }

    private fun uniqueTarget(directory: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var candidate = File(directory, fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "$baseName ($index)$extension")
            index += 1
        }
        return candidate
    }
}
