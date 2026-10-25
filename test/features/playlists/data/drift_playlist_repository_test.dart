import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/playlists/data/drift_playlist_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftPlaylistRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPlaylistRepository(
      database,
      now: () => DateTime.utc(2026, 1, 2),
    );
    await database.batch((batch) {
      for (var id = 1; id <= 6; id++) {
        batch.insert(
          database.tracks,
          TracksCompanion.insert(
            id: Value(id),
            uri: 'file:///track-$id.mp3',
            title: 'Canción $id',
            artist: Value(id <= 2 ? 'Compartido' : 'Artista $id'),
            album: Value(id <= 2 ? 'Álbum' : 'Álbum $id'),
            artworkPath: Value(
              id <= 2 ? '/cover/shared.jpg' : '/cover/$id.jpg',
            ),
            dateAdded: DateTime.utc(2026),
          ),
        );
      }
    });
  });

  tearDown(() => database.close());

  test('crea, renombra y rechaza nombres vacíos', () async {
    final created = await repository.create('  Viaje  ');
    expect(created.name, 'Viaje');
    expect(created.trackCount, 0);

    await repository.rename(created.id, '  Ruta  ');
    expect((await repository.watchById(created.id).first)!.name, 'Ruta');
    await expectLater(repository.create('   '), throwsArgumentError);
  });

  test('añade al final, omite duplicados y actualiza el conteo', () async {
    final playlist = await repository.create('Lista');
    final first = await repository.addTracks(playlist.id, [1, 2, 1]);
    final second = await repository.addTracks(playlist.id, [2, 3]);

    expect((first.added, first.alreadyPresent), (2, 1));
    expect((second.added, second.alreadyPresent), (1, 1));
    expect(
      (await repository.watchTracks(playlist.id).first).map(
        (track) => track.id,
      ),
      [1, 2, 3],
    );
    expect((await repository.watchById(playlist.id).first)!.trackCount, 3);
    final rows = await (database.select(
      database.playlistTracks,
    )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
    expect(rows.map((row) => row.position), [0, 1, 2]);
  });

  test('quitar renumera posiciones contiguas', () async {
    final playlist = await repository.create('Lista');
    await repository.addTracks(playlist.id, [1, 2, 3]);

    await repository.removeTrack(playlist.id, 2);

    final rows = await (database.select(
      database.playlistTracks,
    )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
    expect(rows.map((row) => row.trackId), [1, 3]);
    expect(rows.map((row) => row.position), [0, 1]);
  });

  for (final scenario in <(String, int, int, List<int>)>[
    ('hacia arriba', 2, 1, [1, 3, 2]),
    ('hacia abajo', 0, 1, [2, 1, 3]),
    ('entre extremos', 2, 0, [3, 1, 2]),
    ('al extremo final', 0, 2, [2, 3, 1]),
  ]) {
    test('mueve ${scenario.$1} y conserva posiciones contiguas', () async {
      final playlist = await repository.create('Lista');
      await repository.addTracks(playlist.id, [1, 2, 3]);
      await repository.move(playlist.id, scenario.$2, scenario.$3);

      final rows = await (database.select(
        database.playlistTracks,
      )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
      expect(rows.map((row) => row.trackId), scenario.$4);
      expect(rows.map((row) => row.position), [0, 1, 2]);
    });
  }

  test('eliminar hace cascade sin borrar canciones', () async {
    final playlist = await repository.create('Lista');
    await repository.addTracks(playlist.id, [1, 2]);

    await repository.delete(playlist.id);

    expect(await database.select(database.playlistTracks).get(), isEmpty);
    expect(await database.select(database.tracks).get(), hasLength(6));
    expect(await repository.watchAll().first, isEmpty);
  });

  test(
    'markPlayed y watchRecent ordenan y excluyen nunca reproducidas',
    () async {
      var now = DateTime.utc(2026, 1, 1);
      repository = DriftPlaylistRepository(database, now: () => now);
      final first = await repository.create('Primera');
      final second = await repository.create('Segunda');
      await repository.create('Nunca');
      await repository.markPlayed(first.id);
      now = now.add(const Duration(minutes: 1));
      await repository.markPlayed(second.id);

      final recent = await repository.watchRecent(2).first;
      expect(recent.map((playlist) => playlist.name), ['Segunda', 'Primera']);
      expect(recent.every((playlist) => playlist.lastPlayedAt != null), isTrue);
    },
  );

  test('coverTracks devuelve máximo cuatro carátulas distintas', () async {
    final playlist = await repository.create('Portadas');
    await repository.addTracks(playlist.id, [1, 2, 3, 4, 5, 6]);

    final covers = await repository.coverTracks(playlist.id);

    expect(covers.map((track) => track.id), [1, 3, 4, 5]);
    expect(covers, hasLength(4));
  });
}
