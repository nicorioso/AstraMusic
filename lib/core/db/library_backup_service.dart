import 'dart:convert';
import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:drift/drift.dart';

/// Respaldo lógico comprimido del esquema y de los datos locales.
final class LibraryBackupService {
  LibraryBackupService(this._db);

  final AppDatabase _db;
  static const _tables = [
    'tracks', 'playlists', 'playlist_tracks', 'play_history',
    'library_folders', 'playback_state', 'queue_items', 'excluded_uris',
  ];

  Future<void> export(File target) async {
    final data = <String, Object?>{};
    await _db.transaction(() async {
      for (final table in _tables) {
        data[table] = (await _db.customSelect('SELECT * FROM $table').get())
            .map((row) => row.data)
            .toList();
      }
    });
    final bytes = gzip.encode(utf8.encode(jsonEncode({
      'format': 'astramusic-backup-v1',
      'schemaVersion': _db.schemaVersion,
      'tables': data,
    })));
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  }

  Future<void> restore(File source) async {
    final decoded = jsonDecode(utf8.decode(gzip.decode(await source.readAsBytes())));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'astramusic-backup-v1' ||
        decoded['schemaVersion'] != _db.schemaVersion ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('Respaldo o esquema incompatible.');
    }
    final tables = decoded['tables'] as Map<String, dynamic>;
    if (tables.keys.toSet().difference(_tables.toSet()).isNotEmpty ||
        tables.keys.length != _tables.length) {
      throw const FormatException('Tablas del respaldo inválidas.');
    }
    final columns = <String, Set<String>>{};
    for (final table in _tables) {
      final info = await _db.customSelect('PRAGMA table_info($table)').get();
      columns[table] = info.map((row) => row.read<String>('name')).toSet();
      if (tables[table] is! List) throw const FormatException('Datos inválidos.');
      for (final entry in tables[table] as List) {
        if (entry is! Map<String, dynamic> ||
            !columns[table]!.containsAll(entry.keys)) {
          throw const FormatException('Columnas inválidas.');
        }
      }
    }
    await _db.transaction(() async {
      for (final table in _tables.reversed) {
        await _db.customStatement('DELETE FROM $table');
      }
      for (final table in _tables) {
        for (final entry in tables[table] as List) {
          final row = entry as Map<String, dynamic>;
          if (row.isEmpty) continue;
          final names = row.keys.toList();
          await _db.customInsert(
            'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')})',
            variables: names.map((name) => Variable(row[name])).toList(),
            updates: {_db.tracks, _db.playlists, _db.playlistTracks, _db.playHistory, _db.libraryFolders, _db.playbackState, _db.queueItems, _db.excludedUris},
          );
        }
      }
      final check = await _db.customSelect('PRAGMA foreign_key_check').get();
      if (check.isNotEmpty) throw const FormatException('Referencias inválidas.');
    });
  }
}
