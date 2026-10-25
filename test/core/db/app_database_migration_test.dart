import 'package:astramusic/core/db/app_database.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migra de 7 a 8 y rellena favorited_at solo para favoritos', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionSevenSchema(database);
        database.execute('''
          INSERT INTO tracks (id, uri, title, date_added, is_favorite)
          VALUES
            (1, 'file:///favorita.mp3', 'Favorita', 1767225600000, 1),
            (2, 'file:///normal.mp3', 'Normal', 1767312000000, 0)
        ''');
        database.userVersion = 7;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final tracks = await (database.select(database.tracks)
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();

    expect(database.schemaVersion, 8);
    expect(tracks.first.favoritedAt, tracks.first.dateAdded);
    expect(tracks.last.favoritedAt, isNull);
  });

  test('migra de 6 a 7, deduplica y crea el índice único', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionSixPlaylistSchema(database);
        database.execute('''
          INSERT INTO tracks (id, uri, title, date_added)
          VALUES (1, 'file:///uno.mp3', 'Uno', 1767225600000)
        ''');
        database.execute('''
          INSERT INTO playlists (id, name, created_at, updated_at)
          VALUES (1, 'Lista', 1767225600000, 1767225600000)
        ''');
        database.execute('''
          INSERT INTO playlist_tracks
            (id, playlist_id, track_id, position, added_at)
          VALUES
            (1, 1, 1, 0, 1767225600000),
            (2, 1, 1, 1, 1767225600000)
        ''');
        database.userVersion = 6;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final playlist = await database.select(database.playlists).getSingle();
    final relations = await database.select(database.playlistTracks).get();

    expect(database.schemaVersion, 8);
    expect(playlist.lastPlayedAt, isNull);
    expect(relations.map((row) => row.id), [1]);
    await expectLater(
      database
          .into(database.playlistTracks)
          .insert(
            PlaylistTracksCompanion.insert(
              playlistId: 1,
              trackId: 1,
              position: 2,
              addedAt: DateTime(2026),
            ),
          ),
      throwsA(anything),
    );
  });

  test('migra de 1 a 3 conservando tracks y creando library_folders', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE tracks (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            uri TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NULL,
            album TEXT NULL,
            duration_ms INTEGER NULL,
            track_number INTEGER NULL,
            year INTEGER NULL,
            file_size INTEGER NULL,
            date_added INTEGER NOT NULL,
            is_available INTEGER NOT NULL DEFAULT 1
              CHECK (is_available IN (0, 1)),
            is_favorite INTEGER NOT NULL DEFAULT 0
              CHECK (is_favorite IN (0, 1))
          )
        ''');
        database.execute('CREATE INDEX tracks_title_idx ON tracks (title)');
        database.execute('''
          CREATE TABLE playlists (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        database.execute('''
          CREATE TABLE playlist_tracks (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            playlist_id INTEGER NOT NULL REFERENCES playlists (id)
              ON DELETE CASCADE,
            track_id INTEGER NOT NULL REFERENCES tracks (id)
              ON DELETE CASCADE,
            position INTEGER NOT NULL,
            added_at INTEGER NOT NULL
          )
        ''');
        database.execute('''
          CREATE INDEX playlist_tracks_playlist_position_idx
          ON playlist_tracks (playlist_id, position)
        ''');
        database.execute(
          "INSERT INTO tracks (uri, title, date_added) "
          "VALUES ('file:///existente.mp3', 'Existente', 1767225600000)",
        );
        database.userVersion = 1;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final tracks = await database.select(database.tracks).get();
    final table = await database
        .customSelect(
          "SELECT name FROM sqlite_schema "
          "WHERE type = 'table' AND name = 'library_folders'",
        )
        .getSingleOrNull();

    expect(database.schemaVersion, 8);
    expect(tracks.single.title, 'Existente');
    expect(tracks.single.searchText, 'existente');
    expect(tracks.single.sortTitle, 'existente');
    expect(table?.read<String>('name'), 'library_folders');
  });

  test('migra de 3 a 4 y añade artwork_path nullable', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionThreeTracks(database);
        _createLegacyPlaylistTables(database);
        database.execute(
          "INSERT INTO tracks (uri, title, date_added, search_text, sort_title) "
          "VALUES ('file:///tema.mp3', 'Tema', 1767225600000, 'tema', 'tema')",
        );
        database.userVersion = 3;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final track = await database.select(database.tracks).getSingle();
    expect(track.title, 'Tema');
    expect(track.artworkPath, isNull);
    expect(database.schemaVersion, 8);
  });

  test('migra de 4 a 5 y crea el estado y la cola persistidos', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionFourSchema(database);
        database.userVersion = 4;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_schema WHERE type = 'table' "
          "AND name IN ('playback_state', 'queue_items') ORDER BY name",
        )
        .get();

    expect(tables.map((row) => row.read<String>('name')), [
      'playback_state',
      'queue_items',
    ]);
    expect(database.schemaVersion, 8);
  });

  test('migra de 5 a 6 y crea excluded_uris con uri única', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionFourSchema(database);
        database.execute('''
          CREATE TABLE playback_state (
            id INTEGER NOT NULL PRIMARY KEY DEFAULT 1,
            current_index INTEGER NULL,
            position_ms INTEGER NOT NULL DEFAULT 0,
            shuffle INTEGER NOT NULL DEFAULT 0 CHECK (shuffle IN (0, 1)),
            repeat_mode TEXT NOT NULL DEFAULT 'off',
            updated_at INTEGER NOT NULL
          )
        ''');
        database.execute('''
          CREATE TABLE queue_items (
            position INTEGER NOT NULL PRIMARY KEY,
            track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
            original_position INTEGER NULL
          )
        ''');
        database.userVersion = 5;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    await database
        .into(database.excludedUris)
        .insert(ExcludedUrisCompanion.insert(uri: 'file:///borrada.mp3'));

    expect(
      () => database
          .into(database.excludedUris)
          .insert(ExcludedUrisCompanion.insert(uri: 'file:///borrada.mp3')),
      throwsA(anything),
    );
    expect(database.schemaVersion, 8);
  });

  test('migra de 2 a 3, hace backfill y conserva todas las tablas', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        _createVersionTwoSchema(database);
        database.execute('''
          INSERT INTO tracks (
            id, uri, title, artist, album, date_added
          ) VALUES (
            1, 'file:///cancion.mp3', 'Canción', 'NIÑA', 'Álbum',
            1767225600000
          )
        ''');
        database.execute('''
          INSERT INTO playlists (id, name, created_at, updated_at)
          VALUES (1, 'Favoritas', 1767225600000, 1767225600000)
        ''');
        database.execute('''
          INSERT INTO playlist_tracks (
            id, playlist_id, track_id, position, added_at
          ) VALUES (1, 1, 1, 0, 1767225600000)
        ''');
        database.execute('''
          INSERT INTO library_folders (id, path, added_at)
          VALUES (1, '/música', 1767225600000)
        ''');
        database.userVersion = 2;
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final track = await database.select(database.tracks).getSingle();
    final playlists = await database.select(database.playlists).get();
    final relations = await database.select(database.playlistTracks).get();
    final folders = await database.select(database.libraryFolders).get();
    final indices = await database
        .customSelect(
          "SELECT name FROM sqlite_schema WHERE type = 'index' "
          "AND name LIKE 'tracks_%_idx' ORDER BY name",
        )
        .get();

    expect(track.title, 'Canción');
    expect(track.searchText, 'cancion nina album');
    expect(track.sortTitle, 'cancion');
    expect(track.dateModified, isNull);
    expect(playlists.single.name, 'Favoritas');
    expect(relations.single.trackId, track.id);
    expect(folders.single.path, '/música');
    expect(indices.map((row) => row.read<String>('name')), [
      'tracks_sort_title_idx',
    ]);
  });
}

