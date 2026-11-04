import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:path/path.dart' as path;

const librarySyncBatchSize = 500;

sealed class LibraryScanScope {
  const LibraryScanScope();
}

final class DesktopFolderScanScope extends LibraryScanScope {
  const DesktopFolderScanScope(this.rootPath);

  final String rootPath;
}

final class AndroidMediaStoreScanScope extends LibraryScanScope {
  const AndroidMediaStoreScanScope();
}

class LibrarySyncSummary {
  const LibrarySyncSummary({
    this.newCount = 0,
    this.updatedCount = 0,
    this.unchangedCount = 0,
    this.unavailableCount = 0,
    this.errorCount = 0,
  });

  final int newCount;
  final int updatedCount;
  final int unchangedCount;
  final int unavailableCount;
  final int errorCount;

  LibrarySyncSummary operator +(LibrarySyncSummary other) => LibrarySyncSummary(
    newCount: newCount + other.newCount,
    updatedCount: updatedCount + other.updatedCount,
    unchangedCount: unchangedCount + other.unchangedCount,
    unavailableCount: unavailableCount + other.unavailableCount,
    errorCount: errorCount + other.errorCount,
  );

  String get message =>
      '$newCount nuevas, $updatedCount actualizadas, '
      '$unchangedCount sin cambios, $unavailableCount no disponibles, '
      '$errorCount errores.';
}

final class LibrarySyncService {
  const LibrarySyncService(this._tracks);

  final TrackRepository _tracks;

  Future<LibrarySyncSummary> synchronize({
    required List<ScannedTrack> scannedTracks,
    required LibraryScanScope scope,
    int scanErrorCount = 0,
  }) async {
    final session = await startIncremental(scope: scope);
    await session.addBatch(scannedTracks);
    return session.finish(scanErrorCount: scanErrorCount);
  }

  Future<LibrarySyncSession> startIncremental({
    required LibraryScanScope scope,
  }) async {
    return LibrarySyncSession._(_tracks, scope);
  }

  Future<void> deleteFolderTracks(String rootPath) async {
    var lastId = 0;
    while (true) {
      final page = await _readPageAfterId(_tracks, lastId);
      if (page.isEmpty) break;
      lastId = page.last.id!;
      await _tracks.deleteByUris({
        for (final track in page)
          if (_belongsToScope(track.uri, DesktopFolderScanScope(rootPath)))
            track.uri,
      });
    }
  }

  static bool _belongsToScope(String uriValue, LibraryScanScope scope) {
    return switch (scope) {
      DesktopFolderScanScope(:final rootPath) => _isInsideFolder(
        uriValue,
        rootPath,
      ),
      AndroidMediaStoreScanScope() => _isMediaStoreAudioUri(uriValue),
    };
  }

  static bool _isInsideFolder(String uriValue, String rootPath) {
    String filePath;
    if (path.isAbsolute(uriValue)) {
      filePath = uriValue;
    } else {
      final uri = Uri.tryParse(uriValue);
      if (uri != null && uri.hasScheme && uri.scheme != 'file') return false;
      try {
        filePath = uri != null && uri.scheme == 'file'
            ? uri.toFilePath()
            : uriValue;
      } on UnsupportedError {
        return false;
      }
    }

    final normalizedRoot = path.normalize(path.absolute(rootPath));
    final normalizedFile = path.normalize(path.absolute(filePath));
    return path.equals(normalizedRoot, normalizedFile) ||
        path.isWithin(normalizedRoot, normalizedFile);
  }

  static bool _isMediaStoreAudioUri(String uriValue) {
    final uri = Uri.tryParse(uriValue);
    if (uri == null || uri.scheme != 'content' || uri.authority != 'media') {
      return false;
    }
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[1] == 'audio' &&
        segments[2] == 'media';
  }
}

final class LibrarySyncSession {
  LibrarySyncSession._(this._tracks, this._scope);

  final TrackRepository _tracks;
  final LibraryScanScope _scope;
  final Set<String> _scannedUris = {};
  var _summary = const LibrarySyncSummary();
  var _finished = false;

  Future<void> addBatch(List<ScannedTrack> scannedTracks) async {
    if (_finished) throw StateError('La sincronización ya terminó.');
    for (
      var start = 0;
      start < scannedTracks.length;
      start += librarySyncBatchSize
    ) {
      final end = (start + librarySyncBatchSize).clamp(0, scannedTracks.length);
      await _addPage(scannedTracks.sublist(start, end));
    }
  }

