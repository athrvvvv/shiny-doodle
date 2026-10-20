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
                else -> result.notImplemented()
            }
        }
    }
}
