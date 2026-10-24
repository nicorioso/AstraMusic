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
    final existing = await _tracks.watchAll().first;
    final excluded = await _tracks.excludedUris();
    final existingByUri = {for (final track in existing) track.uri: track};
    final uniqueScanned = {
      for (final scanned in scannedTracks)
        if (!excluded.contains(scanned.uri)) scanned.uri: scanned,
    };
    final now = DateTime.now();
    var newCount = 0;
    var updatedCount = 0;

    final upserts = <Track>[];
    for (final scanned in uniqueScanned.values) {
      final old = existingByUri[scanned.uri];
      final preserveMetadata = scanned.unchanged && old != null;
      final track = Track(
        id: old?.id,
        uri: scanned.uri,
        title: preserveMetadata ? old.title : scanned.title,
        artist: preserveMetadata ? old.artist : scanned.artist,
        album: preserveMetadata ? old.album : scanned.album,
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
        isFavorite: old?.isFavorite ?? false,
        artworkPath: preserveMetadata ? old.artworkPath : scanned.artworkPath,
      );
      upserts.add(track);

      if (old == null) {
        newCount++;
      } else if (!_sameTrackData(old, track)) {
        updatedCount++;
      }
    }

    for (var start = 0; start < upserts.length; start += librarySyncBatchSize) {
      final end = (start + librarySyncBatchSize).clamp(0, upserts.length);
      await _tracks.upsertAll(upserts.sublist(start, end));
    }

    final scannedUris = uniqueScanned.keys.toSet();
    final unavailableUris = existing
        .where(
          (track) => track.isAvailable && _belongsToScope(track.uri, scope),
        )
        .map((track) => track.uri)
        .where((uri) => !scannedUris.contains(uri))
        .toSet();
    await _tracks.markUnavailable(unavailableUris);

    return LibrarySyncSummary(
      newCount: newCount,
      updatedCount: updatedCount,
      unchangedCount: uniqueScanned.values
          .where((track) => track.unchanged)
          .length,
      unavailableCount: unavailableUris.length,
      errorCount: scanErrorCount,
    );
  }

  Future<void> deleteFolderTracks(String rootPath) async {
    final tracks = await _tracks.watchAll().first;
    final uris = tracks
        .where(
          (track) =>
              _belongsToScope(track.uri, DesktopFolderScanScope(rootPath)),
        )
        .map((track) => track.uri)
        .toSet();
    await _tracks.deleteByUris(uris);
  }

  bool _belongsToScope(String uriValue, LibraryScanScope scope) {
    return switch (scope) {
      DesktopFolderScanScope(:final rootPath) => _isInsideFolder(
        uriValue,
        rootPath,
      ),
      AndroidMediaStoreScanScope() => _isMediaStoreAudioUri(uriValue),
    };
  }

  bool _isInsideFolder(String uriValue, String rootPath) {
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

  bool _isMediaStoreAudioUri(String uriValue) {
    final uri = Uri.tryParse(uriValue);
    if (uri == null || uri.scheme != 'content' || uri.authority != 'media') {
      return false;
    }
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[1] == 'audio' &&
        segments[2] == 'media';
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
