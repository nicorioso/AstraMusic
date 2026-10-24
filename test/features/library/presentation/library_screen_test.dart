import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/media_library_permission.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/library_screen.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el estado vacío de la biblioteca', (tester) async {
    await tester.pumpWidget(_testApp(const FakeTrackRepository([])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty-library-message')), findsOneWidget);
    expect(find.byKey(const Key('scan-library-button')), findsOneWidget);
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

  testWidgets('muestra progreso y resumen del escaneo', (tester) async {
    final scanner = ControlledLibraryScanner();
    await tester.pumpWidget(
      _testApp(const FakeTrackRepository([]), scanner: scanner),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-library-button')));
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

    await tester.tap(find.byKey(const Key('scan-library-button')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(find.text('Cancelando...'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const Key('scan-library-button')),
          )
          .onPressed,
      isNull,
    );

    scanner.completeCancellation();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-progress')), findsNothing);
  });
}

Widget _testApp(TrackRepository repository, {LibraryScanner? scanner}) {
  return ProviderScope(
    overrides: [
      trackRepositoryProvider.overrideWithValue(repository),
      isAndroidPlatformProvider.overrideWithValue(true),
      libraryScannerProvider.overrideWithValue(
        scanner ?? ControlledLibraryScanner(),
      ),
      mediaLibraryPermissionProvider.overrideWithValue(
        const FakeMediaLibraryPermission(),
      ),
      audioPlayerServiceProvider.overrideWithValue(
        const FakeAudioPlayerService(),
      ),
      audioFilePickerProvider.overrideWithValue(const FakeAudioFilePicker()),
    ],
    child: const MaterialApp(home: LibraryScreen()),
  );
}

final class ControlledLibraryScanner implements LibraryScanner {
  StreamController<ScanEvent>? _controller;
  Completer<void>? _cancellationGate;

  @override
  Future<LibraryScanTask> startScan({
    String? rootPath,
    Map<String, KnownFileStats> knownFiles = const {},
  }) async {
    final controller = StreamController<ScanEvent>();
    _controller = controller;
    return LibraryScanTask(controller.stream, () async {
      await _cancellationGate?.future;
      if (!controller.isClosed) {
        controller.add(const ScanCancelled());
        await controller.close();
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
  Future<Track?> getById(int id) async {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  Future<void> markUnavailable(Set<String> uris) async {}

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

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker();

  @override
  Future<PickedAudioFile?> pickAudioFile() async => null;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => const [];
}

final class FakeAudioPlayerService implements AudioPlayerService {
  const FakeAudioPlayerService();

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
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> stop() async {}
}