void _createVersionSevenSchema(dynamic database) {
  _createVersionSixPlaylistSchema(database);
  database.execute('ALTER TABLE playlists ADD COLUMN last_played_at INTEGER NULL');
  database.execute('''
    CREATE UNIQUE INDEX playlist_tracks_playlist_track_idx
    ON playlist_tracks (playlist_id, track_id)
  ''');
  database.execute('''
    CREATE TABLE library_folders (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      added_at INTEGER NOT NULL,
      last_scanned_at INTEGER NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playback_state (
      id INTEGER NOT NULL PRIMARY KEY DEFAULT 1,
      current_index INTEGER NULL,
      position_ms INTEGER NOT NULL DEFAULT 0,
      shuffle INTEGER NOT NULL DEFAULT 0 CHECK (shuffle IN (0, 1)),
      repeat_mode TEXT NOT NULL DEFAULT 'off',
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE queue_items (
      position INTEGER NOT NULL PRIMARY KEY,
      track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
      original_position INTEGER NULL
    )
  ''');
  database.execute('CREATE TABLE excluded_uris (uri TEXT NOT NULL PRIMARY KEY)');
}

void _createVersionSixPlaylistSchema(dynamic database) {
  database.execute('''
    CREATE TABLE tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      uri TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      artist TEXT NULL,
      album TEXT NULL,
      duration_ms INTEGER NULL,
      track_number INTEGER NULL,
      year INTEGER NULL,
      file_size INTEGER NULL,
      date_added INTEGER NOT NULL,
      date_modified INTEGER NULL,
      search_text TEXT NOT NULL DEFAULT '',
      sort_title TEXT NOT NULL DEFAULT '',
      is_available INTEGER NOT NULL DEFAULT 1 CHECK (is_available IN (0, 1)),
      is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
      artwork_path TEXT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playlists (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playlist_tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
      track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE INDEX playlist_tracks_playlist_position_idx
    ON playlist_tracks (playlist_id, position)
  ''');
}

