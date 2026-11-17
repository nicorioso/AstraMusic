import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/application/audio_download_controller.dart';
import 'package:astramusic/features/library/application/audio_download_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/playlists/data/drift_playlist_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

class _Backend implements AudioDownloadBackend {
  _Backend({
    this.empty = false,
    this.waitForCancel = false,
    this.thumbnailBytes,
    this.thumbnailUrl,
    this.extension = 'mp3',
  });
  final bool empty;
  final bool waitForCancel;
  final List<int>? thumbnailBytes;
  final String? thumbnailUrl;
  final String extension;
  final Completer<void> started = Completer<void>();
  final Completer<void> stopped = Completer<void>();
  int downloads = 0;

  @override
  Future<DownloadAvailability> checkAvailability() async =>
      const DownloadAvailability(available: true);

  @override
  Future<SourcePreview> analyzeUrl(String url) async => SourcePreview(
    id: 'abc123',
    title: 'Título de YouTube',
    author: 'Canal',
    duration: const Duration(seconds: 12),
    type: SourceType.video,
    thumbnailUrl: thumbnailUrl,
  );

  @override
  Future<PlaylistPreview> analyzePlaylist(String url) async => PlaylistPreview(
    id: 'PL123',
    title: 'Lista de prueba',
    author: 'Canal',
    entries: const [PlaylistEntry(id: 'abc123', title: 'Tema')],
  );

  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) async* {
    downloads++;
    final file = File(
      path.join(request.temporaryDirectory, 'abc123.$extension'),
    );
    await file.writeAsBytes(empty ? [] : [1, 2, 3]);
    final thumbnail = File(path.join(request.temporaryDirectory, 'abc123.jpg'));
    if (thumbnailBytes != null) await thumbnail.writeAsBytes(thumbnailBytes!);
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
        thumbnailPath: thumbnailBytes == null ? null : thumbnail.path,
        thumbnailUrl: thumbnailUrl,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    if (!stopped.isCompleted) stopped.complete();
  }
}

class _Tags implements ArtworkTagReader {
  _Tags({this.fail = false, this.artworkBytes});
  final bool fail;
  final Uint8List? artworkBytes;
  @override
  AudioTags read(File file) {
    if (fail) throw StateError('Fallo de etiquetas');
    return AudioTags(title: path.basenameWithoutExtension(file.path));
  }

  @override
  Uint8List? readArtwork(File file) => artworkBytes;
}

class _BatchBackend implements AudioDownloadBackend {
  _BatchBackend({this.failIds = const {}, this.blockId});
  final Set<String> failIds;
  final String? blockId;
  final blockedStarted = Completer<void>();
  final stopped = Completer<void>();
  final downloadedIds = <String>[];

  String _id(String url) => Uri.parse(url).queryParameters['v']!;

  @override
  Future<DownloadAvailability> checkAvailability() async =>
      const DownloadAvailability(available: true);
  @override
  Future<SourcePreview> analyzeUrl(String url) async {
    final id = _id(url);
    return SourcePreview(
      id: id,
      title: 'Tema $id',
      author: 'Canal',
      type: SourceType.video,
    );
  }

  @override
  Future<PlaylistPreview> analyzePlaylist(String url) async =>
      _playlistPreview();
  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) async* {
    final id = _id(request.url);
    downloadedIds.add(id);
    if (failIds.contains(id)) {
      yield const DownloadEvent(
        status: DownloadStatus.failed,
        error: 'Video unavailable',
      );
      return;
    }
    final file = File(path.join(request.temporaryDirectory, '$id.mp3'));
    await file.writeAsBytes([1, 2, 3]);
    yield const DownloadEvent(
      status: DownloadStatus.downloading,
      downloadedBytes: 1,
      totalBytes: 3,
    );
    if (id == blockId) {
      blockedStarted.complete();
      await stopped.future;
      yield const DownloadEvent(status: DownloadStatus.canceled);
      return;
    }
    yield DownloadEvent(
      status: DownloadStatus.completed,
      audio: DownloadedAudio(
        id: id,
        temporaryPath: file.path,
        title: 'Tema $id',
      ),
    );
  }

  @override
  Future<void> cancel() async {
    if (!stopped.isCompleted) stopped.complete();
  }
}

