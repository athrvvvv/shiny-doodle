package com.example.song_downloader

import android.os.Bundle
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
                else -> result.notImplemented()
            }
        }
    }
}
