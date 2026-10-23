import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/domain/queue_rules.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QueueFakeAudioPlayerService service;
  late FakeTrackRepository repository;
  late ProviderContainer container;

  setUp(() async {
    service = QueueFakeAudioPlayerService();
    repository = FakeTrackRepository();
    container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(service),
        trackRepositoryProvider.overrideWithValue(repository),
      ],
    );
    container.read(playerControllerProvider);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    container.dispose();
    await service.dispose();
  });

  test('playQueue conserva el índice inicial solicitado', () async {
    final tracks = _tracks(3);

    await container
        .read(playerControllerProvider.notifier)
        .playQueue(tracks, startIndex: 1);

    final state = container.read(playerControllerProvider);
    expect(state.queue, tracks);
    expect(state.currentIndex, 1);
    expect(state.currentItem?.title, 'Canción 2');
    expect(state.isPlaying, isTrue);
  });

  test('next y previous respetan límites y repetición', () async {
    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue(_tracks(3), startIndex: 2);

    await controller.next();
    expect(container.read(playerControllerProvider).currentIndex, 2);

    await controller.cycleRepeatMode();
    await controller.next();
    expect(container.read(playerControllerProvider).currentIndex, 0);

    await controller.previous();
    expect(container.read(playerControllerProvider).currentIndex, 2);

    await controller.cycleRepeatMode();
    await controller.next();
    expect(container.read(playerControllerProvider).currentIndex, 2);
  });

  test(
    'un fallo marca la canción y el handler falso salta a la siguiente',
    () async {
      final controller = container.read(playerControllerProvider.notifier);
      await controller.playQueue(_tracks(3), startIndex: 0);

      service.failCurrent('Archivo borrado');
      await Future<void>.delayed(Duration.zero);

      expect(repository.unavailableUris, {'file:///track-1.mp3'});
      expect(container.read(playerControllerProvider).currentIndex, 1);
      expect(
        container.read(playerControllerProvider).errorMessage,
        'Archivo borrado',
      );
    },
  );

  test(
    'un error no fatal conserva el estado y se limpia al continuar',
    () async {
      final controller = container.read(playerControllerProvider.notifier);
      await controller.playQueue(_tracks(3));
      service.failShuffle = true;

      await controller.toggleShuffle();

      var state = container.read(playerControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.errorMessage, 'Fallo auxiliar de aleatorio');

      await controller.next();
      state = container.read(playerControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.errorMessage, isNull);
    },
  );
}

List<Track> _tracks(int count) => List.generate(
  count,
  (index) => Track(
    id: index + 1,
    uri: 'file:///track-${index + 1}.mp3',
    title: 'Canción ${index + 1}',
    dateAdded: DateTime(2026),
  ),
);