void _createVersionThreeTracks(dynamic database) {
  database.execute('''
    CREATE TABLE tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      uri TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      artist TEXT NULL,
      album TEXT NULL,
      duration_ms INTEGER NULL,
      track_number INTEGER NULL,
      year INTEGER NULL,
      file_size INTEGER NULL,
      date_added INTEGER NOT NULL,
      date_modified INTEGER NULL,
      search_text TEXT NOT NULL DEFAULT '',
      sort_title TEXT NOT NULL DEFAULT '',
      is_available INTEGER NOT NULL DEFAULT 1 CHECK (is_available IN (0, 1)),
      is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1))
    )
  ''');
  database.execute(
    'CREATE INDEX tracks_sort_title_idx ON tracks (sort_title, id)',
  );
}

void _createLegacyPlaylistTables(dynamic database) {
  database.execute('''
    CREATE TABLE playlists (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playlist_tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
      track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    )
  ''');
}

void _createVersionFourSchema(dynamic database) {
  _createVersionThreeTracks(database);
  database.execute('ALTER TABLE tracks ADD COLUMN artwork_path TEXT NULL');
  database.execute('''
    CREATE TABLE playlists (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playlist_tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
      track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE library_folders (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      added_at INTEGER NOT NULL,
      last_scanned_at INTEGER NULL
    )
  ''');
}

void _createVersionTwoSchema(dynamic database) {
  database.execute('''
    CREATE TABLE tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      uri TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      artist TEXT NULL,
      album TEXT NULL,
      duration_ms INTEGER NULL,
      track_number INTEGER NULL,
      year INTEGER NULL,
      file_size INTEGER NULL,
      date_added INTEGER NOT NULL,
      is_available INTEGER NOT NULL DEFAULT 1
        CHECK (is_available IN (0, 1)),
      is_favorite INTEGER NOT NULL DEFAULT 0
        CHECK (is_favorite IN (0, 1))
    )
  ''');
  database.execute('CREATE INDEX tracks_title_idx ON tracks (title)');
  database.execute('''
    CREATE TABLE playlists (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE playlist_tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL REFERENCES playlists (id)
        ON DELETE CASCADE,
      track_id INTEGER NOT NULL REFERENCES tracks (id)
        ON DELETE CASCADE,
      position INTEGER NOT NULL,
      added_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE INDEX playlist_tracks_playlist_position_idx
    ON playlist_tracks (playlist_id, position)
  ''');
  database.execute('''
    CREATE TABLE library_folders (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      added_at INTEGER NOT NULL,
      last_scanned_at INTEGER NULL
    )
  ''');
}
