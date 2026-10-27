import 'dart:isolate';

import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';

typedef ArtworkExtractor = LocalAudioFileInfo Function(
  String filePath,
  String cacheDirectory,
);

abstract interface class ArtworkBackfill {
  Future<void> runOnce();
}

final class ArtworkBackfillService implements ArtworkBackfill {
  ArtworkBackfillService(
    this._repository, {
    required this.cacheDirectory,
    this.extractor = readLocalAudioFileWithArtwork,
    this.batchSize = 4,
    this.pageSize = 100,
    this.useIsolate = true,
  });

  final TrackRepository _repository;
  final Future<String> Function() cacheDirectory;
  final ArtworkExtractor extractor;
  final int batchSize;
  final int pageSize;
  final bool useIsolate;
  bool _started = false;

  @override
  Future<void> runOnce() async {
    if (_started) return;
    _started = true;
    try {
      final cache = await cacheDirectory();
      var offset = 0;
      while (true) {
        final page = _repository is PaginatedTrackRepository
            ? await _repository.watchPage(limit: pageSize, offset: offset).first
            : await _repository.watchAll().first;
        if (page.isEmpty) break;
        final pending = page
            .where(
              (track) =>
                  track.artworkPath == null &&
                  localFilePathFromLocation(track.uri) != null,
            )
            .toList(growable: false);
        for (var start = 0; start < pending.length; start += batchSize) {
          final end = (start + batchSize).clamp(0, pending.length);
          final updates = <Track>[];
          for (final track in pending.sublist(start, end)) {
            final filePath = localFilePathFromLocation(track.uri)!;
            try {
              final info = useIsolate
                  ? await Isolate.run(() => extractor(filePath, cache))
                  : extractor(filePath, cache);
              final artworkPath = info.artworkPath;
              if (artworkPath != null) {
                updates.add(track.withArtworkPath(artworkPath));
              }
            } on Object {
              // Un archivo ausente o ilegible no detiene el relleno del lote.
            }
          }
          if (updates.isNotEmpty) await _repository.upsertAll(updates);
          await Future<void>.delayed(Duration.zero);
        }
        if (_repository is! PaginatedTrackRepository ||
            page.length < pageSize) {
          break;
        }
        offset += page.length;
      }
    } on Object {
      // El relleno es oportunista y nunca debe impedir abrir la biblioteca.
    }
  }
}
