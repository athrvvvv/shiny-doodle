class DeviceAudioItem {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String path;
  final int sizeBytes;
  final int dateAdded;

  DeviceAudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.path,
    required this.sizeBytes,
    required this.dateAdded,
  });

  factory DeviceAudioItem.fromMap(Map<dynamic, dynamic> map) {
    final rawArtist = map['artist']?.toString();
    final cleanArtist = (rawArtist == null ||
            rawArtist == '<unknown>' ||
            rawArtist.trim().isEmpty)
        ? 'Unknown Artist'
        : rawArtist;

    return DeviceAudioItem(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id'].toString()) ?? 0,
      title: map['title']?.toString() ?? 'Unknown Song',
      artist: cleanArtist,
      album: map['album']?.toString() ?? '',
      durationMs: map['durationMs'] is int
          ? map['durationMs']
          : int.tryParse(map['durationMs']?.toString() ?? '0') ?? 0,
      path: map['path']?.toString() ?? '',
      sizeBytes: map['sizeBytes'] is int
          ? map['sizeBytes']
          : int.tryParse(map['sizeBytes']?.toString() ?? '0') ?? 0,
      dateAdded: map['dateAdded'] is int
          ? map['dateAdded']
          : int.tryParse(map['dateAdded']?.toString() ?? '0') ?? 0,
    );
  }

  String get formattedDuration {
    if (durationMs <= 0) return '';
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (sizeBytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num = sizeBytes / (1 << (i * 10));
    return '${num.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get fileExtension {
    final idx = path.lastIndexOf('.');
    if (idx != -1 && idx < path.length - 1) {
      return path.substring(idx + 1).toUpperCase();
    }
    return 'MP3';
  }
}
