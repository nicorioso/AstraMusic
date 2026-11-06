import 'dart:async';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/data/audio_handler_player_service.dart';
import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:astramusic/features/player/data/queue_load_strategy.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serializa controles externos detrás de una carga en curso', () async {
    final player = _RecordingAudioPlayer();
    final strategy = _BlockingQueueLoadStrategy();
    final handler = AstraAudioHandler(
      player: player,
      queueLoadStrategy: strategy,
    );
    addTearDown(() async {
      await handler.dispose();
      await player.closeTestStreams();
    });

    final load = handler.loadQueue(const [MediaItem(id: 'uno', title: 'Uno')]);
    await strategy.started.future;
    final pause = handler.pause();
    await Future<void>.delayed(Duration.zero);

    expect(player.pauseCalls, 0);

    strategy.release.complete();
    await Future.wait([load, pause]);
    expect(player.pauseCalls, 1);
  });

  test(
    'serializa fallos del reproductor detrás de la mutación activa',
    () async {
      final player = _RecordingAudioPlayer();
      final strategy = _BlockingQueueLoadStrategy();
      final handler = AstraAudioHandler(
        player: player,
        queueLoadStrategy: strategy,
      );
      addTearDown(() async {
        await handler.dispose();
        await player.closeTestStreams();
      });

      final load = handler.loadQueue(const [
        MediaItem(id: 'uno', title: 'Uno'),
      ]);
      await strategy.started.future;
      player.emitPlayerError(PlayerException(1, 'archivo dañado', 0));
      await Future<void>.delayed(Duration.zero);

      expect(player.pauseCalls, 0);

      strategy.release.complete();
      await load;
      await Future<void>.delayed(Duration.zero);
      expect(player.pauseCalls, 1);
    },
  );

  test('onTaskRemoved detiene audio y conserva el handler utilizable', () async {
    final player = _RecordingAudioPlayer();
    final handler = AstraAudioHandler(player: player);
    addTearDown(() async {
      await handler.dispose();
      await player.closeTestStreams();
    });

    await handler.onTaskRemoved();

    expect(player.stopCalls, 1);
    expect(player.disposeCalls, 0);
    await handler.pause();
    expect(player.pauseCalls, 1);
  });

  test('el servicio cancela carátulas pendientes al desmontarse', () async {
    final player = _RecordingAudioPlayer();
    final handler = AstraAudioHandler(player: player);
    final artwork = _BlockingArtworkProvider();
    final service = AudioHandlerPlayerService(
      handler,
      artworkProvider: artwork,
    );
    addTearDown(player.closeTestStreams);

    handler.mediaItem.add(const MediaItem(id: 'uno', title: 'Uno'));
    await artwork.started.future;
    await service.dispose();
    handler.mediaItem.add(const MediaItem(id: 'dos', title: 'Dos'));
    artwork.release.complete('/ruta/que/no-debe-aplicarse.jpg');
    await Future<void>.delayed(Duration.zero);

    expect(artwork.calls, 1);
    expect(player.disposeCalls, 1);
  });
}

final class _BlockingArtworkProvider implements ArtworkProvider {
  final started = Completer<void>();
  final release = Completer<String?>();
  int calls = 0;

  @override
  Future<String?> artworkFor(Track track, {required int size}) {
    calls++;
    started.complete();
    return release.future;
  }
}

final class _BlockingQueueLoadStrategy implements QueueLoadStrategy {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Duration?> load(
    AudioPlayer player,
    List<AudioSource> sources, {
    required int startIndex,
    required Duration initialPosition,
  }) async {
    started.complete();
    await release.future;
    return null;
  }
}

final class _RecordingAudioPlayer extends AudioPlayer {
  _RecordingAudioPlayer();

  final _playbackEvents = StreamController<PlaybackEvent>.broadcast(sync: true);
  final _errors = StreamController<PlayerException>.broadcast(sync: true);
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEvents.stream;

  @override
  Stream<PlayerException> get errorStream => _errors.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream.empty();

  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();

  @override
  Stream<double> get speedStream => const Stream.empty();

  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();

  @override
  double get speed => 1;

  @override
  bool get playing => false;

  @override
  int? get currentIndex => 0;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  ProcessingState get processingState => ProcessingState.idle;

  @override
  PlaybackEvent get playbackEvent => PlaybackEvent(currentIndex: 0);

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void emitPlayerError(PlayerException error) => _errors.add(error);

  Future<void> closeTestStreams() async {
    await _playbackEvents.close();
    await _errors.close();
  }
}
