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
}

sealed class ScanEvent {
  const ScanEvent();
}

final class ScanProgress extends ScanEvent {
  const ScanProgress({required this.foundCount, required this.errorCount});

  final int foundCount;
  final int errorCount;
}

final class ScanCompleted extends ScanEvent {
  const ScanCompleted({required this.tracks, required this.errorCount});

  final List<ScannedTrack> tracks;
  final int errorCount;
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
  Future<LibraryScanTask> startScan({String? rootPath});
}