PlaylistPreview _playlistPreview() => PlaylistPreview(
  id: 'PL123',
  title: 'Mi playlist',
  author: 'Canal',
  entries: const [
    PlaylistEntry(id: 'uno123', title: 'Primera'),
    PlaylistEntry(id: 'dos456', title: 'Segunda'),
    PlaylistEntry(id: 'tres789', title: 'Tercera'),
  ],
);

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

  AudioDownloadService service(
    AudioDownloadBackend backend, {
    TagReader? tags,
    Future<List<int>?> Function(Uri)? fetchThumbnail,
  }) => AudioDownloadService(
    backend: backend,
    tracks: repository,
    playlists: DriftPlaylistRepository(database),
    tagReader: tags ?? _Tags(),
    fetchThumbnail: fetchThumbnail,
    supportDirectory: () async => root,
    temporaryDirectory: () async => Directory(path.join(root.path, 'tmp')),
  );

  for (final extension in ['m4a', 'mp3', 'opus', 'webm']) {
    test('registra audio .$extension desde la carpeta temporal', () async {
      final result = await service(_Backend(extension: extension))
          .download('https://youtu.be/abc123');
      expect(result.status, AudioImportStatus.downloaded);
      final track = (await repository.watchAll().first).single;
      expect(track.uri, endsWith('abc123.$extension'));
      expect(await File.fromUri(Uri.parse(track.uri)).length(), 3);
    });
  }

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
    'guarda la miniatura auxiliar y registra artworkPath en Drift',
    () async {
      final thumbnail = image.encodePng(image.Image(width: 8, height: 8));
      final result = await service(_Backend(thumbnailBytes: thumbnail))
          .download('https://youtu.be/abc123');
      final stored = (await repository.watchAll().first).single;
      expect(result.status, AudioImportStatus.downloaded);
      expect(stored.artworkPath, isNotNull);
      expect(stored.artworkPath, contains('downloaded_artwork'));
      expect(await File(stored.artworkPath!).length(), greaterThan(0));
      expect(
        image.decodeImage(await File(stored.artworkPath!).readAsBytes()),
        isNotNull,
      );
      expect(
        await Directory(path.join(root.path, 'tmp')).list().toList(),
        isEmpty,
      );
    },
  );

  test('usa miniatura embebida antes de la URL', () async {
    final embedded = Uint8List.fromList(
      image.encodePng(image.Image(width: 8, height: 8)),
    );
    var fetches = 0;
    await service(
      _Backend(thumbnailUrl: 'https://i.ytimg.com/vi/abc123/default.jpg'),
      tags: _Tags(artworkBytes: embedded),
      fetchThumbnail: (_) async {
        fetches++;
        return null;
      },
    ).download('https://youtu.be/abc123');
    final stored = (await repository.watchAll().first).single;
    expect(stored.artworkPath, isNotNull);
    expect(fetches, 0);
  });

  test('descarga miniatura de URL cuando no hay imagen local', () async {
    final thumbnail = image.encodePng(image.Image(width: 8, height: 8));
    Uri? requested;
    await service(
      _Backend(thumbnailUrl: 'https://i.ytimg.com/vi/abc123/default.jpg'),
      fetchThumbnail: (uri) async {
        requested = uri;
        return thumbnail;
      },
    ).download('https://youtu.be/abc123');
    final stored = (await repository.watchAll().first).single;
    expect(requested?.host, 'i.ytimg.com');
    expect(await File(stored.artworkPath!).length(), greaterThan(0));
  });

  test('si la imagen auxiliar está corrupta usa la URL de respaldo', () async {
    final thumbnail = image.encodePng(image.Image(width: 8, height: 8));
    var requests = 0;
    await service(
      _Backend(
        thumbnailBytes: [1, 2, 3],
        thumbnailUrl: 'https://i.ytimg.com/vi/abc123/default.jpg',
      ),
      fetchThumbnail: (_) async {
        requests++;
        return thumbnail;
      },
    ).download('https://youtu.be/abc123');
    final stored = (await repository.watchAll().first).single;
    expect(requests, 1);
    expect(await File(stored.artworkPath!).length(), greaterThan(0));
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
      service(
        _Backend(
          thumbnailBytes: image.encodePng(image.Image(width: 8, height: 8)),
        ),
      ).download('https://youtu.be/abc123'),
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
    final artworks = Directory(path.join(root.path, 'downloaded_artwork'));
    expect(await artworks.list().toList(), isEmpty);
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

  test(
    'lote continúa tras fallo y crea playlist en orden con duplicado',
    () async {
      final existingFile = File(
        path.join(root.path, 'downloaded_audio', 'dos456.mp3'),
      );
      await existingFile.parent.create(recursive: true);
      await existingFile.writeAsBytes([1, 2]);
      await repository.upsertAll([
        Track(
          uri: existingFile.uri.toString(),
          title: 'Personalizada',
          dateAdded: DateTime.utc(2020),
          isFavorite: true,
        ),
      ]);
      final backend = _BatchBackend(failIds: {'fallo00'});
      final preview = PlaylistPreview(
        id: 'PL123',
        title: 'Mi playlist',
        author: 'Canal',
        entries: const [
          PlaylistEntry(id: 'uno123', title: 'Primera'),
          PlaylistEntry(id: 'fallo00', title: 'Falla'),
          PlaylistEntry(id: 'dos456', title: 'Segunda'),
          PlaylistEntry(id: 'tres789', title: 'Tercera'),
        ],
      );
      final progress = <BatchProgress>[];
      final result = await service(backend)
          .downloadPlaylist(preview, onProgress: progress.add);
      expect(result.canceled, false);
      expect(result.addedCount, 2);
      expect(result.existingCount, 1);
      expect(result.errors['fallo00'], contains('no está disponible'));
      expect(
        progress.any(
          (item) =>
              item.index == 4 && item.total == 4 && item.title == 'Tercera',
        ),
        true,
      );
      final tracks = await DriftPlaylistRepository(database)
          .watchTracks(result.playlistId!)
          .first;
      expect(tracks.map((track) => track.title).toList(), [
        'Tema uno123',
        'Personalizada',
        'Tema tres789',
      ]);
      expect(tracks[1].isFavorite, true);
      expect(await repository.count(), 3);
    },
  );

  test(
    'cancelación de lote conserva completadas y limpia pista en curso',
    () async {
      final backend = _BatchBackend(blockId: 'dos456');
      final downloader = service(backend);
      final pending = downloader.downloadPlaylist(_playlistPreview());
      await backend.blockedStarted.future;
      await downloader.cancel();
      final result = await pending;
      expect(result.canceled, true);
      expect(result.addedCount, 1);
      expect(backend.downloadedIds, ['uno123', 'dos456']);
      final tracks = await DriftPlaylistRepository(database)
          .watchTracks(result.playlistId!)
          .first;
      expect(tracks.map((track) => track.title).toList(), ['Tema uno123']);
      expect(
        await File(path.join(root.path, 'downloaded_audio', 'dos456.mp3'))
            .exists(),
        false,
      );
      expect(
        await Directory(path.join(root.path, 'tmp')).list().toList(),
        isEmpty,
      );
    },
  );
}
