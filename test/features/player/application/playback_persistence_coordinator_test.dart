import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/playback_state_repository.dart';
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
}

Track _track(int id) => Track(
  id: id,
  uri: 'file:///track-$id.mp3',
  title: 'Canción $id',
  dateAdded: DateTime(2026),
);

final class _RecordingRepository implements PlaybackStateRepository {
  final List<PlaybackStateSnapshot> saves = [];

  @override
  Future<PersistedPlaybackState?> load() async => null;

  @override
  Future<void> save(PlaybackStateSnapshot snapshot) async =>
      saves.add(snapshot);
}

final class _FakePlayer implements AudioPlayerService {
  final _queue = StreamController<List<Track>>.broadcast(sync: true);

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
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();
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
