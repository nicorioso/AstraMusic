import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/application/audio_download_controller.dart';
import 'package:astramusic/features/library/application/audio_download_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _Backend implements AudioDownloadBackend {
  _Backend({this.empty = false, this.waitForCancel = false});
  final bool empty;
  final bool waitForCancel;
  final Completer<void> started = Completer<void>();
  final Completer<void> stopped = Completer<void>();
  int downloads = 0;

  @override
  Future<DownloadAvailability> checkAvailability() async =>
      const DownloadAvailability(available: true);

  @override
  Future<SourcePreview> analyzeUrl(String url) async => const SourcePreview(
    id: 'abc123',
    title: 'Título de YouTube',
    author: 'Canal',
    duration: Duration(seconds: 12),
    type: SourceType.video,
  );

  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) async* {
    downloads++;
    final file = File(path.join(request.temporaryDirectory, 'abc123.mp3'));
    await file.writeAsBytes(empty ? [] : [1, 2, 3]);
    if (!started.isCompleted) started.complete();
    yield const DownloadEvent(
      status: DownloadStatus.downloading,
      downloadedBytes: 3,
      totalBytes: 3,
    );
    if (waitForCancel) {
      await stopped.future;
      yield const DownloadEvent(status: DownloadStatus.canceled);
      return;
    }
    yield DownloadEvent(
      status: DownloadStatus.completed,
      audio: DownloadedAudio(
        id: 'abc123',
        temporaryPath: file.path,
        title: 'Título de YouTube',
      ),
    );
  }

  @override
  Future<void> cancel() async {
    if (!stopped.isCompleted) stopped.complete();
  }
}

class _Tags implements TagReader {
  _Tags({this.fail = false});
  final bool fail;
  @override
  AudioTags read(File file) {
    if (fail) throw StateError('Fallo de etiquetas');
    return const AudioTags(title: 'abc123');
  }
}

