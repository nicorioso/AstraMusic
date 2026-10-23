import 'package:astramusic/core/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migra de 1 a 2 conservando tracks y creando library_folders', () async {
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

    expect(database.schemaVersion, 2);
    expect(tracks.single.title, 'Existente');
    expect(table?.read<String>('name'), 'library_folders');
  });
}
