import 'dart:async';
import 'dart:math';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/data/latest_seek_coordinator.dart';
import 'package:astramusic/features/player/data/queue_load_strategy.dart';
import 'package:astramusic/features/player/domain/manual_queue_order.dart';
import 'package:astramusic/features/player/domain/queue_rules.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path_utils;

class HandlerPlaybackFailure {
  const HandlerPlaybackFailure({required this.item, required this.message});

  final MediaItem item;
  final String message;
}

class AstraAudioHandler extends BaseAudioHandler with SeekHandler {
  AstraAudioHandler({
    AudioPlayer? player,
    this._queueLoadStrategy = const SetAudioSourcesQueueLoadStrategy(),
    Random? shuffleRandom,
  }) : _player = player ?? AudioPlayer(),
       _queueOrder = ManualQueueOrder([], random: shuffleRandom) {
    _lastObservedSpeed = _player.speed;
    _seekCoordinator = LatestSeekCoordinator(
      _executeSeek,
      canExecute: () => !_queueOrder.isEmpty,
      onDiscarded: (count) {
        if (kDebugMode) {
          debugPrint('AstraMusic seek: $count solicitudes descartadas.');
        }
      },
    );
    _playerSubscriptions
      ..add(
        _player.playbackEventStream.listen(
          _broadcastPlaybackState,
          onError: (Object error, StackTrace stackTrace) {
            _scheduleFailure(_messageFor(error));
          },
        ),
      )
      ..add(
        _player.errorStream.listen((error) {
          _scheduleFailure(
            error.message ?? 'No fue posible reproducir el archivo.',
            code: error.code,
          );
        }, onError: _handleStreamError),
      )
      ..add(
        _player.durationStream.listen(
          _updateDuration,
          onError: _handleStreamError,
        ),
      )
      ..add(
        _player.currentIndexStream.listen(
          (_) => _publishQueueAndCurrent(),
          onError: _handleStreamError,
        ),
      )
      ..add(
        _player.sequenceStateStream.listen((_) {
          if (!_mutatingQueue) _publishQueueAndCurrent();
        }, onError: _handleStreamError),
      )
      ..add(
        _player.speedStream.listen(
          _handleSpeedChange,
          onError: _handleStreamError,
        ),
      )
      ..add(
        _player.processingStateStream.listen((state) {
          if (state == ProcessingState.completed) {
            unawaited(_resetAtQueueEnd());
          }
        }, onError: _handleStreamError),
      );
  }

  final AudioPlayer _player;
  final QueueLoadStrategy _queueLoadStrategy;
  final ManualQueueOrder<MediaItem> _queueOrder;
  late final LatestSeekCoordinator _seekCoordinator;
  final Set<int> _failedIndices = {};
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  final _failureController =
      StreamController<HandlerPlaybackFailure>.broadcast();
  Future<void> _failureChain = Future.value();
  bool _mutatingQueue = false;
  bool _playRequested = false;
  bool _resettingAtEnd = false;
  late double _lastObservedSpeed;
  double? _lastUnexpectedPublishedSpeed;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<HandlerPlaybackFailure> get failureStream => _failureController.stream;
  List<MediaItem> get originalQueue => List.unmodifiable(_queueOrder.original);