  Future<void> _addPage(List<ScannedTrack> page) async {
    final uniqueScanned = {for (final scanned in page) scanned.uri: scanned};
    final uris = uniqueScanned.keys.toSet();
    final excluded = await _excludedAmong(_tracks, uris);
    final existing = await _findByUris(_tracks, uris);
    final existingByUri = {for (final track in existing) track.uri: track};
    final now = DateTime.now();
    var newCount = 0;
    var updatedCount = 0;
    var unchangedCount = 0;

    final upserts = <Track>[];
    for (final scanned in uniqueScanned.values) {
      if (excluded.contains(scanned.uri)) continue;
      final old = existingByUri[scanned.uri];
      final preserveMetadata = scanned.unchanged && old != null;
      final track = Track(
        id: old?.id,
        uri: scanned.uri,
        title: preserveMetadata ? old.title : scanned.title,
        artist: preserveMetadata ? old.artist : scanned.artist,
        album: preserveMetadata ? old.album : scanned.album,
        genre: preserveMetadata ? old.genre : scanned.genre,
        folderPath: switch (_scope) {
          DesktopFolderScanScope(:final rootPath) => rootPath,
          AndroidMediaStoreScanScope() => null,
        },
        duration: preserveMetadata
            ? old.duration
            : scanned.durationMs == null
            ? null
            : Duration(milliseconds: scanned.durationMs!),
        trackNumber: preserveMetadata ? old.trackNumber : scanned.trackNumber,
        year: preserveMetadata ? old.year : scanned.year,
        fileSize: scanned.fileSize,
        dateAdded: old?.dateAdded ?? scanned.dateAdded ?? now,
        dateModified: scanned.dateModified ?? old?.dateModified,
        isAvailable: true,
        favoritedAt: old?.favoritedAt,
        artworkPath: preserveMetadata ? old.artworkPath : scanned.artworkPath,
      );
      upserts.add(track);
      _scannedUris.add(scanned.uri);

      if (old == null) {
        newCount++;
      } else if (!_sameTrackData(old, track)) {
        updatedCount++;
      }
      if (scanned.unchanged) unchangedCount++;
    }

    await _tracks.upsertAll(upserts);

    _summary += LibrarySyncSummary(
      newCount: newCount,
      updatedCount: updatedCount,
      unchangedCount: unchangedCount,
    );
  }

  Future<LibrarySyncSummary> finish({int scanErrorCount = 0}) async {
    if (_finished) throw StateError('La sincronización ya terminó.');
    _finished = true;
    var unavailableCount = 0;
    var lastId = 0;
    while (true) {
      final page = await _readPageAfterId(_tracks, lastId);
      if (page.isEmpty) break;
      lastId = page.last.id!;
      final unavailableUris = {
        for (final track in page)
          if (track.isAvailable &&
              LibrarySyncService._belongsToScope(track.uri, _scope) &&
              !_scannedUris.contains(track.uri))
            track.uri,
      };
      await _tracks.markUnavailable(unavailableUris);
      unavailableCount += unavailableUris.length;
    }

    return _summary +
        LibrarySyncSummary(
          unavailableCount: unavailableCount,
          errorCount: scanErrorCount,
        );
  }

  bool _sameTrackData(Track old, Track current) =>
      old.title == current.title &&
      old.artist == current.artist &&
      old.album == current.album &&
      old.duration == current.duration &&
      old.trackNumber == current.trackNumber &&
      old.year == current.year &&
      old.fileSize == current.fileSize &&
      old.dateAdded == current.dateAdded &&
      old.dateModified == current.dateModified &&
      old.isAvailable == current.isAvailable &&
      old.isFavorite == current.isFavorite &&
      old.artworkPath == current.artworkPath;
}

Future<List<Track>> _findByUris(
  TrackRepository tracks,
  Set<String> uris,
) async {
  if (tracks is SyncTrackRepository) return tracks.findByUris(uris);
  return (await tracks.watchAll().first)
      .where((track) => uris.contains(track.uri))
      .toList();
}

Future<List<Track>> _readPageAfterId(TrackRepository tracks, int id) async {
  if (tracks is SyncTrackRepository) {
    return tracks.readPageAfterId(id, librarySyncBatchSize);
  }
  return (await tracks.watchAll().first)
      .where((track) => (track.id ?? 0) > id)
      .take(librarySyncBatchSize)
      .toList();
}

Future<Set<String>> _excludedAmong(
  TrackRepository tracks,
  Set<String> uris,
) async {
  if (tracks is SyncTrackRepository) return tracks.excludedAmong(uris);
  return (await tracks.excludedUris()).intersection(uris);
}
