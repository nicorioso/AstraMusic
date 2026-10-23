import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/data/queue_load_strategy.dart';
import 'package:astramusic/features/player/domain/queue_rules.dart';
import 'package:audio_service/audio_service.dart';
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
  }) : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(
      _broadcastPlaybackState,
      onError: (Object error, StackTrace stackTrace) {
        _scheduleFailure(_messageFor(error));
      },
    );
    _player.errorStream.listen((error) {
      _scheduleFailure(
        error.message ?? 'No fue posible reproducir el archivo.',
        code: error.code,
      );
    });
    _player.durationStream.listen(_updateDuration);
    _player.currentIndexStream.listen((_) => _publishQueueAndCurrent());
    _player.sequenceStateStream.listen((_) {
      if (!_mutatingQueue) _publishQueueAndCurrent();
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) unawaited(_resetAtQueueEnd());
    });
  }

  final AudioPlayer _player;
  final QueueLoadStrategy _queueLoadStrategy;
  final QueueShuffleOrder _shuffleOrder = QueueShuffleOrder();
  final List<MediaItem> _baseQueue = [];
  final Set<int> _failedIndices = {};
  final _failureController =
      StreamController<HandlerPlaybackFailure>.broadcast();
  Future<void> _failureChain = Future.value();
  bool _mutatingQueue = false;
  bool _playRequested = false;
  bool _resettingAtEnd = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<HandlerPlaybackFailure> get failureStream => _failureController.stream;

  Future<void> loadLocalFile({required String path, required String title}) {
    return loadQueue([MediaItem(id: path, title: title)]);
  }

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
    _baseQueue
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
      ),
    );

    try {
      await _queueLoadStrategy.load(
        _player,
        items.map(_itemToSource).toList(growable: false),
        startIndex: startIndex,
        shuffleOrder: _shuffleOrder,
      );
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
    if (_baseQueue.isEmpty) return;
    _playRequested = true;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: _player.currentIndex ?? 0);
    }
    await _player.play();
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
  Future<void> seek(Duration position) => _player.seek(position);

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
    final baseIndex = _baseIndexForEffective(index);
    if (baseIndex == null) return;
    await _player.seek(Duration.zero, index: baseIndex);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    if (enabled && !_player.shuffleModeEnabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    _publishQueueAndCurrent();
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
    _shuffleOrder.scheduleInsertionAt(queue.value.length);
    await _player.addAudioSource(_itemToSource(mediaItem));
    _baseQueue.add(mediaItem);
  });

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) =>
      _mutateQueue(() async {
        if (mediaItems.isEmpty) return;
        _shuffleOrder.scheduleInsertionAt(queue.value.length);
        await _player.addAudioSources(
          mediaItems.map(_itemToSource).toList(growable: false),
        );
        _baseQueue.addAll(mediaItems);
      });

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      _mutateQueue(() async {
        final baseIndex = _baseInsertionIndex(index);
        _shuffleOrder.scheduleInsertionAt(index);
        await _player.insertAudioSource(baseIndex, _itemToSource(mediaItem));
        _baseQueue.insert(baseIndex, mediaItem);
      });

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    if (queue.isEmpty) {
      await _mutateQueue(() async {
        _playRequested = false;
        await _player.stop();
        await _player.clearAudioSources();
        _baseQueue.clear();
        _failedIndices.clear();
      });
      return;
    }
    await loadQueue(queue);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    final index = _baseQueue.indexWhere(
      (candidate) => candidate.id == mediaItem.id,
    );
    if (index == -1) return;
    _baseQueue[index] = mediaItem;
    _publishQueueAndCurrent();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = queue.value.indexOf(mediaItem);
    if (index != -1) await removeQueueItemAt(index);
  }

  @override
  Future<void> removeQueueItemAt(int index) => _mutateQueue(() async {
    final baseIndex = _baseIndexForEffective(index);
    if (baseIndex == null) return;
    await _player.removeAudioSourceAt(baseIndex);
    _baseQueue.removeAt(baseIndex);
    _reindexFailedAfterRemoval(baseIndex);
  });

  Future<void> moveQueueItem(int oldIndex, int newIndex) =>
      _mutateQueue(() async {
        final oldBaseIndex = _baseIndexForEffective(oldIndex);
        if (oldBaseIndex == null ||
            newIndex < 0 ||
            newIndex >= queue.value.length) {
          return;
        }
        final newBaseIndex = _baseIndexForEffective(newIndex);
        if (newBaseIndex == null || oldBaseIndex == newBaseIndex) return;
        _shuffleOrder.scheduleInsertionAt(newIndex);
        await _player.moveAudioSource(oldBaseIndex, newBaseIndex);
        _baseQueue.insert(newBaseIndex, _baseQueue.removeAt(oldBaseIndex));
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

  AudioSource _itemToSource(MediaItem item) =>
      AudioSource.uri(_sourceUri(item.id), tag: item);

  Uri _sourceUri(String source) {
    if (path_utils.isAbsolute(source)) return Uri.file(source);
    final uri = Uri.tryParse(source);
    if (uri != null && uri.hasScheme) return uri;
    return Uri.file(source);
  }

  List<int> get _effectiveIndices {
    final indices = _player.effectiveIndices;
    if (indices.length == _baseQueue.length) return indices;
    return List.generate(_baseQueue.length, (index) => index);
  }

  int? _baseIndexForEffective(int effectiveIndex) {
    final indices = _effectiveIndices;
    if (effectiveIndex < 0 || effectiveIndex >= indices.length) return null;
    return indices[effectiveIndex];
  }

  int _baseInsertionIndex(int effectiveIndex) {
    if (_baseQueue.isEmpty) return 0;
    if (effectiveIndex >= queue.value.length) return _baseQueue.length;
    return _baseIndexForEffective(effectiveIndex) ?? _baseQueue.length;
  }

  int? get _effectiveCurrentIndex {
    final current = _player.currentIndex;
    if (current == null) return null;
    final index = _effectiveIndices.indexOf(current);
    return index == -1 ? null : index;
  }

  void _publishQueueAndCurrent() {
    final indices = _effectiveIndices;
    queue.add(List.unmodifiable(indices.map((index) => _baseQueue[index])));
    final current = _player.currentIndex;
    mediaItem.add(
      current != null && current >= 0 && current < _baseQueue.length
          ? _baseQueue[current]
          : null,
    );
    playbackState.add(
      playbackState.value.copyWith(queueIndex: _effectiveCurrentIndex),
    );
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    final hasQueue = _baseQueue.isNotEmpty;
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: hasQueue ? _controls(playing) : const [],
        systemActions: hasQueue ? const {MediaAction.seek} : const {},
        androidCompactActionIndices: hasQueue ? const [0, 1, 2] : const [],
        processingState: _processingState(_player.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _effectiveCurrentIndex,
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
    _failureChain = _failureChain.then(
      (_) => _handleFailure(failedIndex, message, code: code),
    );
  }

  Future<void> _handleFailure(
    int failedIndex,
    String message, {
    int? code,
  }) async {
    if (failedIndex < 0 || failedIndex >= _baseQueue.length) {
      _broadcastError(message, code: code);
      return;
    }

    final firstFailure = _failedIndices.add(failedIndex);
    if (!firstFailure && _player.currentIndex != failedIndex) return;
    if (firstFailure) {
      _failureController.add(
        HandlerPlaybackFailure(item: _baseQueue[failedIndex], message: message),
      );
    }
    _broadcastError(message, code: code);

    final nextIndex = nextUnfailedIndex(
      currentIndex: failedIndex,
      effectiveIndices: _effectiveIndices,
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
    if (_playRequested) await _player.play();
  }

  void _broadcastError(String message, {int? code}) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        controls: _baseQueue.isEmpty ? const [] : _controls(false),
        androidCompactActionIndices: _baseQueue.isEmpty
            ? const []
            : const [0, 1, 2],
        systemActions: _baseQueue.isEmpty ? const {} : const {MediaAction.seek},
        errorCode: code ?? -1,
        errorMessage: message,
        queueIndex: _effectiveCurrentIndex,
      ),
    );
  }

  Future<void> _resetAtQueueEnd() async {
    if (_resettingAtEnd ||
        _player.loopMode != LoopMode.off ||
        _baseQueue.isEmpty) {
      return;
    }
    _resettingAtEnd = true;
    try {
      _playRequested = false;
      await _player.pause();
      await _player.seek(Duration.zero, index: _effectiveIndices.first);
      _broadcastPlaybackState(_player.playbackEvent);
    } finally {
      _resettingAtEnd = false;
    }
  }

  void _updateDuration(Duration? duration) {
    final current = _player.currentIndex;
    if (current == null || current < 0 || current >= _baseQueue.length) return;
    final item = _baseQueue[current];
    if (duration == null || item.duration == duration) return;
    _baseQueue[current] = item.copyWith(duration: duration);
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
