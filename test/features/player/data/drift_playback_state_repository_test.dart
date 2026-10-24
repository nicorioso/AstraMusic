import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/playback_state_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/data/drift_playback_state_repository.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftPlaybackStateRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPlaybackStateRepository(database);
    await database.batch((batch) {
      for (var index = 1; index <= 3; index++) {
        batch.insert(
          database.tracks,
          TracksCompanion.insert(
            id: Value(index),
            uri: 'file:///track-$index.mp3',
            title: 'Canción $index',
            dateAdded: DateTime(2026),
          ),
        );
      }
    });
  });

  tearDown(() => database.close());

  test('guarda y restaura ambos órdenes con aleatorio activo', () async {
    final tracks = await database.select(database.tracks).get();
    final domain = tracks.map((row) => _track(row)).toList();

    await repository.save(
      PlaybackStateSnapshot(
        queue: [domain[1], domain[0], domain[2]],
        originalQueue: domain,
        currentIndex: 1,
        position: const Duration(seconds: 37),
        shuffle: true,
        repeatMode: RepeatMode.all,
      ),
    );
    final restored = await repository.load();

    expect(restored, isNotNull);
    expect(restored!.queue.map((item) => item.track.id), [2, 1, 3]);
    expect(restored.queue.map((item) => item.originalPosition), [1, 0, 2]);
    expect(restored.currentIndex, 1);
    expect(restored.position, const Duration(seconds: 37));
    expect(restored.shuffle, isTrue);
    expect(restored.repeatMode, RepeatMode.all);
  });

  test('conserva la cola para validar disponibilidad al restaurar', () async {
    final rows = await database.select(database.tracks).get();
    final tracks = rows.map(_track).toList();
    await repository.save(
      PlaybackStateSnapshot(
        queue: tracks,
        originalQueue: tracks,
        currentIndex: 1,
        position: Duration.zero,
        shuffle: false,
        repeatMode: RepeatMode.off,
      ),
    );
    await (database.update(database.tracks)..where((row) => row.id.equals(2)))
        .write(const TracksCompanion(isAvailable: Value(false)));

    final restored = await repository.load();

    expect(restored!.queue.map((item) => item.track.id), [1, 2, 3]);
    expect(restored.currentIndex, 1);
    expect(restored.queue[restored.currentIndex!].track.id, 2);
    expect(restored.queue[restored.currentIndex!].track.isAvailable, isFalse);
  });
}

Track _track(TrackRow row) => Track(
  id: row.id,
  uri: row.uri,
  title: row.title,
  artist: row.artist,
  album: row.album,
  duration: row.durationMs == null
      ? null
      : Duration(milliseconds: row.durationMs!),
  dateAdded: row.dateAdded,
);
