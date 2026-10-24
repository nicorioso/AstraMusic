class ScannedTrack {
  const ScannedTrack({
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.trackNumber,
    this.year,
    this.fileSize,
    this.dateAdded,
    this.dateModified,
    this.unchanged = false,
  });

  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? trackNumber;
  final int? year;
  final int? fileSize;
  final DateTime? dateAdded;
  final DateTime? dateModified;
  final bool unchanged;
}

class KnownFileStats {
  const KnownFileStats({required this.fileSize, required this.dateModified});

  final int? fileSize;
  final DateTime? dateModified;
}

sealed class ScanEvent {
  const ScanEvent();
}

final class ScanProgress extends ScanEvent {
  const ScanProgress({
    required this.foundCount,
    required this.errorCount,
    this.unchangedCount = 0,
  });

  final int foundCount;
  final int errorCount;
  final int unchangedCount;
}

final class ScanCompleted extends ScanEvent {
  const ScanCompleted({
    required this.tracks,
    required this.errorCount,
    this.unchangedCount = 0,
  });

  final List<ScannedTrack> tracks;
  final int errorCount;
  final int unchangedCount;
}

final class ScanCancelled extends ScanEvent {
  const ScanCancelled();
}

final class LibraryScanTask {
  LibraryScanTask(this.events, this._cancel);

  final Stream<ScanEvent> events;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

abstract interface class LibraryScanner {
  Future<LibraryScanTask> startScan({
    String? rootPath,
    Map<String, KnownFileStats> knownFiles = const {},
  });
}
