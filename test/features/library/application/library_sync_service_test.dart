import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/features/library/application/library_sync_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late AppDatabase database;
  late DriftTrackRepository repository;
  late LibrarySyncService service;
  late Directory root;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTrackRepository(database);
    service = LibrarySyncService(repository);
    root = await Directory.systemTemp.createTemp('astramusic_sync_');
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('dos escaneos iguales son idempotentes', () async {
    final scanned = [_scanned(path.join(root.path, 'única.mp3'))];
    final scope = DesktopFolderScanScope(root.path);

    final first = await service.synchronize(
      scannedTracks: scanned,
      scope: scope,
    );
    final second = await service.synchronize(
      scannedTracks: scanned,
      scope: scope,
    );

    expect(first.newCount, 1);
    expect(second.newCount, 0);
    expect(second.updatedCount, 0);
    expect(await repository.count(), 1);
  });

  test('marca ausentes y reactiva archivos que reaparecen', () async {
    final firstUri = path.join(root.path, 'primera.mp3');
    final secondUri = path.join(root.path, 'segunda.mp3');
    final scope = DesktopFolderScanScope(root.path);
    await service.synchronize(
      scannedTracks: [_scanned(firstUri), _scanned(secondUri)],
      scope: scope,
    );

    final missingSummary = await service.synchronize(
      scannedTracks: [_scanned(firstUri)],
      scope: scope,
    );
    var tracks = await repository.watchAll().first;
    expect(missingSummary.unavailableCount, 1);
    expect(
      tracks.singleWhere((track) => track.uri == secondUri).isAvailable,
      isFalse,
    );

    final restoredSummary = await service.synchronize(
      scannedTracks: [_scanned(firstUri), _scanned(secondUri)],
      scope: scope,
    );
    tracks = await repository.watchAll().first;
    expect(restoredSummary.updatedCount, 1);
    expect(
      tracks.singleWhere((track) => track.uri == secondUri).isAvailable,
      isTrue,
    );
    expect(await repository.count(), 2);
  });
}

ScannedTrack _scanned(String uri) => ScannedTrack(
  uri: uri,
  title: path.basenameWithoutExtension(uri),
  fileSize: 42,
  dateAdded: DateTime(2026),
);
