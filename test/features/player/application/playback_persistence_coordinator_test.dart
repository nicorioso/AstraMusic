import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/playback_state_repository.dart';
import 'package:astramusic/core/platform/track_availability.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/application/playback_persistence_coordinator.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agrupa cambios rápidos de cola con debounce', () {
    fakeAsync((async) {
      final player = _FakePlayer();
      final repository = _RecordingRepository();
      final coordinator = PlaybackPersistenceCoordinator(player, repository);
      coordinator.start();
      async.flushMicrotasks();

      player.emitQueue([_track(1)]);
      async.elapse(const Duration(milliseconds: 300));
      player.emitQueue([_track(1), _track(2)]);
      async.elapse(const Duration(milliseconds: 499));
      expect(repository.saves, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(repository.saves, hasLength(1));
      expect(repository.saves.single.queue.map((track) => track.id), [1, 2]);
      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test(
    'descarta la cola y el estado cuando todos los archivos faltan',
    () async {
      final player = _FakePlayer();
      final repository = _RecordingRepository(saved: _saved([1, 2], 1));
      final coordinator = PlaybackPersistenceCoordinator(
        player,
        repository,
        availabilityChecker: const _FakeAvailabilityChecker({}),
      );

      await coordinator.start();

      expect(player.loadedQueues, isEmpty);
      expect(repository.clearCount, 1);
    },
  );

  test('omite archivos faltantes y ajusta el índice restaurado', () async {
    final player = _FakePlayer();
    final repository = _RecordingRepository(saved: _saved([1, 2, 3], 2));
    final coordinator = PlaybackPersistenceCoordinator(
      player,
      repository,
      availabilityChecker: const _FakeAvailabilityChecker({
        'file:///track-2.mp3',
        'file:///track-3.mp3',
      }),
    );

    await coordinator.start();

    expect(player.loadedQueues.single.map((track) => track.id), [2, 3]);
    expect(player.skippedIndex, 1);
    expect(repository.clearCount, 0);
  });

  test('captura una excepción del servicio al cargar la cola', () async {
    final player = _FakePlayer(failOnLoad: true);
    final repository = _RecordingRepository(saved: _saved([1], 0));
    final coordinator = PlaybackPersistenceCoordinator(
      player,
      repository,
      availabilityChecker: const _FakeAvailabilityChecker({
        'file:///track-1.mp3',
      }),
    );

    await expectLater(coordinator.start(), completes);

    expect(repository.clearCount, 1);
    expect(player.clearCount, 1);
  });

  test('abandona y limpia una restauración que vence el tiempo', () async {
    final player = _FakePlayer(loadGate: Completer<void>());
    final repository = _RecordingRepository(saved: _saved([1], 0));
    final coordinator = PlaybackPersistenceCoordinator(
      player,
      repository,
      restoreTimeout: const Duration(milliseconds: 10),
      availabilityChecker: const _FakeAvailabilityChecker({
        'file:///track-1.mp3',
      }),
    );

    await coordinator.start();

    expect(repository.clearCount, 1);
    expect(player.clearCount, 1);
  });
}

PersistedPlaybackState _saved(List<int> ids, int currentIndex) {
  return PersistedPlaybackState(
    queue: [
      for (var position = 0; position < ids.length; position++)
        PersistedQueueItem(
          track: _track(ids[position]),
          position: position,
          originalPosition: position,
        ),
    ],
    currentIndex: currentIndex,
    position: const Duration(seconds: 12),
    shuffle: false,
    repeatMode: RepeatMode.off,
  );
}

Track _track(int id) => Track(
  id: id,
  uri: 'file:///track-$id.mp3',
  title: 'Canción $id',
  dateAdded: DateTime(2026),
);

final class _RecordingRepository implements PlaybackStateRepository {
  _RecordingRepository({this.saved});

  final PersistedPlaybackState? saved;
  final List<PlaybackStateSnapshot> saves = [];
  int clearCount = 0;

  @override
  Future<void> clear() async => clearCount++;

  @override
  Future<PersistedPlaybackState?> load() async => saved;

  @override
  Future<void> save(PlaybackStateSnapshot snapshot) async =>
      saves.add(snapshot);
}

final class _FakePlayer implements AudioPlayerService {
  _FakePlayer({this.failOnLoad = false, this.loadGate});

  final bool failOnLoad;
  final Completer<void>? loadGate;
  final _queue = StreamController<List<Track>>.broadcast(sync: true);
  final List<List<Track>> loadedQueues = [];
  int? skippedIndex;
  int clearCount = 0;

  void emitQueue(List<Track> queue) => _queue.add(queue);

  @override
  Stream<List<Track>> get queueStream => _queue.stream;
  @override
  Stream<AudioPlaybackState> get playbackStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioItem?> get currentItemStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<bool> get shuffleEnabledStream => const Stream.empty();
  @override
  Stream<RepeatMode> get repeatModeStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();
  @override
  Future<void> addToQueue(Track track) async {}
  @override
  Future<void> clearQueue() async => clearCount++;
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
    if (failOnLoad) throw StateError('falló la carga');
    await loadGate?.future;
    loadedQueues.add(List.of(tracks));
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
  Future<void> skipToIndex(int index) async => skippedIndex = index;
  @override
  Future<void> stop() async {}
}

final class _FakeAvailabilityChecker implements TrackAvailabilityChecker {
  const _FakeAvailabilityChecker(this.existing);

  final Set<String> existing;

  @override
  Future<Map<String, bool>> checkAll(Iterable<String> uris) async => {
    for (final uri in uris) uri: existing.contains(uri),
  };

  @override
  Future<bool> exists(String uri) async => existing.contains(uri);
}
