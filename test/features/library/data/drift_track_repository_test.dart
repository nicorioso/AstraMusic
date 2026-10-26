import 'dart:async';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_list_query.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTrackRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTrackRepository(database);
  });

  tearDown(() => database.close());

  test('upsertAll mantiene una sola fila por uri', () async {
    await repository.upsertAll([_track(uri: 'file:///uno.mp3', title: 'Uno')]);
    await repository.upsertAll([
      _track(uri: 'file:///uno.mp3', title: 'Uno actualizado'),
    ]);

    expect(await repository.count(), 1);
    final stored = await repository.watchAll().first;
    expect(stored.single.title, 'Uno actualizado');
  });

  test(
    'watchSearch busca por título, artista y álbum sin mayúsculas',
    () async {
      await repository.upsertAll([
        _track(uri: 'file:///titulo.mp3', title: 'Aurora Boreal'),
        _track(
          uri: 'file:///artista.mp3',
          title: 'Otra canción',
          artist: 'Los Viajeros',
        ),
        _track(
          uri: 'file:///album.mp3',
          title: 'Última canción',
          album: 'Noches Largas',
        ),
      ]);

      expect(
        (await repository.watchSearch('AURORA').first).single.uri,
        'file:///titulo.mp3',
      );
      expect(
        (await repository.watchSearch('VIAJEROS').first).single.uri,
        'file:///artista.mp3',
      );
      expect(
        (await repository.watchSearch('NOCHES').first).single.uri,
        'file:///album.mp3',
      );
    },
  );

  test(
    'watchSearch trata porcentaje y guion bajo como texto literal',
    () async {
      await repository.upsertAll([
        _track(uri: 'file:///porcentaje.mp3', title: 'Mezcla 100% real'),
        _track(uri: 'file:///guion.mp3', title: 'Tema_A'),
        _track(uri: 'file:///parecido.mp3', title: 'TemaXA'),
      ]);

      expect(
        (await repository.watchSearch('%').first).map((track) => track.uri),
        ['file:///porcentaje.mp3'],
      );
      expect(
        (await repository.watchSearch('_').first).map((track) => track.uri),
        ['file:///guion.mp3'],
      );
    },
  );

  test('watchSearch compara mayúsculas Unicode', () async {
    await repository.upsertAll([
      _track(uri: 'file:///unicode.mp3', title: 'ÉXITO 東京'),
    ]);

    expect(
      (await repository.watchSearch('éxito 東京').first).single.uri,
      'file:///unicode.mp3',
    );
  });

  test('watchSearch encuentra títulos sin escribir sus acentos', () async {
    await repository.upsertAll([
      _track(uri: 'file:///cancion.mp3', title: 'Canción de la Niña'),
    ]);

    expect(
      (await repository.watchSearch('cancion').first).single.uri,
      'file:///cancion.mp3',
    );
    expect(
      (await repository.watchSearch('nina').first).single.uri,
      'file:///cancion.mp3',
    );
  });

  test(
    'watchAll ordena por el título normalizado y desempata por id',
    () async {
      await repository.upsertAll([
        _track(uri: 'file:///exito.mp3', title: 'Éxito'),
        _track(uri: 'file:///avion.mp3', title: 'avión'),
        _track(uri: 'file:///arbol.mp3', title: 'Árbol'),
        _track(uri: 'file:///arbol-2.mp3', title: 'árbol'),
      ]);

      expect((await repository.watchAll().first).map((track) => track.uri), [
        'file:///arbol.mp3',
        'file:///arbol-2.mp3',
        'file:///avion.mp3',
        'file:///exito.mp3',
      ]);
    },
  );

  test('watchPage aplica ventana, desplazamiento y búsqueda', () async {
    await repository.upsertAll([
      _track(uri: 'file:///delta.mp3', title: 'Delta', artist: 'Grupo'),
      _track(uri: 'file:///alfa.mp3', title: 'Alfa', artist: 'Grupo'),
      _track(uri: 'file:///charlie.mp3', title: 'Charlie'),
      _track(uri: 'file:///bravo.mp3', title: 'Bravo', artist: 'Grupo'),
    ]);

    expect(
      (await repository.watchPage(limit: 2, offset: 1).first).map(
        (track) => track.title,
      ),
      ['Bravo', 'Charlie'],
    );
    expect(
      (await repository.watchPage(limit: 2, offset: 1, query: 'grupo').first)
          .map((track) => track.title),
      ['Bravo', 'Delta'],
    );
  });

  test('watchFilteredPage combina favoritos, disponibilidad y orden', () async {
    await repository.upsertAll([
      _track(uri: 'file:///uno.mp3', title: 'Uno', artist: 'Zulu', duration: const Duration(minutes: 1)),
      _track(uri: 'file:///dos.mp3', title: 'Dos', artist: 'Alfa', duration: const Duration(minutes: 3), isAvailable: false),
      _track(uri: 'file:///tres.mp3', title: 'Tres', artist: 'Beta', duration: const Duration(minutes: 2)),
    ]);
    final items = await repository.watchAll().first;
    for (final item in items) {
      await repository.setFavorite(item.id!, true);
    }
    expect(
      (await repository.watchFilteredPage(limit: 10, query: const TrackListQuery(favoritesOnly: true, availableOnly: true, sort: TrackSort.duration)).first).map((track) => track.title),
      ['Tres', 'Uno'],
    );
  });

  test('markUnavailable cambia la disponibilidad', () async {
    await repository.upsertAll([
      _track(uri: 'file:///ausente.mp3', title: 'Ausente'),
    ]);
    final id = (await repository.watchAll().first).single.id!;

    await repository.markUnavailable({'file:///ausente.mp3'});

    expect((await repository.getById(id))?.isAvailable, isFalse);
  });

  test('setFavorite ordena por fecha y quitar elimina de favoritos', () async {
    var now = DateTime.utc(2026, 1, 1);
    repository = DriftTrackRepository(database, now: () => now);
    await repository.upsertAll([
      _track(uri: 'file:///uno.mp3', title: 'Uno'),
      _track(uri: 'file:///dos.mp3', title: 'Dos'),
    ]);
    final tracks = await repository.watchAll().first;
    await repository.setFavorite(tracks.first.id!, true);
    now = now.add(const Duration(minutes: 1));
    await repository.setFavorite(tracks.last.id!, true);

    var favorites = await repository.watchFavorites().first;
    expect(favorites.map((track) => track.title), ['Uno', 'Dos']);
    expect(favorites.every((track) => track.isFavorite), isTrue);

    await repository.setFavorite(tracks.last.id!, false);
    favorites = await repository.watchFavorites().first;
    expect(favorites.map((track) => track.title), ['Dos']);
    expect((await repository.getById(tracks.last.id!))!.favoritedAt, null);
  });

  test('borrar una canción elimina sus relaciones por cascade', () async {
    await repository.upsertAll([
      _track(uri: 'file:///relacionada.mp3', title: 'Relacionada'),
    ]);
    final trackId = (await repository.watchAll().first).single.id!;
    final now = DateTime.now();
    final playlistId = await database
        .into(database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: 'Prueba',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.playlistTracks)
        .insert(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: 0,
            addedAt: now,
          ),
        );
    await database
        .into(database.queueItems)
        .insert(
          QueueItemsCompanion.insert(
            position: const Value(0),
            trackId: trackId,
          ),
        );

    await repository.excludeAndDelete(
      (await repository.watchAll().first).single,
    );

    final relations = await database.select(database.playlistTracks).get();
    final queue = await database.select(database.queueItems).get();
    expect(relations, isEmpty);
    expect(queue, isEmpty);
    expect(await repository.excludedUris(), {'file:///relacionada.mp3'});
  });

  test('watchAll emite de nuevo al insertar', () async {
    final initialEmission = Completer<void>();
    final insertedEmission = Completer<void>();
    final subscription = repository.watchAll().listen((tracks) {
      if (tracks.isEmpty && !initialEmission.isCompleted) {
        initialEmission.complete();
      }
      if (tracks.length == 1 && !insertedEmission.isCompleted) {
        insertedEmission.complete();
      }
    });
    addTearDown(subscription.cancel);

    await initialEmission.future;
    await repository.upsertAll([
      _track(uri: 'file:///reactiva.mp3', title: 'Reactiva'),
    ]);

    await expectLater(
      insertedEmission.future.timeout(const Duration(seconds: 2)),
      completes,
    );
  });

  test('clearLibrary vacía todas las tablas relacionadas', () async {
    await repository.upsertAll([
      _track(uri: 'file:///todo.mp3', title: 'Todo'),
    ]);
    final track = (await repository.watchAll().first).single;
    final now = DateTime(2026);
    final playlistId = await database
        .into(database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: 'Lista',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.playlistTracks)
        .insert(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: track.id!,
            position: 0,
            addedAt: now,
          ),
        );
    await database
        .into(database.queueItems)
        .insert(
          QueueItemsCompanion.insert(
            position: const Value(0),
            trackId: track.id!,
          ),
        );
    await database
        .into(database.playbackState)
        .insert(PlaybackStateCompanion.insert(updatedAt: now));
    await database
        .into(database.libraryFolders)
        .insert(LibraryFoldersCompanion.insert(path: '/música', addedAt: now));
    await database
        .into(database.excludedUris)
        .insert(ExcludedUrisCompanion.insert(uri: 'file:///excluida.mp3'));

    await repository.clearLibrary();

    expect(await database.select(database.tracks).get(), isEmpty);
    expect(await database.select(database.playlists).get(), isEmpty);
    expect(await database.select(database.playlistTracks).get(), isEmpty);
    expect(await database.select(database.queueItems).get(), isEmpty);
    expect(await database.select(database.playbackState).get(), isEmpty);
    expect(await database.select(database.libraryFolders).get(), isEmpty);
    expect(await database.select(database.excludedUris).get(), isEmpty);
  });
}

Track _track({
  required String uri,
  required String title,
  String? artist,
  String? album,
  Duration? duration,
  bool isAvailable = true,
}) {
  return Track(
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    isAvailable: isAvailable,
    dateAdded: DateTime(2026),
  );
}
