import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/download_item.dart';

class YouTubeDownloaderService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.songdownloader/native');

  /// Extract clean YouTube video ID or full URL
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final idRegex = RegExp(r'^[a-zA-Z0-9_-]{11}$');
    if (idRegex.hasMatch(trimmed)) return trimmed;

    final urlRegex = RegExp(
      r'(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(trimmed);
    return match?.group(1);
  }

  /// Request storage permissions
  Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.audio.isGranted || await Permission.storage.isGranted) {
      return true;
    }

    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) return true;

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted || storageStatus.isLimited;
  }

  /// Determine the best output directory for user-visible MP3s
  Future<Directory> _getPublicDownloadDirectory() async {
    if (Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (await publicDownload.exists()) {
        return publicDownload;
      }
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) return externalDir;
      } catch (_) {}
    }

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return downloadsDir;
    } catch (_) {}

    return await getApplicationDocumentsDirectory();
  }

  String _formatSeconds(dynamic seconds) {
    if (seconds == null) return '--:--';
    final total = seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0;
    if (total <= 0) return '--:--';
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num = bytes / (1 << (i * 10));
    return '${num.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Main download entry point - runs 100% on-device!
  Future<void> startDownload({
    required DownloadItem item,
    required void Function(DownloadItem updatedItem) onProgress,
  }) async {
    File? rawAudioFile;
    try {
      await requestStoragePermissions();

      final fullUrl = item.url.startsWith('http')
          ? item.url
          : 'https://www.youtube.com/watch?v=${item.id}';

      // Stage 1: On-device metadata extraction
      item.status = DownloadStatus.fetchingInfo;
      item.statusMessage = 'Reading song metadata (on-device)...';
      item.progress = 0.10;
      onProgress(item);

      final String? infoJsonStr = await _nativeChannel.invokeMethod<String>(
        'getVideoInfo',
        {'url': fullUrl},
      );

      if (infoJsonStr != null) {
        final Map<String, dynamic> infoMap = json.decode(infoJsonStr);
        if (infoMap['success'] == true) {
          item.title = infoMap['title'] ?? item.title;
          item.author = infoMap['artist'] ?? item.author;
          item.thumbnailUrl = infoMap['thumbnail'] ?? item.thumbnailUrl;
          item.duration = _formatSeconds(infoMap['duration']);
          item.progress = 0.25;
          onProgress(item);
        }
      }

      // Stage 2: Download raw audio track on device via embedded yt-dlp
      item.status = DownloadStatus.downloading;
      item.statusMessage = 'Downloading audio track on phone...';
      item.progress = 0.35;
      onProgress(item);

      final tempDir = await getTemporaryDirectory();
      final tempFileName = 'temp_${item.id}_${DateTime.now().millisecondsSinceEpoch}';

      final String? downloadJsonStr = await _nativeChannel.invokeMethod<String>(
        'downloadAudio',
        {
          'url': fullUrl,
          'outputDir': tempDir.path,
          'fileName': tempFileName,
        },
      );

      if (downloadJsonStr == null) {
        throw Exception('Native audio download returned empty response');
      }

      final Map<String, dynamic> downloadMap = json.decode(downloadJsonStr);
      if (downloadMap['success'] != true) {
        throw Exception(downloadMap['error'] ?? 'Audio extraction failed');
      }

      final String rawPath = downloadMap['path'];
      rawAudioFile = File(rawPath);
      if (!await rawAudioFile.exists()) {
        throw Exception('Extracted audio file not found on disk');
      }

      final rawFileSize = await rawAudioFile.length();
      item.fileSizeBytes = rawFileSize;
      item.progress = 0.70;
      item.statusMessage = 'Converting to 320k MP3 (FFmpeg)...';
      item.status = DownloadStatus.converting;
      onProgress(item);

      // Stage 3: Transcode to high quality 320k MP3 with ID3 tags
      final targetDirectory = await _getPublicDownloadDirectory();
      final safeTitle = _sanitizeFileName(item.title);
      var destinationMp3Path = '${targetDirectory.path}/$safeTitle.mp3';

      int counter = 1;
      while (await File(destinationMp3Path).exists()) {
        destinationMp3Path = '${targetDirectory.path}/${safeTitle}_$counter.mp3';
        counter++;
      }

      final ffmpegCmd =
          '-y -i "$rawPath" -vn -c:a libmp3lame -b:a 320k '
          '-metadata title="${item.title.replaceAll('"', r'\"')}" '
          '-metadata artist="${item.author.replaceAll('"', r'\"')}" '
          '"$destinationMp3Path"';

      final session = await FFmpegKit.execute(ffmpegCmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final mp3File = File(destinationMp3Path);
        final finalSize = await mp3File.length();

        item.status = DownloadStatus.completed;
        item.statusMessage = 'Saved as 320k MP3 to Downloads!';
        item.progress = 1.0;
        item.mp3FilePath = destinationMp3Path;
        item.fileSizeBytes = finalSize;
        onProgress(item);
      } else {
        // Fallback: If FFmpeg encoding returned an error, copy raw audio
        final fallbackPath = '${targetDirectory.path}/$safeTitle.m4a';
        await rawAudioFile.copy(fallbackPath);
        item.status = DownloadStatus.completed;
        item.statusMessage = 'Saved audio to Downloads';
        item.progress = 1.0;
        item.mp3FilePath = fallbackPath;
        onProgress(item);
      }
    } catch (e) {
      debugPrint('On-device download error: $e');
      item.status = DownloadStatus.error;
      item.statusMessage = 'Download failed';
      item.errorMessage = e.toString().replaceAll('Exception:', '').trim();
      onProgress(item);
    } finally {
      if (rawAudioFile != null && await rawAudioFile.exists()) {
        try {
          await rawAudioFile.delete();
        } catch (_) {}
      }
    }
  }

  void dispose() {}
}
