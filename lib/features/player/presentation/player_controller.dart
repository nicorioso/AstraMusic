import 'dart:async';
import 'dart:math';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  throw StateError('AudioPlayerService debe configurarse en ProviderScope.');
});

final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => const SystemAudioFilePicker(),
);

final notificationPermissionGrantedProvider = Provider<bool>((ref) => true);

final appForegroundProvider = NotifierProvider<AppForegroundController, bool>(
  AppForegroundController.new,
);

class AppForegroundController extends Notifier<bool> {
  @override
  bool build() => true;

  void setForeground(bool foreground) => state = foreground;
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerViewState>(PlayerController.new);

class PlayerViewState {
  const PlayerViewState({
    this.status = AudioPlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration,
    this.currentItem,
    this.queue = const [],
    this.recentlyPlayed = const [],
    this.canUndoQueue = false,
    this.currentIndex,
    this.shuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.volume = 1,
    this.errorMessage,
    this.notificationWarning = false,
  });

  final AudioPlaybackStatus status;
  final Duration position;
  final Duration? duration;
  final AudioItem? currentItem;
  final List<Track> queue;
  final List<Track> recentlyPlayed;
  final bool canUndoQueue;
  final int? currentIndex;
  final bool shuffleEnabled;
  final RepeatMode repeatMode;
  final double volume;
  final String? errorMessage;
  final bool notificationWarning;

  bool get isPlaying => status == AudioPlaybackStatus.playing;
  bool get isLoading => status == AudioPlaybackStatus.loading;

  PlayerViewState copyWith({
    AudioPlaybackStatus? status,
    Duration? position,
    Object? duration = _notProvided,
    Object? currentItem = _notProvided,
    List<Track>? queue,
    List<Track>? recentlyPlayed,
    bool? canUndoQueue,
    Object? currentIndex = _notProvided,
    bool? shuffleEnabled,
    RepeatMode? repeatMode,
    double? volume,
    Object? errorMessage = _notProvided,
    bool? notificationWarning,
  }) {
    return PlayerViewState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration == _notProvided
          ? this.duration
          : duration as Duration?,
      currentItem: currentItem == _notProvided
          ? this.currentItem
          : currentItem as AudioItem?,
      queue: queue ?? this.queue,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      canUndoQueue: canUndoQueue ?? this.canUndoQueue,
      currentIndex: currentIndex == _notProvided
          ? this.currentIndex
          : currentIndex as int?,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      volume: volume ?? this.volume,
      errorMessage: errorMessage == _notProvided
          ? this.errorMessage
          : errorMessage as String?,
      notificationWarning: notificationWarning ?? this.notificationWarning,
    );
  }

  static const _notProvided = Object();
}

sealed class QueueChange {
  const QueueChange();
}

final class QueueMove extends QueueChange {
  const QueueMove(this.from, this.to);
  final int from;
  final int to;
}

final class QueueRemoval extends QueueChange {
  const QueueRemoval(this.removedIndex);
  final int removedIndex;
}

final class QueueClear extends QueueChange {
  const QueueClear();
}

