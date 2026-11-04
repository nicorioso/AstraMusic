import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/drift_smart_playlist_repository.dart';
import 'package:astramusic/features/library/domain/smart_playlist_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'registra cada inicio y actualiza las cuatro listas reactivas',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftSmartPlaylistRepository(
        database,
        now: () => DateTime(2026, 1, 10),
      );
      for (var id = 1; id <= 3; id++) {
        await database
            .into(database.tracks)
            .insert(
              TracksCompanion.insert(
                uri: 'file:///$id.mp3',
                title: 'Pista $id',
                dateAdded: DateTime(2026, 1, id),
              ),
            );
      }
      expect(
        (await repository.watch(SmartPlaylist.neverPlayed).first).map(
          (track) => track.id,
        ),
        [3, 2, 1],
      );
      await repository.recordPlay(1);
      await repository.recordPlay(2);
      await repository.recordPlay(1);
      expect(
        (await repository.watch(SmartPlaylist.mostPlayed).first).map(
          (track) => track.id,
        ),
        [1, 2],
      );
      expect(
        (await repository.watch(SmartPlaylist.recentlyPlayed).first).map(
          (track) => track.id,
        ),
        [1, 2],
      );
      expect(
        (await repository.watch(SmartPlaylist.neverPlayed).first).map(
          (track) => track.id,
        ),
        [3],
      );
      expect(
        (await repository.watch(SmartPlaylist.recentlyAdded).first).map(
          (track) => track.id,
        ),
        [3, 2, 1],
      );
      expect((await database.select(database.playHistory).get()).length, 3);
      expect(
        (await (database.select(
          database.tracks,
        )..where((row) => row.id.equals(1))).getSingle()).playCount,
        2,
      );
      await repository.recordPlay(999);
      expect((await database.select(database.playHistory).get()).length, 3);
    },
  );
}
