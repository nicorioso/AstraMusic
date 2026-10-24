import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_cache.dart';
import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/media_library_permission.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/library_folders_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/library_screen.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conserva la carátula compartida al borrar una canción', () async {
    final first = Track(
      id: 1,
      uri: 'file:///uno.mp3',
      title: 'Uno',
      artist: 'Artista',
      album: 'Álbum',
      dateAdded: DateTime(2026),
    );
    final second = Track(
      id: 2,
      uri: 'file:///dos.mp3',
      title: 'Dos',
      artist: 'Artista',
      album: 'Álbum',
      dateAdded: DateTime(2026),
    );
    final repository = RecordingTrackRepository([first, second]);
    final cache = RecordingArtworkCache();
    final container = ProviderContainer(
      overrides: [
        trackRepositoryProvider.overrideWithValue(repository),
        audioPlayerServiceProvider.overrideWithValue(
          const FakeAudioPlayerService(),
        ),
        artworkCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.notifier).deleteTrack(first);

    expect(repository.deletedUris, {'file:///uno.mp3'});
    expect(cache.deletedKeys, isEmpty);
  });

  test('Añadir archivos recupera una uri excluida', () async {
    final repository = RecordingTrackRepository([]);
    final container = ProviderContainer(
      overrides: [
        trackRepositoryProvider.overrideWithValue(repository),
        audioPlayerServiceProvider.overrideWithValue(
          const FakeAudioPlayerService(),
        ),
        audioFilePickerProvider.overrideWithValue(const _PickedFilePicker()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.notifier).addFiles();

    expect(repository.restoredUris, {'content://document/audio/1'});
    expect(repository.tracks.single.uri, 'content://document/audio/1');
  });

  testWidgets('muestra el estado vacío de la biblioteca', (tester) async {
    await tester.pumpWidget(_testApp(const FakeTrackRepository([])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty-library-message')), findsOneWidget);
    expect(find.byKey(const Key('scan-library-button')), findsNothing);
    expect(find.text('Escanear música del dispositivo'), findsNothing);
    expect(find.text('Actualizar biblioteca'), findsNothing);
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir archivos'), findsOneWidget);
  });

  testWidgets('muestra canciones del repositorio sin tipos de drift', (
    tester,
  ) async {
    final tracks = [
      Track(
        id: 1,
        uri: 'file:///primera.mp3',
        title: 'Primera canción',
        artist: 'Artista local',
        duration: const Duration(minutes: 3, seconds: 5),
        dateAdded: DateTime(2026),
      ),
      Track(
        id: 2,
        uri: 'file:///segunda.mp3',
        title: 'Segunda canción',
        dateAdded: DateTime(2026),
      ),
    ];

    await tester.pumpWidget(_testApp(FakeTrackRepository(tracks)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-track-list')), findsOneWidget);
    expect(find.text('Primera canción'), findsOneWidget);
    expect(find.text('Artista local'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
    expect(find.text('Segunda canción'), findsOneWidget);
  });

  testWidgets('atenúa una canción no disponible y no intenta reproducirla', (
    tester,
  ) async {
    var playQueueCalls = 0;
    final track = Track(
      id: 1,
      uri: 'file:///ausente.mp3',
      title: 'Canción ausente',
      dateAdded: DateTime(2026),
      isAvailable: false,
    );
    await tester.pumpWidget(
      _testApp(
        FakeTrackRepository([track]),
        player: FakeAudioPlayerService(onPlayQueue: () => playQueueCalls++),
      ),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('track-availability-file:///ausente.mp3')),
    );
    expect(opacity.opacity, lessThan(1));
    expect(find.text('No disponible'), findsOneWidget);

    await tester.tap(find.text('Canción ausente'));
    await tester.pump();

    expect(playQueueCalls, 0);
    expect(find.text('No disponible'), findsWidgets);
  });

  testWidgets('muestra progreso y resumen del escaneo', (tester) async {
    final scanner = ControlledLibraryScanner();
    await tester.pumpWidget(
      _testApp(const FakeTrackRepository([]), scanner: scanner),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    unawaited(container.read(libraryControllerProvider.notifier).startScan());
    await tester.pump();
    await tester.pump();
    scanner.addProgress(foundCount: 7, errorCount: 1);
    await tester.pump();

    expect(find.byKey(const Key('scan-progress')), findsOneWidget);
    expect(
      find.text('Escaneando: 7 encontradas, 0 sin cambios, 1 errores'),
      findsOneWidget,
    );

    await scanner.complete([
      const ScannedTrack(
        uri: 'content://media/external/audio/media/1',
        title: 'Encontrada',
      ),
    ], errorCount: 1);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-progress')), findsNothing);
    expect(
      find.text(
        '1 nuevas, 0 actualizadas, 0 sin cambios, '
        '0 no disponibles, 1 errores.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('bloquea nuevos escaneos mientras termina la cancelación', (
    tester,
  ) async {
    final scanner = ControlledLibraryScanner()..delayCancellation();
    await tester.pumpWidget(
      _testApp(const FakeTrackRepository([]), scanner: scanner),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    unawaited(container.read(libraryControllerProvider.notifier).startScan());
    await tester.pump();
    await tester.pump();
    final cancellation = container
        .read(libraryControllerProvider.notifier)
        .cancelScan();
    await tester.pump();
    await scanner.cancellationStarted;

    expect(find.text('Cancelando...'), findsOneWidget);
    expect(container.read(libraryControllerProvider).actionsDisabled, isTrue);

    scanner.completeCancellation();
    await cancellation;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('scan-progress')), findsNothing);
  });

  for (final size in const [Size(360, 800), Size(1200, 800)]) {
    testWidgets('biblioteca no desborda a ${size.width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tracks = [
        Track(
          id: 1,
          uri: 'file:///長い曲.mp3',
          title: '星間の非常に長い曲名とコロンビアの夜空を巡る歌',
          artist: 'とても長い名前のアーティストと仲間たち',
          duration: const Duration(hours: 1, minutes: 2, seconds: 3),
          dateAdded: DateTime(2026),
        ),
      ];

      await tester.pumpWidget(_testApp(FakeTrackRepository(tracks)));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('la lista usa al menos 70% de alto y muestra ocho filas', (
    tester,
  ) async {
    const size = Size(937, 1029);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tracks = List.generate(
      30,
      (index) => Track(
        id: index,
        uri: 'file:///cancion-$index.mp3',
        title: 'Canción $index',
        dateAdded: DateTime(2026),
      ),
    );

    await tester.pumpWidget(_testApp(FakeTrackRepository(tracks)));
    await tester.pumpAndSettle();

    final viewport = tester.getSize(
      find.byKey(const Key('library-track-list')),
    );
    expect(viewport.height, greaterThanOrEqualTo(size.height * 0.70));
    expect(find.text('Canción 7'), findsOneWidget);
  });

  testWidgets('la lista de carpetas usa al menos 70% de alto', (tester) async {
    const size = Size(937, 1029);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final folders = List.generate(
      30,
      (index) => LibraryFolder(
        id: index,
        path: '/música/carpeta-$index',
        addedAt: DateTime(2026),
      ),
    );

    await tester.pumpWidget(
      _testApp(
        const FakeTrackRepository([]),
        isAndroid: false,
        foldersRepository: FakeLibraryFoldersRepository(folders),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('music-folders-button')));
    await tester.pumpAndSettle();

    final viewport = tester.getSize(
      find.byKey(const Key('music-folders-list')),
    );
    expect(viewport.height, greaterThanOrEqualTo(size.height * 0.70));
  });
}

Widget _testApp(
  TrackRepository repository, {
  LibraryScanner? scanner,
  bool isAndroid = true,
  LibraryFoldersRepository? foldersRepository,
  AudioPlayerService player = const FakeAudioPlayerService(),
}) {
  return ProviderScope(
    overrides: [
      trackRepositoryProvider.overrideWithValue(repository),
      isAndroidPlatformProvider.overrideWithValue(isAndroid),
      if (foldersRepository != null)
        libraryFoldersRepositoryProvider.overrideWithValue(foldersRepository),
      libraryScannerProvider.overrideWithValue(
        scanner ?? ControlledLibraryScanner(),
      ),
      mediaLibraryPermissionProvider.overrideWithValue(
        const FakeMediaLibraryPermission(),
      ),
      audioPlayerServiceProvider.overrideWithValue(player),
      audioFilePickerProvider.overrideWithValue(const FakeAudioFilePicker()),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      home: const LibraryScreen(),
    ),
  );
}

final class FakeLibraryFoldersRepository implements LibraryFoldersRepository {
  const FakeLibraryFoldersRepository(this.folders);

  final List<LibraryFolder> folders;

  @override
  Future<LibraryFolder> add(String path) => throw UnimplementedError();

  @override
  Future<void> markScanned(int id, DateTime scannedAt) async {}

  @override
  Future<void> remove(int id) async {}

  @override
  Stream<List<LibraryFolder>> watchAll() => Stream.value(folders);
}

final class ControlledLibraryScanner implements LibraryScanner {
  StreamController<ScanEvent>? _controller;
  Completer<void>? _cancellationGate;
  final Completer<void> _cancellationStarted = Completer<void>();

  Future<void> get cancellationStarted => _cancellationStarted.future;

  @override
  Future<LibraryScanTask> startScan({
    String? rootPath,
    Map<String, KnownFileStats> knownFiles = const {},
  }) async {
    final controller = StreamController<ScanEvent>();
    _controller = controller;
    return LibraryScanTask(controller.stream, () async {
      if (!_cancellationStarted.isCompleted) _cancellationStarted.complete();
      final gate = _cancellationGate;
      if (gate != null) {
        await gate.future;
      }
      if (!controller.isClosed) {
        controller.add(const ScanCancelled());
        unawaited(controller.close());
      }
    });
  }

  void delayCancellation() {
    _cancellationGate = Completer<void>();
  }

  void completeCancellation() {
    _cancellationGate?.complete();
  }

  void addProgress({required int foundCount, required int errorCount}) {
    _controller!.add(
      ScanProgress(foundCount: foundCount, errorCount: errorCount),
    );
  }

  Future<void> complete(
    List<ScannedTrack> tracks, {
    required int errorCount,
  }) async {
    final controller = _controller!;
    controller.add(ScanCompleted(tracks: tracks, errorCount: errorCount));
    await controller.close();
  }
}

final class FakeMediaLibraryPermission implements MediaLibraryPermission {
  const FakeMediaLibraryPermission();

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<MediaLibraryPermissionStatus> request() async =>
      MediaLibraryPermissionStatus.granted;
}

final class FakeTrackRepository implements TrackRepository {
  const FakeTrackRepository(this.tracks);

  final List<Track> tracks;

  @override
  Future<int> count() async => tracks.length;

  @override
  Future<void> deleteByUris(Set<String> uris) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<Set<String>> excludedUris() async => const {};

  @override
  Future<void> excludeAndDelete(Track track) async {}

  @override
  Future<void> restoreExcluded(Set<String> uris) async {}

  @override
  Future<void> clearLibrary() async {}

  @override
  Future<Track?> getById(int id) async {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  Future<void> markUnavailable(Set<String> uris) async {}

  @override
  Future<void> setAvailability(Map<String, bool> availability) async {}

  @override
  Future<void> upsertAll(List<Track> tracks) async {}

  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);

  @override
  Stream<List<Track>> watchSearch(String query) => Stream.value(
    tracks
        .where(
          (track) =>
              [track.title, track.artist, track.album].whereType<String>().any(
                (value) => value.toLowerCase().contains(query.toLowerCase()),
              ),
        )
        .toList(growable: false),
  );
}

final class RecordingTrackRepository implements TrackRepository {
  RecordingTrackRepository(this.tracks);

  final List<Track> tracks;
  final Set<String> deletedUris = {};
  final Set<String> restoredUris = {};

  @override
  Future<void> excludeAndDelete(Track track) async {
    deletedUris.add(track.uri);
    tracks.removeWhere((candidate) => candidate.uri == track.uri);
  }

  @override
  Future<void> restoreExcluded(Set<String> uris) async =>
      restoredUris.addAll(uris);

  @override
  Future<void> upsertAll(List<Track> values) async => tracks.addAll(values);

  @override
  Stream<List<Track>> watchAll() => Stream.value(List.of(tracks));

  @override
  Stream<List<Track>> watchSearch(String query) => watchAll();

  @override
  Future<int> count() async => tracks.length;

  @override
  Future<void> clearLibrary() async => tracks.clear();

  @override
  Future<void> deleteAll() async => tracks.clear();

  @override
  Future<void> deleteByUris(Set<String> uris) async =>
      tracks.removeWhere((track) => uris.contains(track.uri));

  @override
  Future<Set<String>> excludedUris() async => const {};

  @override
  Future<Track?> getById(int id) async => null;

  @override
  Future<void> markUnavailable(Set<String> uris) async {}

  @override
  Future<void> setAvailability(Map<String, bool> availability) async {}
}

final class RecordingArtworkCache implements ArtworkCache {
  final List<String> deletedKeys = [];

  @override
  Future<void> clear() async {}

  @override
  Future<void> deleteByKey(String key) async => deletedKeys.add(key);
}

final class _PickedFilePicker implements AudioFilePicker {
  const _PickedFilePicker();

  @override
  Future<PickedAudioFile?> pickAudioFile() async => null;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => const [
    PickedAudioFile(path: 'content://document/audio/1', title: 'Recuperada'),
  ];
}

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker();

  @override
  Future<PickedAudioFile?> pickAudioFile() async => null;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => const [];
}

final class FakeAudioPlayerService implements AudioPlayerService {
  const FakeAudioPlayerService({this.onPlayQueue});

  final VoidCallback? onPlayQueue;

  @override
  Stream<AudioItem?> get currentItemStream => const Stream.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();

  @override
  Stream<AudioPlaybackState> get playbackStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<List<Track>> get queueStream => const Stream.empty();

  @override
  Stream<RepeatMode> get repeatModeStream => const Stream.empty();

  @override
  Stream<double> get volumeStream => const Stream.empty();

  @override
  Stream<bool> get shuffleEnabledStream => const Stream.empty();

  @override
  Future<void> addToQueue(Track track) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> loadFile({required String path, required String title}) async {}

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playNext(Track track) async {}

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    onPlayQueue?.call();
  }

  @override
  Future<void> previous() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> stop() async {}
}
