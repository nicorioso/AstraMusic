import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/playback_state_repository.dart';
import 'package:astramusic/core/platform/track_availability.dart';
import 'package:astramusic/features/library/domain/track.dart';

final class PlaybackPersistenceCoordinator {
  PlaybackPersistenceCoordinator(
    this._player,
    this._repository, {
    this.debounceDuration = const Duration(milliseconds: 500),
    this.positionInterval = const Duration(seconds: 5),
    this.restoreTimeout = const Duration(seconds: 5),
    this.availabilityChecker = const SystemTrackAvailabilityChecker(),
  });

  final AudioPlayerService _player;
  final PlaybackStateRepository _repository;
  final Duration debounceDuration;
  final Duration positionInterval;
  final Duration restoreTimeout;
  final TrackAvailabilityChecker availabilityChecker;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<Track> _queue = const [];
  List<Track> _originalQueue = const [];
  int? _currentIndex;
  Duration _position = Duration.zero;
  bool _shuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  AudioPlaybackStatus _status = AudioPlaybackStatus.idle;
  Timer? _debounce;
  Timer? _positionTimer;
  Future<void> _writeChain = Future.value();
  bool _restoring = false;
  bool _started = false;
  int _restoreGeneration = 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _restoring = true;
    _listen();
    final generation = ++_restoreGeneration;
    try {
      await _restore(generation).timeout(restoreTimeout);
    } catch (_) {
      _restoreGeneration++;
      await _discardRestore();
    } finally {
      _restoring = false;
    }
  }

  Future<void> _restore(int generation) async {
    final saved = await _repository.load();
    if (!_isCurrentRestore(generation) || saved == null) return;
    final availableItems = <PersistedQueueItem>[];
    for (final item in saved.queue) {
      if (await availabilityChecker.exists(item.track.uri)) {
        availableItems.add(
          PersistedQueueItem(
            track: item.track.withAvailability(true),
            position: item.position,
            originalPosition: item.originalPosition,
          ),
        );
      }
      if (!_isCurrentRestore(generation)) return;
    }
    if (availableItems.isEmpty) {
      await _discardRestore();
      return;
    }
    final playback = availableItems.map((item) => item.track).toList();
    final original = [...availableItems]
      ..sort(
        (a, b) => (a.originalPosition ?? a.position).compareTo(
          b.originalPosition ?? b.position,
        ),
      );
    final originalTracks = original.map((item) => item.track).toList();
    final savedIndex = saved.currentIndex ?? 0;
    final index = availableItems
        .where((item) => item.position < savedIndex)
        .length
        .clamp(0, playback.length - 1);
    await _player.playQueue(originalTracks, startIndex: 0);
    if (!_isCurrentRestore(generation)) return;
    if (saved.shuffle) {
      await _player.setShuffle(true);
      await _reorderTo(playback);
    }
    await _player.setRepeatMode(saved.repeatMode);
    await _player.skipToIndex(index);
    await _player.seek(saved.position);
    await _player.pause();
    if (!_isCurrentRestore(generation)) return;
    _queue = playback;
    _originalQueue = originalTracks;
    _currentIndex = index;
    _position = saved.position;
    _shuffle = saved.shuffle;
    _repeatMode = saved.repeatMode;
    _status = AudioPlaybackStatus.paused;
  }

  bool _isCurrentRestore(int generation) =>
      _restoring && generation == _restoreGeneration;

  Future<void> _discardRestore() async {
    try {
      await _repository.clear();
    } catch (_) {}
    try {
      await _player.clearQueue();
    } catch (_) {}
    _queue = const [];
    _originalQueue = const [];
    _currentIndex = null;
    _position = Duration.zero;
    _shuffle = false;
    _repeatMode = RepeatMode.off;
    _status = AudioPlaybackStatus.idle;
  }

  Future<void> _reorderTo(List<Track> target) async {
    final current = _player is OriginalQueueProvider
        ? List<Track>.of((_player as OriginalQueueProvider).playbackQueue)
        : <Track>[];
    // Tras activar aleatorio la cola emitida es la fuente confiable. Si el
    // servicio no expone orden original, los movimientos posteriores igual
    // convergen usando los ids esperados desde la cola cargada.
    if (current.isEmpty) current.addAll(target);
    for (var index = 0; index < target.length; index++) {
      final found = current.indexWhere(
        (track) => track.id == target[index].id,
        index,
      );
      if (found < 0 || found == index) continue;
      await _player.moveInQueue(found, index);
      current.insert(index, current.removeAt(found));
    }
  }

  void _listen() {
    _subscriptions.addAll([
      _player.queueStream.listen((queue) {
        _queue = queue;
        if (!_shuffle) _originalQueue = queue;
        _scheduleSave();
      }),
      _player.currentIndexStream.listen((index) {
        _currentIndex = index;
        _scheduleSave();
      }),
      _player.positionStream.listen((position) => _position = position),
      _player.shuffleEnabledStream.listen((shuffle) {
        _shuffle = shuffle;
        _scheduleSave();
      }),
      _player.repeatModeStream.listen((mode) {
        _repeatMode = mode;
        _scheduleSave();
      }),
      _player.playbackStateStream.listen((state) {
        final wasPlaying = _status == AudioPlaybackStatus.playing;
        _status = state.status;
        if (state.status == AudioPlaybackStatus.playing) {
          _positionTimer ??= Timer.periodic(positionInterval, (_) => _save());
        } else {
          _positionTimer?.cancel();
          _positionTimer = null;
          if (wasPlaying || state.status == AudioPlaybackStatus.paused) _save();
        }
      }),
    ]);
  }

  void _scheduleSave() {
    if (_restoring) return;
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, _save);
  }

  void _save() {
    if (_restoring) return;
    final original = _player is OriginalQueueProvider
        ? (_player as OriginalQueueProvider).originalQueue
        : _originalQueue;
    final snapshot = PlaybackStateSnapshot(
      queue: List.of(_queue),
      originalQueue: List.of(original),
      currentIndex: _currentIndex,
      position: _position,
      shuffle: _shuffle,
      repeatMode: _repeatMode,
    );
    _writeChain = _writeChain
        .then((_) => _repository.save(snapshot))
        .catchError((_) {});
  }

  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    _save();
    await _writeChain;
  }

  Future<void> dispose() async {
    await flush();
    _positionTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
