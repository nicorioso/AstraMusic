import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/db/library_backup_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('respalda y restaura pistas y rechaza un archivo corrupto', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('astra-backup-');
    addTearDown(() async { await db.close(); await dir.delete(recursive: true); });
    final backup = File('${dir.path}/backup.gz');
    final service = LibraryBackupService(db);
    await db.into(db.tracks).insert(TracksCompanion.insert(uri: 'file:///song.mp3', title: 'Song', dateAdded: DateTime(2026)));
    await service.export(backup);
    await db.delete(db.tracks).go();
    await service.restore(backup);
    expect((await db.select(db.tracks).get()).single.title, 'Song');
    await backup.writeAsString('invalid');
    await expectLater(service.restore(backup), throwsA(isA<FormatException>()));
    expect((await db.select(db.tracks).get()).length, 1);
  });
}
