/// Contrato independiente del motor y de la interfaz de descargas.
abstract class AudioDownloadBackend {
  Future<DownloadAvailability> checkAvailability();
  Future<SourcePreview> analyzeUrl(String url);
  Future<PlaylistPreview> analyzePlaylist(String url);
  Stream<DownloadEvent> downloadAudio(DownloadRequest request);
  Future<void> cancel();
}

class DownloadAvailability {
  const DownloadAvailability({
    required this.available,
    this.ytDlpVersion,
    this.ffmpegVersion,
    this.error,
  });
  final bool available;
  final String? ytDlpVersion;
  final String? ffmpegVersion;
  final String? error;
}

enum SourceType { video, playlist }

class PlaylistEntry {
  const PlaylistEntry({required this.id, required this.title, this.duration});
  final String id;
  final String title;
  final Duration? duration;
  String get url => 'https://www.youtube.com/watch?v=$id';
}

class PlaylistPreview {
  PlaylistPreview({
    required this.id,
    required this.title,
    required this.author,
    required List<PlaylistEntry> entries,
    this.thumbnailUrl,
    this.truncated = false,
  }) : entries = List.unmodifiable(entries);

  final String id;
  final String title;
  final String author;
  final String? thumbnailUrl;
  final List<PlaylistEntry> entries;
  final bool truncated;
}

class SourcePreview {
  const SourcePreview({
    required this.id,
    required this.title,
    required this.author,
    required this.type,
    this.duration,
    this.thumbnailUrl,
  });
  final String id;
  final String title;
  final String author;
  final SourceType type;
  final Duration? duration;
  final String? thumbnailUrl;
}

enum AudioDownloadFormat { mp3 }

class DownloadRequest {
  const DownloadRequest({
    required this.url,
    required this.temporaryDirectory,
    this.format = AudioDownloadFormat.mp3,
  });
  final String url;
  final String temporaryDirectory;
  final AudioDownloadFormat format;
}

enum DownloadStatus {
  analyzing,
  downloading,
  processing,
  registering,
  completed,
  failed,
  canceled,
}

class DownloadEvent {
  const DownloadEvent({
    required this.status,
    this.downloadedBytes,
    this.totalBytes,
    this.error,
    this.audio,
  });
  final DownloadStatus status;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? error;
  final DownloadedAudio? audio;
}

class DownloadedAudio {
  const DownloadedAudio({
    required this.id,
    required this.temporaryPath,
    required this.title,
    this.author,
    this.duration,
    this.thumbnailUrl,
    this.thumbnailPath,
  });
  final String id;
  final String temporaryPath;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;

  /// Imagen auxiliar dentro de la carpeta temporal del trabajo.
  final String? thumbnailPath;
}

class DownloadBatchItem {
  const DownloadBatchItem({
    required this.sourceId,
    required this.title,
    required this.trackId,
    required this.alreadyPresent,
  });
  final String sourceId;
  final String title;
  final int trackId;
  final bool alreadyPresent;
}

class DownloadBatchResult {
  DownloadBatchResult({
    required List<DownloadBatchItem> successes,
    required Map<String, String> errors,
    required this.canceled,
    this.playlistId,
  }) : successes = List.unmodifiable(successes),
       errors = Map.unmodifiable(errors);
  final List<DownloadBatchItem> successes;
  final Map<String, String> errors;
  final bool canceled;
  final int? playlistId;
  int get addedCount => successes.where((item) => !item.alreadyPresent).length;
  int get existingCount =>
      successes.where((item) => item.alreadyPresent).length;
}
