import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('elige un archivo y alterna entre reproducción y pausa', (
    tester,
  ) async {
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.text('cancion'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('play-pause-button')));
    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();

    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('muestra un error de carga sin lanzar una excepción', (
    tester,
  ) async {
    final service = FakeAudioPlayerService(failOnLoad: true);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/invalido.xyz', title: 'invalido'),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('Formato no compatible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alterna aleatorio, repetir y resalta la canción en la cola', (
    tester,
  ) async {
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('shuffle-button')));
    await tester.tap(find.byKey(const Key('shuffle-button')));
    await tester.pump();
    expect(find.byIcon(Icons.shuffle_on), findsOneWidget);

    await tester.tap(find.byKey(const Key('repeat-button')));
    await tester.pump();
    expect(find.text('Repetir: toda la cola'), findsOneWidget);
    await tester.tap(find.byKey(const Key('repeat-button')));
    await tester.pump();
    expect(find.text('Repetir: una canción'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-queue-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('current-queue-item')), findsOneWidget);
    expect(find.text('cancion'), findsOneWidget);
  });

  testWidgets('un fallo de aleatorio no deshabilita los controles', (
    tester,
  ) async {
    final service = FakeAudioPlayerService(failOnShuffle: true);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('shuffle-button')));
    await tester.tap(find.byKey(const Key('shuffle-button')));
    await tester.pump();

    expect(
      find.text('No fue posible cambiar el modo aleatorio.'),
      findsOneWidget,
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key('next-button'))).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('previous-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('repeat-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('la pantalla del reproductor no desborda en tamaño compacto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(
            path: 'file:///tmp/cancion.mp3',
            title: 'Título extremadamente largo para una pantalla compacta',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play-pause-button')), findsOneWidget);
  });

  for (final size in const [Size(360, 800), Size(1200, 800)]) {
    testWidgets('reproductor y cola no desbordan a ${size.width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeAudioPlayerService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        _testApp(
          service: service,
          picker: const FakeAudioFilePicker(
            PickedAudioFile(
              path: 'file:///tmp/星間の非常に長い曲名.mp3',
              title: '星間の非常に長い曲名とコロンビアの夜空',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
      await tester.tap(find.byKey(const Key('choose-audio-button')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('open-queue-button')));
      await tester.pumpAndSettle();
      expect(find.byType(QueueScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _testApp({
  required AudioPlayerService service,
  required AudioFilePicker picker,
}) {
  return ProviderScope(
    overrides: [
      audioPlayerServiceProvider.overrideWithValue(service),
      audioFilePickerProvider.overrideWithValue(picker),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      home: const PlayerScreen(),
    ),
  );
}

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker(this.file);

  final PickedAudioFile? file;

  @override
  Future<PickedAudioFile?> pickAudioFile() async => file;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => [?file];
}

final class FakeAudioPlayerService implements AudioPlayerService {
  FakeAudioPlayerService({this.failOnLoad = false, this.failOnShuffle = false});

  final bool failOnLoad;
  final bool failOnShuffle;
  final _playbackStateController =
      StreamController<AudioPlaybackState>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _durationController = StreamController<Duration?>.broadcast(sync: true);
  final _currentItemController = StreamController<AudioItem?>.broadcast(
    sync: true,
  );
  final _queueController = StreamController<List<Track>>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);
  final _shuffleController = StreamController<bool>.broadcast(sync: true);
  final _repeatController = StreamController<RepeatMode>.broadcast(sync: true);

  @override
  Stream<AudioPlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioItem?> get currentItemStream => _currentItemController.stream;

  @override
  Stream<int?> get currentIndexStream => _indexController.stream;

  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();

  @override
  Stream<List<Track>> get queueStream => _queueController.stream;

  @override
  Stream<RepeatMode> get repeatModeStream => _repeatController.stream;

  @override
  Stream<bool> get shuffleEnabledStream => _shuffleController.stream;

  @override
  Future<void> loadFile({required String path, required String title}) async {
    if (failOnLoad) {
      _playbackStateController.add(
        const AudioPlaybackState(
          AudioPlaybackStatus.error,
          errorMessage: 'Formato no compatible',
        ),
      );
      return;
    }

    const duration = Duration(minutes: 3);
    _currentItemController.add(
      AudioItem(path: path, title: title, duration: duration),
    );
    _queueController.add([
      Track(
        uri: path,
        title: title,
        duration: duration,
        dateAdded: DateTime(2026),
      ),
    ]);
    _indexController.add(0);
    _durationController.add(duration);
    _positionController.add(Duration.zero);
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    final track = tracks[startIndex];
    _queueController.add(List.unmodifiable(tracks));
    _indexController.add(startIndex);
    _currentItemController.add(
      AudioItem(
        path: track.uri,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        trackId: track.id,
      ),
    );
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> addToQueue(Track track) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> playNext(Track track) async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _repeatController.add(mode);
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    if (failOnShuffle) {
      throw const AudioPlayerException(
        'No fue posible cambiar el modo aleatorio.',
      );
    }
    _shuffleController.add(enabled);
  }

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> play() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.playing),
    );
  }

  @override
  Future<void> pause() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> stop() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await Future.wait([
      _playbackStateController.close(),
      _positionController.close(),
      _durationController.close(),
      _currentItemController.close(),
      _queueController.close(),
      _indexController.close(),
      _shuffleController.close(),
      _repeatController.close(),
    ]);
  }
}
