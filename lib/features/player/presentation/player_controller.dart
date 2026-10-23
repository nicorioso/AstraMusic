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

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerViewState>(PlayerController.new);

class PlayerViewState {
  const PlayerViewState({
    this.status = AudioPlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration,
    this.currentItem,
    this.queue = const [],
    this.currentIndex,
    this.shuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.errorMessage,
    this.notificationWarning = false,
  });

  final AudioPlaybackStatus status;
  final Duration position;
  final Duration? duration;
  final AudioItem? currentItem;
  final List<Track> queue;
  final int? currentIndex;
  final bool shuffleEnabled;
  final RepeatMode repeatMode;
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
    Object? currentIndex = _notProvided,
    bool? shuffleEnabled,
    RepeatMode? repeatMode,
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
      currentIndex: currentIndex == _notProvided
          ? this.currentIndex
          : currentIndex as int?,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      errorMessage: errorMessage == _notProvided
          ? this.errorMessage
          : errorMessage as String?,
      notificationWarning: notificationWarning ?? this.notificationWarning,
    );
  }

  static const _notProvided = Object();
}

class PlayerController extends Notifier<PlayerViewState> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _isListening = false;

  AudioPlayerService get _service => ref.read(audioPlayerServiceProvider);

  @override
  PlayerViewState build() {
    final notificationPermissionGranted = ref.watch(
      notificationPermissionGrantedProvider,
    );
    ref.onDispose(_disposeSubscriptions);
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
      _setError(error);
    }
  }

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    _startListening();
    final available = tracks.where((track) => track.isAvailable).toList();
    if (available.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No hay canciones disponibles para reproducir.',
      );
      return;
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
    try {
      await _service.playQueue(available, startIndex: availableStartIndex);
      await _service.setShuffle(shuffle);
      await _service.play();
    } catch (error) {
      _setError(error);
    }
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

  Future<void> addToQueue(Track track) =>
      _run(() => _service.addToQueue(track));

  Future<void> playNext(Track track) => _run(() => _service.playNext(track));

  Future<void> removeFromQueue(int index) =>
      _run(() => _service.removeFromQueue(index));

  Future<void> moveInQueue(int oldIndex, int newIndex) =>
      _run(() => _service.moveInQueue(oldIndex, newIndex));

  Future<void> clearQueue() => _run(_service.clearQueue);

  Future<void> _run(Future<void> Function() action) async {
    _startListening();
    try {
      await action();
    } catch (error) {
      _setError(error);
    }
  }

  void _startListening() {
    if (_isListening || !ref.mounted) return;
    _isListening = true;

    _subscriptions
      ..add(
        _service.playbackStateStream.listen((playbackState) {
          if (!ref.mounted) return;
          state = state.copyWith(
            status: playbackState.status,
            errorMessage: playbackState.errorMessage ?? state.errorMessage,
          );
        }),
      )
      ..add(
        _service.positionStream.listen((position) {
          if (ref.mounted) state = state.copyWith(position: position);
        }),
      )
      ..add(
        _service.durationStream.listen((duration) {
          if (ref.mounted) state = state.copyWith(duration: duration);
        }),
      )
      ..add(
        _service.currentItemStream.listen((item) {
          if (!ref.mounted) return;
          state = state.copyWith(
            currentItem: item,
            duration: item?.duration ?? state.duration,
          );
        }),
      )
      ..add(
        _service.queueStream.listen((queue) {
          if (ref.mounted) state = state.copyWith(queue: queue);
        }),
      )
      ..add(
        _service.currentIndexStream.listen((index) {
          if (ref.mounted) state = state.copyWith(currentIndex: index);
        }),
      )
      ..add(
        _service.shuffleEnabledStream.listen((enabled) {
          if (ref.mounted) state = state.copyWith(shuffleEnabled: enabled);
        }),
      )
      ..add(
        _service.repeatModeStream.listen((mode) {
          if (ref.mounted) state = state.copyWith(repeatMode: mode);
        }),
      )
      ..add(_service.failureStream.listen(_handleFailure));
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

  void _setError(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(
      status: AudioPlaybackStatus.error,
      errorMessage: _messageFor(error),
    );
  }

  void _disposeSubscriptions() {
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