  Future<void> loadQueue(List<MediaItem> items, {int startIndex = 0}) async {
    if (items.isEmpty) {
      await updateQueue(const []);
      return;
    }
    if (startIndex < 0 || startIndex >= items.length) {
      throw RangeError.range(startIndex, 0, items.length - 1, 'startIndex');
    }

    _playRequested = false;
    _failedIndices.clear();
    _mutatingQueue = true;
    _queueOrder
      ..clear()
      ..addAll(items);
    queue.add(List.unmodifiable(items));
    mediaItem.add(items[startIndex]);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
        controls: _controls(false),
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        updatePosition: Duration.zero,
        queueIndex: startIndex,
        shuffleMode: AudioServiceShuffleMode.none,
      ),
    );

    try {
      await _loadPlayerQueue(startIndex: startIndex);
      _publishQueueAndCurrent();
      _broadcastPlaybackState(_player.playbackEvent);
    } on PlayerException catch (error) {
      await _handleFailure(
        startIndex,
        error.message ?? 'El formato del archivo no es compatible.',
        code: error.code,
      );
    } on PlayerInterruptedException catch (error) {
      final message = error.message ?? 'La carga de la cola fue interrumpida.';
      _broadcastError(message);
      throw AudioPlayerException(message);
    } catch (error) {
      final message = _messageFor(error);
      _broadcastError(message);
      throw AudioPlayerException(message);
    } finally {
      _mutatingQueue = false;
      _publishQueueAndCurrent();
    }
  }

  @override
  Future<void> play() async {
    if (_queueOrder.isEmpty) return;
    _playRequested = true;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: _player.currentIndex ?? 0);
    }
    _startPlayer();
  }

  @override
  Future<void> pause() async {
    _playRequested = false;
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _playRequested = false;
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) {
    if (kDebugMode) {
      debugPrint(
        'AstraMusic seek solicitado: ${position.inMilliseconds} ms, '
        '${DateTime.now().toIso8601String()}.',
      );
    }
    return _seekCoordinator.request(position);
  }

  @override
  Future<void> skipToNext() async {
    final nextIndex = _player.nextIndex;
    if (nextIndex != null) {
      await _player.seek(Duration.zero, index: nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final decision = decidePrevious(
      position: _player.position,
      previousIndex: _player.previousIndex,
    );
    switch (decision.action) {
      case PreviousAction.restartCurrent:
        await _player.seek(Duration.zero);
      case PreviousAction.goToPrevious:
        await _player.seek(Duration.zero, index: decision.targetIndex);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queueOrder.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    if (_queueOrder.isEmpty || enabled == _queueOrder.shuffleEnabled) {
      playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
      return;
    }

    final currentIndex = _player.currentIndex ?? 0;
    final currentPosition = _player.position;
    final wasPlaying = _player.playing;
    final newIndex = _queueOrder.setShuffle(
      enabled: enabled,
      currentIndex: currentIndex,
    );

    _mutatingQueue = true;
    try {
      _failedIndices.clear();
      await _loadPlayerQueue(
        startIndex: newIndex,
        initialPosition: currentPosition,
      );
      if (wasPlaying && !_player.playing) _startPlayer();
      if (!wasPlaying && _player.playing) await _player.pause();
      playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    } catch (error) {
      final rollbackIndex = _queueOrder.setShuffle(
        enabled: !enabled,
        currentIndex: newIndex,
      );
      try {
        await _loadPlayerQueue(
          startIndex: rollbackIndex,
          initialPosition: currentPosition,
        );
        if (wasPlaying && !_player.playing) _startPlayer();
      } catch (_) {
        // El error original describe mejor la operación que falló.
      }
      throw AudioPlayerException(
        'No fue posible cambiar el modo aleatorio: ${_messageFor(error)}',
      );
    } finally {
      _mutatingQueue = false;
      _publishQueueAndCurrent();
      _broadcastPlaybackState(_player.playbackEvent);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) => _mutateQueue(() async {
    await _player.addAudioSource(_itemToSource(mediaItem));
    _queueOrder.add(mediaItem);
  });

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) =>
      _mutateQueue(() async {
        if (mediaItems.isEmpty) return;
        await _player.addAudioSources(
          mediaItems.map(_itemToSource).toList(growable: false),
        );
        _queueOrder.addAll(mediaItems);
      });

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      _mutateQueue(() async {
        final safeIndex = index.clamp(0, _queueOrder.length);
        await _player.insertAudioSource(safeIndex, _itemToSource(mediaItem));
        _queueOrder.insertAt(safeIndex, mediaItem);
        _failedIndices.clear();
      });

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    if (queue.isEmpty) {
      await _mutateQueue(() async {
        _playRequested = false;
        await _player.stop();
        await _player.clearAudioSources();
        _queueOrder.clear();
        _failedIndices.clear();
      });
      return;
    }
    await loadQueue(queue);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    final index = _queueOrder.indexWhere(
      (candidate) => candidate.id == mediaItem.id,
    );
    if (index == -1) return;
    _queueOrder.replaceAt(index, mediaItem);
    _publishQueueAndCurrent();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = queue.value.indexOf(mediaItem);
    if (index != -1) await removeQueueItemAt(index);
  }

  @override
  Future<void> removeQueueItemAt(int index) => _mutateQueue(() async {
    if (index < 0 || index >= _queueOrder.length) return;
    await _player.removeAudioSourceAt(index);
    _queueOrder.removeAt(index);
    _reindexFailedAfterRemoval(index);
  });

  Future<void> moveQueueItem(int oldIndex, int newIndex) =>
      _mutateQueue(() async {
        if (oldIndex < 0 ||
            oldIndex >= _queueOrder.length ||
            newIndex < 0 ||
            newIndex >= _queueOrder.length ||
            oldIndex == newIndex) {
          return;
        }
        await _player.moveAudioSource(oldIndex, newIndex);
        _queueOrder.move(oldIndex, newIndex);
        _failedIndices.clear();
      });

  Future<void> _mutateQueue(Future<void> Function() mutation) async {
    _mutatingQueue = true;
    try {
      await mutation();
    } finally {
      _mutatingQueue = false;
      _publishQueueAndCurrent();
      _broadcastPlaybackState(_player.playbackEvent);
    }
  }

  Future<Duration?> _loadPlayerQueue({
    required int startIndex,
    Duration initialPosition = Duration.zero,
  }) {
    return _queueLoadStrategy.load(
      _player,
      _queueOrder.playback.map(_itemToSource).toList(growable: false),
      startIndex: startIndex,
      initialPosition: initialPosition,
    );
  }

  AudioSource _itemToSource(MediaItem item) =>
      AudioSource.uri(_sourceUri(item.id), tag: item);

  Uri _sourceUri(String source) {
    if (path_utils.isAbsolute(source)) return Uri.file(source);
    final uri = Uri.tryParse(source);
    if (uri != null && uri.hasScheme) return uri;
    return Uri.file(source);
  }

  void _publishQueueAndCurrent() {
    queue.add(List.unmodifiable(_queueOrder.playback));
    final current = _player.currentIndex;
    mediaItem.add(
      current != null && current >= 0 && current < _queueOrder.length
          ? _queueOrder[current]
          : null,
    );
    playbackState.add(playbackState.value.copyWith(queueIndex: current));
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    final hasQueue = !_queueOrder.isEmpty;
    final playing = _player.playing;
    final speed = _player.speed;
    if (kDebugMode && speed != 1.0) {
      if (_lastUnexpectedPublishedSpeed != speed) {
        debugPrint(
          'AstraMusic PlaybackState publicó velocidad inesperada: $speed.',
        );
        _lastUnexpectedPublishedSpeed = speed;
      }
    } else {
      _lastUnexpectedPublishedSpeed = null;
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: hasQueue ? _controls(playing) : const [],
        systemActions: hasQueue ? const {MediaAction.seek} : const {},
        androidCompactActionIndices: hasQueue ? const [0, 1, 2] : const [],
        processingState: _processingState(_player.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  List<MediaControl> _controls(bool playing) => [
    MediaControl.skipToPrevious,
    if (playing) MediaControl.pause else MediaControl.play,
    MediaControl.skipToNext,
  ];

  void _scheduleFailure(String message, {int? code}) {
    final failedIndex = _player.currentIndex;
    if (failedIndex == null) {
      _broadcastError(message, code: code);
      return;
    }
    _failureChain = _failureChain
        .then((_) => _handleFailure(failedIndex, message, code: code))
        .catchError((Object error, StackTrace stackTrace) {
          _broadcastError(_messageFor(error));
        });
  }

  Future<void> _handleFailure(
    int failedIndex,
    String message, {
    int? code,
  }) async {
    if (failedIndex < 0 || failedIndex >= _queueOrder.length) {
      _broadcastError(message, code: code);
      return;
    }

    final firstFailure = _failedIndices.add(failedIndex);
    if (!firstFailure && _player.currentIndex != failedIndex) return;
    if (firstFailure) {
      _failureController.add(
        HandlerPlaybackFailure(
          item: _queueOrder[failedIndex],
          message: message,
        ),
      );
    }
    _broadcastError(message, code: code);

    final nextIndex = nextUnfailedIndex(
      currentIndex: failedIndex,
      effectiveIndices: List.generate(_queueOrder.length, (index) => index),
      failedIndices: _failedIndices,
    );
    if (nextIndex == null) {
      _playRequested = false;
      await _player.pause();
      _broadcastError(
        'No fue posible reproducir ninguna canción de la cola.',
        code: code,
      );
      return;
    }

    await _player.seek(Duration.zero, index: nextIndex);
    if (_playRequested) _startPlayer();
    _broadcastPlaybackState(_player.playbackEvent);
  }

  void _startPlayer() {
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        _scheduleFailure(_messageFor(error));
      }),
    );
  }

  void _broadcastError(String message, {int? code}) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        controls: _queueOrder.isEmpty ? const [] : _controls(false),
        androidCompactActionIndices: _queueOrder.isEmpty
            ? const []
            : const [0, 1, 2],
        systemActions: _queueOrder.isEmpty
            ? const {}
            : const {MediaAction.seek},
        errorCode: code ?? -1,
        errorMessage: message,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  Future<void> _resetAtQueueEnd() async {
    if (_resettingAtEnd ||
        _player.loopMode != LoopMode.off ||
        _queueOrder.isEmpty) {
      return;
    }
    _resettingAtEnd = true;
    try {
      _playRequested = false;
      await _player.pause();
      await _player.seek(Duration.zero, index: 0);
      _broadcastPlaybackState(_player.playbackEvent);
    } finally {
      _resettingAtEnd = false;
    }
  }

  void _updateDuration(Duration? duration) {
    final current = _player.currentIndex;
    if (current == null || current < 0 || current >= _queueOrder.length) return;
    final item = _queueOrder[current];
    if (duration == null || item.duration == duration) return;
    _queueOrder.replaceAt(current, item.copyWith(duration: duration));
    _publishQueueAndCurrent();
  }

  void _reindexFailedAfterRemoval(int removedIndex) {
    final reindexed = <int>{};
    for (final index in _failedIndices) {
      if (index < removedIndex) reindexed.add(index);
      if (index > removedIndex) reindexed.add(index - 1);
    }
    _failedIndices
      ..clear()
      ..addAll(reindexed);
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _broadcastError(_messageFor(error));
  }

  Future<void> _executeSeek(Duration requestedPosition) async {
    final duration = _player.duration ?? mediaItem.value?.duration;
    final position = clampSeekPosition(requestedPosition, duration);
    final stopwatch = Stopwatch()..start();
    try {
      await _player.seek(position);
      _broadcastPlaybackState(_player.playbackEvent);
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'AstraMusic seek ejecutado: ${position.inMilliseconds} ms en '
          '${stopwatch.elapsedMilliseconds} ms; estado '
          '${_player.processingState.name}, playing=${_player.playing}.',
        );
      }
    }
  }

  void _handleSpeedChange(double speed) {
    if (speed == _lastObservedSpeed) return;
    if (kDebugMode) {
      debugPrint('AstraMusic velocidad cambió: $_lastObservedSpeed -> $speed.');
    }
    _lastObservedSpeed = speed;
  }

  AudioProcessingState _processingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.isEmpty ? 'No fue posible cargar el archivo.' : message;
  }
}
