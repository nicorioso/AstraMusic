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

  test('sincroniza cada lote antes de finalizar el escaneo', () async {
    final firstUri = path.join(root.path, 'primera.mp3');
    final missingUri = path.join(root.path, 'ausente.mp3');
    final scope = DesktopFolderScanScope(root.path);
    await service.synchronize(
      scannedTracks: [_scanned(missingUri)],
      scope: scope,
    );

    final session = await service.startIncremental(scope: scope);
    await session.addBatch([_scanned(firstUri)]);

    var tracks = await repository.watchAll().first;
    expect(tracks.any((track) => track.uri == firstUri), isTrue);
    expect(
      tracks.singleWhere((track) => track.uri == missingUri).isAvailable,
      isTrue,
    );

    final summary = await session.finish();
    tracks = await repository.watchAll().first;
    expect(summary.newCount, 1);
    expect(summary.unavailableCount, 1);
    expect(
      tracks.singleWhere((track) => track.uri == missingUri).isAvailable,
      isFalse,
    );
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

  test(
    'un archivo sin cambios conserva sus etiquetas y se contabiliza',
    () async {
      final uri = path.join(root.path, 'etiquetada.mp3');
      final scope = DesktopFolderScanScope(root.path);
      await service.synchronize(
        scannedTracks: [
          ScannedTrack(
            uri: uri,
            title: 'Título de etiqueta',
            artist: 'Artista',
            fileSize: 42,
            dateModified: DateTime(2026),
          ),
        ],
        scope: scope,
      );

      final summary = await service.synchronize(
        scannedTracks: [
          ScannedTrack(
            uri: uri,
            title: 'nombre-del-archivo',
            fileSize: 42,
            dateModified: DateTime(2026),
            unchanged: true,
          ),
        ],
        scope: scope,
      );
      final stored = (await repository.watchAll().first).single;

      expect(summary.unchangedCount, 1);
      expect(summary.updatedCount, 0);
      expect(stored.title, 'Título de etiqueta');
      expect(stored.artist, 'Artista');
    },
  );

  test('una uri excluida no reaparece en una sincronización', () async {
    final uri = path.join(root.path, 'borrada.mp3');
    final track = _scanned(uri);
    await service.synchronize(
      scannedTracks: [track],
      scope: DesktopFolderScanScope(root.path),
    );
    await repository.excludeAndDelete(
      (await repository.watchAll().first).single,
    );

    final summary = await service.synchronize(
      scannedTracks: [track],
      scope: DesktopFolderScanScope(root.path),
    );

    expect(summary.newCount, 0);
    expect(await repository.count(), 0);
  });
}

ScannedTrack _scanned(String uri) => ScannedTrack(
  uri: uri,
  title: path.basenameWithoutExtension(uri),
  fileSize: 42,
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);