class PlayerController extends Notifier<PlayerViewState> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  // Se cancela en _pausePositionUpdates al pausar lifecycle o disponer.
  // ignore: cancel_subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  bool _isListening = false;
  int? _recordedTrackId;
  Duration? _lastPosition;
  bool _replacingQueue = false;
  bool _recordCheckScheduled = false;
  List<Track>? _queueBeforeChange;
  int? _indexBeforeChange;
  String? _lastRecentUri;
  QueueChange? _lastQueueChange;
  Duration _positionBeforeChange = Duration.zero;
  bool _wasPlayingBeforeChange = false;
  bool _shuffleBeforeChange = false;

  AudioPlayerService get _service => ref.read(audioPlayerServiceProvider);

  @override
  PlayerViewState build() {
    final notificationPermissionGranted = ref.watch(
      notificationPermissionGrantedProvider,
    );
    ref.onDispose(_disposeSubscriptions);
    final lifecycleSubscription = ref.listen(appForegroundProvider, (
      _,
      foreground,
    ) {
      if (foreground) {
        _resumePositionUpdates();
      } else {
        _pausePositionUpdates();
      }
    });
    ref.onDispose(lifecycleSubscription.close);
    Future.microtask(_startListening);

    return PlayerViewState(notificationWarning: !notificationPermissionGranted);
  }

  Future<void> chooseFile() async {
    _startListening();
    state = state.copyWith(errorMessage: null);

    try {
      final file = await ref.read(audioFilePickerProvider).pickAudioFile();
      if (file == null || !ref.mounted) return;

      state = state.copyWith(
        currentItem: AudioItem(path: file.path, title: file.title),
        position: Duration.zero,
        duration: null,
      );
      await _service.loadFile(path: file.path, title: file.title);
    } catch (error) {
      _setFatalError(error);
    }
  }

  Future<bool> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    _startListening();
    final available = tracks.where((track) => track.isAvailable).toList();
    if (available.isEmpty) {
      _setFatalError(
        const AudioPlayerException(
          'No hay canciones disponibles para reproducir.',
        ),
      );
      return false;
    }

    var availableStartIndex = 0;
    if (shuffle) {
      availableStartIndex = Random().nextInt(available.length);
    } else if (startIndex >= 0 && startIndex < tracks.length) {
      final selectedUri = tracks[startIndex].uri;
      final mapped = available.indexWhere((track) => track.uri == selectedUri);
      if (mapped >= 0) availableStartIndex = mapped;
    }

    state = state.copyWith(errorMessage: null);
    _replacingQueue = true;
    var started = false;
    try {
      await _service.playQueue(available, startIndex: availableStartIndex);
      try {
        await _service.setShuffle(shuffle);
      } catch (error) {
        _setNonFatalError(error);
      }
      await _service.play();
      // Una cola nueva inicia otra reproducción, aunque empiece en la misma pista.
      _recordedTrackId = null;
      started = true;
    } catch (error) {
      _setFatalError(error);
    } finally {
      _replacingQueue = false;
      if (started) _recordCurrentTrackNow();
    }
    return started;
  }

  Future<void> togglePlayback() => _run(() async {
    if (state.currentItem == null || state.isLoading) return;
    if (state.isPlaying) {
      await _service.pause();
    } else {
      await _service.play();
    }
  });

  Future<void> seek(Duration position) => _run(() => _service.seek(position));

  Future<void> next() => _run(_service.next);

  Future<void> previous() => _run(_service.previous);

  Future<void> skipToIndex(int index) =>
      _run(() => _service.skipToIndex(index));

  Future<void> toggleShuffle() =>
      _run(() => _service.setShuffle(!state.shuffleEnabled));

  Future<void> cycleRepeatMode() => _run(() {
    final next = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    return _service.setRepeatMode(next);
  });

  Future<void> setVolume(double volume) =>
      _run(() => _service.setVolume(volume.clamp(0.0, 1.0)));

  Future<void> addToQueue(Track track) =>
      _run(() => _service.addToQueue(track));

  Future<void> playNext(Track track) => _run(() => _service.playNext(track));

  void _rememberQueue(QueueChange change) {
    _lastQueueChange = change;
    _positionBeforeChange = state.position;
    _wasPlayingBeforeChange = state.isPlaying;
    _shuffleBeforeChange = state.shuffleEnabled;
    _queueBeforeChange = List.of(state.queue);
    _indexBeforeChange = state.currentIndex;
    state = state.copyWith(canUndoQueue: true);
  }

  Future<void> undoQueueChange() async {
    final previous = _queueBeforeChange;
    final change = _lastQueueChange;
    if (previous == null || change == null) return;
    final index = _indexBeforeChange;
    _queueBeforeChange = null;
    _lastQueueChange = null;
    state = state.copyWith(canUndoQueue: false);
    switch (change) {
      case QueueMove(:final from, :final to):
        await _run(() => _service.moveInQueue(to, from));
      case QueueRemoval(:final removedIndex):
        if (removedIndex >= previous.length) return;
        await _run(() async {
          await _service.addToQueue(previous[removedIndex]);
          await _service.moveInQueue(previous.length - 1, removedIndex);
        });
      case QueueClear():
        if (previous.isEmpty) return;
        final started = await playQueue(
          previous,
          startIndex: (index ?? 0).clamp(0, previous.length - 1),
          shuffle: _shuffleBeforeChange,
        );
        if (started) {
          await seek(_positionBeforeChange);
          if (!_wasPlayingBeforeChange) await _run(_service.pause);
        }
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    _rememberQueue(QueueRemoval(index));
    await _run(() => _service.removeFromQueue(index));
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex >= state.queue.length ||
        oldIndex == newIndex) {
      return;
    }
    _rememberQueue(QueueMove(oldIndex, newIndex));
    await _run(() => _service.moveInQueue(oldIndex, newIndex));
  }

  Future<void> clearQueue() async {
    if (state.queue.isEmpty) return;
    _rememberQueue(const QueueClear());
    await _run(_service.clearQueue);
  }

  Future<void> stopAndClearQueue() => _run(() async {
    await _service.stop();
    await _service.clearQueue();
  });

  Future<void> removeTrackFromQueue(String uri) async {
    final indices = <int>[
      for (var index = 0; index < state.queue.length; index++)
        if (state.queue[index].uri == uri) index,
    ];
    for (final index in indices.reversed) {
      await _service.removeFromQueue(index);
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  void _recordRecentTrack() {
    final item = state.currentItem;
    final index = state.currentIndex;
    if (item == null ||
        index == null ||
        index < 0 ||
        index >= state.queue.length) {
      return;
    }
    final track = state.queue[index];
    if (track.uri != item.path || _lastRecentUri == track.uri) return;
    _lastRecentUri = track.uri;
    state = state.copyWith(
      recentlyPlayed: [track, ...state.recentlyPlayed].take(10).toList(),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    _startListening();
    try {
      await action();
      if (ref.mounted) state = state.copyWith(errorMessage: null);
    } catch (error) {
      _setNonFatalError(error);
    }
  }

  void _startListening() {
    if (_isListening || !ref.mounted) return;
    _isListening = true;

    _subscribe(_service.playbackStateStream, (playbackState) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: playbackState.status,
        errorMessage: playbackState.errorMessage ?? state.errorMessage,
      );
      if (playbackState.status == AudioPlaybackStatus.idle) {
        _recordedTrackId = null;
      }
      _recordCurrentTrack();
    });
    if (ref.read(appForegroundProvider)) _resumePositionUpdates();
    _subscribe(_service.durationStream, (duration) {
      if (ref.mounted) state = state.copyWith(duration: duration);
    });
    _subscribe(_service.currentItemStream, (item) {
      if (!ref.mounted) return;
      state = state.copyWith(
        currentItem: item,
        duration: item?.duration ?? state.duration,
      );
      _recordRecentTrack();
    });
    _subscribe(_service.queueStream, (queue) {
      if (ref.mounted) {
        state = state.copyWith(queue: queue);
        _recordCurrentTrack();
        _recordRecentTrack();
      }
    });
    _subscribe(_service.currentIndexStream, (index) {
      if (ref.mounted) {
        state = state.copyWith(currentIndex: index);
        _recordCurrentTrack();
        _recordRecentTrack();
      }
    });
    _subscribe(_service.shuffleEnabledStream, (enabled) {
      if (ref.mounted) state = state.copyWith(shuffleEnabled: enabled);
    });
    _subscribe(_service.repeatModeStream, (mode) {
      if (ref.mounted) state = state.copyWith(repeatMode: mode);
    });
    _subscribe(_service.volumeStream, (volume) {
      if (ref.mounted) state = state.copyWith(volume: volume);
    });
    _subscribe(
      _service.failureStream,
      (failure) => unawaited(_handleFailure(failure)),
    );
  }

  void _recordCurrentTrack() {
    if (_recordCheckScheduled || _replacingQueue) return;
    _recordCheckScheduled = true;
    scheduleMicrotask(() {
      _recordCheckScheduled = false;
      _recordCurrentTrackNow();
    });
  }

  void _recordCurrentTrackNow() {
    if (!ref.mounted || !state.isPlaying || _replacingQueue) return;
    final index = state.currentIndex;
    if (index == null || index < 0 || index >= state.queue.length) return;
    final track = state.queue[index];
    if (track.id == null) return;
    if (_recordedTrackId == track.id) return;
    _recordedTrackId = track.id;
    unawaited(_savePlay(track.id!));
  }

  Future<void> _savePlay(int id) async {
    try {
      await ref.read(smartPlaylistRepositoryProvider).recordPlay(id);
    } catch (error) {
      _setNonFatalError(error);
    }
  }

  void _subscribe<T>(Stream<T> stream, void Function(T value) onData) {
    _subscriptions.add(
      stream.listen(
        onData,
        onError: (Object error, StackTrace stackTrace) {
          _setNonFatalError(error);
        },
      ),
    );
  }

  void _resumePositionUpdates() {
    if (!ref.mounted || _positionSubscription != null) return;
    final service = _service;
    if (service case final PositionSnapshotProvider snapshot) {
      state = state.copyWith(position: snapshot.currentPosition);
    }
    _positionSubscription = service.positionStream.listen(
      (position) {
        if (!ref.mounted) return;
        final previous = _lastPosition;
        _lastPosition = position;
        state = state.copyWith(position: position);
        if (previous != null &&
            previous > const Duration(seconds: 5) &&
            position < const Duration(seconds: 2) &&
            state.isPlaying &&
            !_replacingQueue) {
          _recordedTrackId = null;
          _recordCurrentTrack();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _setNonFatalError(error);
      },
    );
  }

  void _pausePositionUpdates() {
    final subscription = _positionSubscription;
    _positionSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> _handleFailure(AudioPlaybackFailure failure) async {
    if (!ref.mounted) return;
    state = state.copyWith(errorMessage: failure.message);
    try {
      await ref.read(trackRepositoryProvider).markUnavailable({
        failure.track.uri,
      });
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          errorMessage:
              '${failure.message} No se pudo actualizar la biblioteca.',
        );
      }
    }
  }

  void _setFatalError(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(
      status: AudioPlaybackStatus.error,
      errorMessage: _messageFor(error),
    );
  }

  void _setNonFatalError(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(errorMessage: _messageFor(error));
  }

  void _disposeSubscriptions() {
    _pausePositionUpdates();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.isEmpty ? 'Ocurrió un error inesperado.' : message;
  }
}
