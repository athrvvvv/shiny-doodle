package com.example.song_downloader

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.songdownloader/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Python on Android
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVideoInfo" -> {
                    val url = call.argument<String>("url") ?: ""
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val py = Python.getInstance()
                            val module = py.getModule("downloader")
                            val jsonRes = module.callAttr("get_video_info", url).toString()
                            withContext(Dispatchers.Main) {
                                result.success(jsonRes)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("PYTHON_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "downloadAudio" -> {
                    val url = call.argument<String>("url") ?: ""
                    val outputDir = call.argument<String>("outputDir") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "audio"
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val py = Python.getInstance()
                            val module = py.getModule("downloader")
                            val jsonRes = module.callAttr("download_audio", url, outputDir, fileName).toString()
                            withContext(Dispatchers.Main) {
                                result.success(jsonRes)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("PYTHON_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "scanMediaFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
                    val title = call.argument<String>("title")
                    val artist = call.argument<String>("artist")

                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "Path cannot be empty", null)
                        return@setMethodCallHandler
                    }

                    val file = File(path)
                    if (file.exists()) {
                        file.setLastModified(System.currentTimeMillis())
                    }

                    var responded = false
                    fun sendSuccess(uriStr: String?) {
                        if (!responded) {
                            responded = true
                            CoroutineScope(Dispatchers.Main).launch {
                                result.success(uriStr ?: "scanned")
                            }
                        }
                    }

                    try {
                        // 1. Send broadcast intent for Samsung, Xiaomi, and other OEM pickers
                        try {
                            val uriFromFile = Uri.fromFile(file)
                            val scanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                                data = uriFromFile
                            }
                            applicationContext.sendBroadcast(scanIntent)
                        } catch (_: Exception) {}

                        // 2. Direct MediaScannerConnection scan
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            arrayOf(mimeType)
                        ) { scannedPath, uri ->
                            Log.d("SongDownloader", "MediaScanner indexed: $scannedPath -> $uri")
                            if (uri != null) {
                                try {
                                    val nowSec = System.currentTimeMillis() / 1000
                                    val values = ContentValues().apply {
                                        put(MediaStore.Audio.Media.IS_MUSIC, 1)
                                        put(MediaStore.Audio.Media.DATE_ADDED, nowSec)
                                        put(MediaStore.Audio.Media.DATE_MODIFIED, nowSec)
                                        if (!title.isNullOrBlank()) {
                                            put(MediaStore.Audio.Media.TITLE, title)
                                        }
                                        if (!artist.isNullOrBlank()) {
                                            put(MediaStore.Audio.Media.ARTIST, artist)
                                        }
                                        put(MediaStore.Audio.Media.ALBUM, "Song Downloader")
                                    }
                                    contentResolver.update(uri, values, null, null)
                                } catch (e: Exception) {
                                    Log.w("SongDownloader", "MediaStore update warning: ${e.message}")
                                }
                            }
                            sendSuccess(uri?.toString())
                        }

                        // Safety fallback in case scanner callback is delayed
                        CoroutineScope(Dispatchers.Default).launch {
                            delay(1200)
                            sendSuccess("fallback_completed")
                        }
                    } catch (e: Exception) {
                        result.error("SCAN_ERROR", e.message, null)
                    }
                }
                "getDeviceAudios" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val audioList = mutableListOf<Map<String, Any?>>()
                            val seenPaths = HashSet<String>()

                            val projection = arrayOf(
                                MediaStore.Audio.Media._ID,
                                MediaStore.Audio.Media.TITLE,
                                MediaStore.Audio.Media.ARTIST,
                                MediaStore.Audio.Media.ALBUM,
                                MediaStore.Audio.Media.DURATION,
                                MediaStore.Audio.Media.DATA,
                                MediaStore.Audio.Media.SIZE,
                                MediaStore.Audio.Media.DATE_ADDED
                            )
                            val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/mpeg' OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/mp4' OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/m4a' OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/flac' OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/x-wav' OR ${MediaStore.Audio.Media.MIME_TYPE} = 'audio/ogg'"
                            val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

                            contentResolver.query(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                projection,
                                selection,
                                null,
                                sortOrder
                            )?.use { cursor ->
                                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                                val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                                val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                                val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                                val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)

                                while (cursor.moveToNext()) {
                                    val path = cursor.getString(dataCol) ?: ""
                                    if (path.isNotEmpty() && File(path).exists()) {
                                        seenPaths.add(path)
                                        val item = mapOf(
                                            "id" to cursor.getLong(idCol),
                                            "title" to (cursor.getString(titleCol) ?: File(path).nameWithoutExtension),
                                            "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                                            "album" to (cursor.getString(albumCol) ?: ""),
                                            "durationMs" to cursor.getLong(durationCol),
                                            "path" to path,
                                            "sizeBytes" to cursor.getLong(sizeCol),
                                            "dateAdded" to cursor.getLong(dateAddedCol)
                                        )
                                        audioList.add(item)
                                    }
                                }
                            }

                            // Also scan /storage/emulated/0/Download & /storage/emulated/0/Music in case any audio file wasn't indexed yet
                            val directoriesToScan = listOf(
                                File("/storage/emulated/0/Download"),
                                File("/storage/emulated/0/Music")
                            )
                            val audioExtensions = setOf("mp3", "m4a", "wav", "aac", "flac", "ogg", "opus")

                            for (dir in directoriesToScan) {
                                if (dir.exists() && dir.isDirectory) {
                                    val files = dir.listFiles() ?: emptyArray()
                                    for (file in files) {
                                        if (file.isFile && audioExtensions.contains(file.extension.lowercase())) {
                                            if (!seenPaths.contains(file.absolutePath)) {
                                                seenPaths.add(file.absolutePath)
                                                val item = mapOf(
                                                    "id" to System.currentTimeMillis() + file.hashCode(),
                                                    "title" to file.nameWithoutExtension,
                                                    "artist" to "Unknown Artist",
                                                    "album" to dir.name,
                                                    "durationMs" to 0L,
                                                    "path" to file.absolutePath,
                                                    "sizeBytes" to file.length(),
                                                    "dateAdded" to (file.lastModified() / 1000)
                                                )
                                                audioList.add(item)
                                            }
                                        }
                                    }
                                }
                            }

                            withContext(Dispatchers.Main) {
                                result.success(audioList)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("QUERY_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
