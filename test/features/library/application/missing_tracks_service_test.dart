import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/application/missing_tracks_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repara una ruta única conservando el id y omite ambigüedades', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('astra-repair-');
    addTearDown(() async { await db.close(); await dir.delete(recursive: true); });
    final old = Uri.file('${dir.path}/old/song.mp3').toString();
    final id = await db.into(db.tracks).insert(TracksCompanion.insert(uri: old, title: 'Song', dateAdded: DateTime(2026)));
    final service = MissingTracksService(db);
    expect((await service.findMissing()).single.id, id);
    final found = await File('${dir.path}/song.mp3').create();
    expect((await service.repair(dir)).repaired, 1);
    expect((await db.select(db.tracks).getSingle()).uri, found.uri.toString());
    expect((await db.select(db.tracks).getSingle()).id, id);
  });
}
