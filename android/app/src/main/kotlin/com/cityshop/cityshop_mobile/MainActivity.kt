package com.cityshop.cityshop_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "cityshop/document_picker"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickDocument") {
                    if (pendingResult != null) {
                        result.error("busy", "A file picker is already open.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf(
                                "application/pdf",
                                "application/msword",
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                "application/vnd.ms-excel",
                                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                "application/vnd.ms-powerpoint",
                                "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                                "text/plain",
                                "text/csv",
                                "application/zip",
                                "application/x-zip-compressed",
                                "application/rtf",
                                "application/vnd.oasis.opendocument.text",
                                "application/vnd.oasis.opendocument.spreadsheet",
                            ),
                        )
                    }
                    startActivityForResult(intent, REQUEST_PICK)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK) return
        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        try {
            val uri = data.data!!
            val name = queryDisplayName(uri) ?: "file"
            val mime = contentResolver.getType(uri)
            val cached = File(cacheDir, "chat_pick_${System.currentTimeMillis()}_$name")
            contentResolver.openInputStream(uri).use { input ->
                FileOutputStream(cached).use { output ->
                    if (input == null) throw IllegalStateException("Could not open file")
                    input.copyTo(output)
                }
            }
            result.success(
                mapOf(
                    "path" to cached.absolutePath,
                    "name" to name,
                    "size" to cached.length(),
                    "mime" to mime,
                ),
            )
        } catch (e: Exception) {
            result.error("pick_failed", e.message, null)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return uri.lastPathSegment
    }

    companion object {
        private const val REQUEST_PICK = 44121
    }
}
