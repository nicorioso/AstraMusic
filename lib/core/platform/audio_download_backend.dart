/// Contrato independiente del motor y de la interfaz de descargas.
abstract class AudioDownloadBackend {
  Future<DownloadAvailability> checkAvailability();
  Future<SourcePreview> analyzeUrl(String url);
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
  });
  final String id;
  final String temporaryPath;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;
}

class DownloadBatchResult {
  DownloadBatchResult({
    required List<DownloadedAudio> successes,
    required Map<String, String> errors,
    required this.canceled,
  }) : successes = List.unmodifiable(successes),
       errors = Map.unmodifiable(errors);
  final List<DownloadedAudio> successes;
  final Map<String, String> errors;
  final bool canceled;
}
