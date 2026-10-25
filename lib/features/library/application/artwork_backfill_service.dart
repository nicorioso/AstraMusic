import 'dart:isolate';

import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';

typedef ArtworkExtractor = LocalAudioFileInfo Function(
  String filePath,
  String cacheDirectory,
);

final class ArtworkBackfillService {
  ArtworkBackfillService(
    this._repository, {
    required this.cacheDirectory,
    this.extractor = readLocalAudioFileWithArtwork,
    this.batchSize = 4,
    this.useIsolate = true,
  });

  final TrackRepository _repository;
  final Future<String> Function() cacheDirectory;
  final ArtworkExtractor extractor;
  final int batchSize;
  final bool useIsolate;
  bool _started = false;

  Future<void> runOnce() async {
    if (_started) return;
    _started = true;
    try {
      final tracks = await _repository.watchAll().first;
      final pending = tracks
          .where(
            (track) =>
                track.artworkPath == null &&
                localFilePathFromLocation(track.uri) != null,
          )
          .toList(growable: false);
      if (pending.isEmpty) return;
      final cache = await cacheDirectory();
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
    } on Object {
      // El relleno es oportunista y nunca debe impedir abrir la biblioteca.
    }
  }
}
