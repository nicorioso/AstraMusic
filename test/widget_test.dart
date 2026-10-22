import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:flutter/material.dart';
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

    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.text('cancion'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

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

    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('Formato no compatible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
    child: const MaterialApp(home: PlayerScreen()),
  );
}

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker(this.file);

  final PickedAudioFile? file;

  @override
  Future<PickedAudioFile?> pickAudioFile() async => file;
}

final class FakeAudioPlayerService implements AudioPlayerService {
  FakeAudioPlayerService({this.failOnLoad = false});

  final bool failOnLoad;
  final _playbackStateController =
      StreamController<AudioPlaybackState>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _durationController = StreamController<Duration?>.broadcast(sync: true);
  final _currentItemController = StreamController<AudioItem?>.broadcast(
    sync: true,
  );

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
    _durationController.add(duration);
    _positionController.add(Duration.zero);
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

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
    ]);
  }
}