void main() {
  late Directory root;
  late AppDatabase database;
  late DriftTrackRepository repository;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('astra-service-test-');
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTrackRepository(database);
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  AudioDownloadService service(_Backend backend, {TagReader? tags}) =>
      AudioDownloadService(
        backend: backend,
        tracks: repository,
        tagReader: tags ?? _Tags(),
        supportDirectory: () async => root,
        temporaryDirectory: () async => Directory(path.join(root.path, 'tmp')),
      );

  test('mueve y registra audio con respaldo de metadatos', () async {
    final backend = _Backend();
    final result = await service(backend).download('https://youtu.be/abc123');
    expect(result.status, AudioImportStatus.downloaded);
    final track = (await repository.watchAll().first).single;
    expect(
      track.uri,
      File(path.join(root.path, 'downloaded_audio', 'abc123.mp3')).uri
          .toString(),
    );
    expect(track.title, 'Título de YouTube');
    expect(track.artist, 'Canal');
    expect(track.duration, const Duration(seconds: 12));
    expect(track.fileSize, 3);
    expect(await File.fromUri(Uri.parse(track.uri)).length(), 3);
    expect(
      await Directory(path.join(root.path, 'tmp')).list().toList(),
      isEmpty,
    );
  });

  test(
    'omite duplicado sin alterar favorito ni metadatos personalizados',
    () async {
      final backend = _Backend();
      final downloader = service(backend);
      await downloader.download('https://youtu.be/abc123');
      final original = (await repository.watchAll().first).single;
      await repository.upsertAll([
        Track(
          id: original.id,
          uri: original.uri,
          title: 'Mi título',
          artist: 'Mi artista',
          dateAdded: DateTime.utc(2020),
          isFavorite: true,
        ),
      ]);
      final duplicate = await downloader.download('https://youtu.be/abc123');
      final stored = (await repository.watchAll().first).single;
      expect(duplicate.status, AudioImportStatus.duplicate);
      expect(backend.downloads, 1);
      expect(stored.title, 'Mi título');
      expect(stored.artist, 'Mi artista');
      expect(stored.dateAdded.isAtSameMomentAs(DateTime.utc(2020)), true);
      expect(stored.isFavorite, true);
    },
  );

  test('rechaza archivo vacío y elimina el temporal', () async {
    final backend = _Backend(empty: true);
    await expectLater(
      service(backend).download('https://youtu.be/abc123'),
      throwsStateError,
    );
    expect(await repository.count(), 0);
    expect(
      await Directory(path.join(root.path, 'tmp')).list().toList(),
      isEmpty,
    );
    expect(
      await Directory(path.join(root.path, 'downloaded_audio')).exists(),
      false,
    );
  });

  test('revierte archivo definitivo si falla lectura de etiquetas', () async {
    await expectLater(
      service(
        _Backend(),
        tags: _Tags(fail: true),
      ).download('https://youtu.be/abc123'),
      throwsStateError,
    );
    expect(await repository.count(), 0);
    expect(
      await File(path.join(root.path, 'downloaded_audio', 'abc123.mp3'))
          .exists(),
      false,
    );
    expect(
      await Directory(path.join(root.path, 'tmp')).list().toList(),
      isEmpty,
    );
  });

  test('revierte archivo definitivo si Drift rechaza registro', () async {
    await database.customStatement(
      'CREATE TRIGGER reject_download BEFORE INSERT ON tracks BEGIN SELECT RAISE(ABORT, "rechazado"); END',
    );
    await expectLater(
      service(_Backend()).download('https://youtu.be/abc123'),
      throwsA(isA<Exception>()),
    );
    expect(await repository.count(), 0);
    expect(
      await File(path.join(root.path, 'downloaded_audio', 'abc123.mp3'))
          .exists(),
      false,
    );
    expect(
      await Directory(path.join(root.path, 'tmp')).list().toList(),
      isEmpty,
    );
  });

  test('cancela y limpia el trabajo temporal', () async {
    final backend = _Backend(waitForCancel: true);
    final downloader = service(backend);
    final pending = downloader.download('https://youtu.be/abc123');
    await backend.started.future;
    await downloader.cancel();
    expect((await pending).status, AudioImportStatus.canceled);
    expect(await repository.count(), 0);
    expect(
      await Directory(path.join(root.path, 'tmp')).list().toList(),
      isEmpty,
    );
  });

  test(
    'provider separado publica progreso y resultado sin LibraryController',
    () async {
      final backend = _Backend();
      final container = ProviderContainer(
        overrides: [
          audioDownloadServiceProvider.overrideWithValue(service(backend)),
        ],
      );
      addTearDown(container.dispose);
      final states = <AudioDownloadState>[];
      final listener = container.listen(
        audioDownloadControllerProvider,
        (_, next) => states.add(next),
      );
      addTearDown(listener.close);
      final controller = container.read(
        audioDownloadControllerProvider.notifier,
      );
      await controller.refreshAvailability();
      expect(
        container.read(audioDownloadControllerProvider).availability?.available,
        true,
      );
      await controller.analyze('https://youtu.be/abc123');
      expect(
        container.read(audioDownloadControllerProvider).preview?.id,
        'abc123',
      );
      await controller.start('https://youtu.be/abc123');
      expect(
        states.any((state) => state.status == DownloadStatus.downloading),
        true,
      );
      expect(
        container.read(audioDownloadControllerProvider).status,
        DownloadStatus.completed,
      );
      expect(
        container.read(audioDownloadControllerProvider).track?.title,
        'Título de YouTube',
      );
    },
  );

  test('provider publica error y cancelación', () async {
    final emptyContainer = ProviderContainer(
      overrides: [
        audioDownloadServiceProvider.overrideWithValue(
          service(_Backend(empty: true)),
        ),
      ],
    );
    addTearDown(emptyContainer.dispose);
    await emptyContainer
        .read(audioDownloadControllerProvider.notifier)
        .start('https://youtu.be/abc123');
    final failed = emptyContainer.read(audioDownloadControllerProvider);
    expect(failed.status, DownloadStatus.failed);
    expect(failed.error, isNotEmpty);
    expect(failed.isBusy, false);

    final backend = _Backend(waitForCancel: true);
    final container = ProviderContainer(
      overrides: [
        audioDownloadServiceProvider.overrideWithValue(service(backend)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(audioDownloadControllerProvider.notifier);
    final pending = controller.start('https://youtu.be/abc123');
    await backend.started.future;
    await controller.cancel();
    await pending;
    final canceled = container.read(audioDownloadControllerProvider);
    expect(canceled.status, DownloadStatus.canceled);
    expect(canceled.isBusy, false);
  });
}