final class QueueFakeAudioPlayerService implements AudioPlayerService {
  final _playback = StreamController<AudioPlaybackState>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);
  final _item = StreamController<AudioItem?>.broadcast(sync: true);
  final _queue = StreamController<List<Track>>.broadcast(sync: true);
  final _index = StreamController<int?>.broadcast(sync: true);
  final _shuffle = StreamController<bool>.broadcast(sync: true);
  final _repeat = StreamController<RepeatMode>.broadcast(sync: true);
  final _failure = StreamController<AudioPlaybackFailure>.broadcast(sync: true);

  List<Track> tracks = [];
  int? currentIndex;
  RepeatMode repeatMode = RepeatMode.off;
  bool failShuffle = false;

  @override
  Stream<AudioPlaybackState> get playbackStateStream => _playback.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<AudioItem?> get currentItemStream => _item.stream;
  @override
  Stream<List<Track>> get queueStream => _queue.stream;
  @override
  Stream<int?> get currentIndexStream => _index.stream;
  @override
  Stream<bool> get shuffleEnabledStream => _shuffle.stream;
  @override
  Stream<RepeatMode> get repeatModeStream => _repeat.stream;
  @override
  Stream<AudioPlaybackFailure> get failureStream => _failure.stream;

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    this.tracks = List.of(tracks);
    currentIndex = startIndex;
    _emitQueue();
  }

  @override
  Future<void> loadFile({required String path, required String title}) =>
      playQueue([Track(uri: path, title: title, dateAdded: DateTime(2026))]);

  @override
  Future<void> play() async {
    _playback.add(const AudioPlaybackState(AudioPlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    _playback.add(const AudioPlaybackState(AudioPlaybackStatus.paused));
  }

  @override
  Future<void> stop() => pause();

  @override
  Future<void> seek(Duration position) async => _position.add(position);

  @override
  Future<void> next() => _move(1);

  @override
  Future<void> previous() => _move(-1);

  Future<void> _move(int offset) async {
    final target = relativeIndex(
      currentIndex: currentIndex,
      queueLength: tracks.length,
      offset: offset,
      repeatMode: repeatMode,
    );
    if (target == null) return;
    currentIndex = target;
    _emitCurrent();
  }

  @override
  Future<void> skipToIndex(int index) async {
    currentIndex = index;
    _emitCurrent();
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    if (failShuffle) {
      throw const AudioPlayerException('Fallo auxiliar de aleatorio');
    }
    _shuffle.add(enabled);
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    repeatMode = mode;
    _repeat.add(mode);
  }

  @override
  Future<void> addToQueue(Track track) async {
    tracks.add(track);
    _queue.add(List.unmodifiable(tracks));
  }

  @override
  Future<void> playNext(Track track) async {
    tracks.insert((currentIndex ?? -1) + 1, track);
    _queue.add(List.unmodifiable(tracks));
  }

  @override
  Future<void> removeFromQueue(int index) async {
    tracks.removeAt(index);
    currentIndex = indexAfterRemoval(
      currentIndex: currentIndex,
      removedIndex: index,
      newLength: tracks.length,
    );
    _emitQueue();
  }

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, moved);
    currentIndex = indexAfterMove(
      currentIndex: currentIndex,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    _emitQueue();
  }

  @override
  Future<void> clearQueue() async {
    tracks.clear();
    currentIndex = null;
    _queue.add(const []);
    _index.add(null);
    _item.add(null);
  }

  void failCurrent(String message) {
    final failed = tracks[currentIndex!];
    _failure.add(AudioPlaybackFailure(track: failed, message: message));
    final target = nextUnfailedIndex(
      currentIndex: currentIndex!,
      effectiveIndices: List.generate(tracks.length, (index) => index),
      failedIndices: {currentIndex!},
    );
    if (target != null) {
      currentIndex = target;
      _emitCurrent();
    }
  }

  void _emitQueue() {
    _queue.add(List.unmodifiable(tracks));
    _emitCurrent();
  }

  void _emitCurrent() {
    _index.add(currentIndex);
    final current = currentIndex;
    if (current == null) {
      _item.add(null);
      return;
    }
    final track = tracks[current];
    _item.add(
      AudioItem(
        path: track.uri,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        trackId: track.id,
      ),
    );
  }

  Future<void> dispose() => Future.wait([
    _playback.close(),
    _position.close(),
    _duration.close(),
    _item.close(),
    _queue.close(),
    _index.close(),
    _shuffle.close(),
    _repeat.close(),
    _failure.close(),
  ]);
}

final class FakeTrackRepository implements TrackRepository {
  final Set<String> unavailableUris = {};

  @override
  Future<void> markUnavailable(Set<String> uris) async {
    unavailableUris.addAll(uris);
  }

  @override
  Future<int> count() async => 0;
  @override
  Future<void> deleteAll() async {}
  @override
  Future<void> deleteByUris(Set<String> uris) async {}
  @override
  Future<Track?> getById(int id) async => null;
  @override
  Future<void> upsertAll(List<Track> tracks) async {}
  @override
  Stream<List<Track>> watchAll() => const Stream.empty();
  @override
  Stream<List<Track>> watchSearch(String query) => const Stream.empty();
}
