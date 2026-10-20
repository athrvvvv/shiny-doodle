enum DownloadStatus {
  idle,
  fetchingInfo,
  downloading,
  converting,
  completed,
  error,
}

class DownloadItem {
  final String id;
  final String url;
  String title;
  String author;
  String? duration;
  String? thumbnailUrl;
  double progress; // 0.0 to 1.0
  String statusMessage;
  DownloadStatus status;
  String? mp3FilePath;
  int? fileSizeBytes;
  String? errorMessage;
  DateTime timestamp;

  DownloadItem({
    required this.id,
    required this.url,
    this.title = 'Fetching details...',
    this.author = '',
    this.duration,
    this.thumbnailUrl,
    this.progress = 0.0,
    this.statusMessage = 'Connecting to YouTube...',
    this.status = DownloadStatus.fetchingInfo,
    this.mp3FilePath,
    this.fileSizeBytes,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
