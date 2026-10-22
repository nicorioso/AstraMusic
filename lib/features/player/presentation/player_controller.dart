import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
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
    this.errorMessage,
    this.notificationWarning = false,
  });

  final AudioPlaybackStatus status;
  final Duration position;
  final Duration? duration;
  final AudioItem? currentItem;
  final String? errorMessage;
  final bool notificationWarning;

  bool get isPlaying => status == AudioPlaybackStatus.playing;
  bool get isLoading => status == AudioPlaybackStatus.loading;

  PlayerViewState copyWith({
    AudioPlaybackStatus? status,
    Duration? position,
    Object? duration = _notProvided,
    Object? currentItem = _notProvided,
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
      if (!ref.mounted) return;
      state = state.copyWith(
        status: AudioPlaybackStatus.error,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> togglePlayback() async {
    _startListening();
    if (state.currentItem == null || state.isLoading) return;

    try {
      if (state.isPlaying) {
        await _service.pause();
      } else {
        await _service.play();
      }
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: AudioPlaybackStatus.error,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> seek(Duration position) async {
    _startListening();
    try {
      await _service.seek(position);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: AudioPlaybackStatus.error,
        errorMessage: _messageFor(error),
      );
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
            errorMessage: playbackState.errorMessage,
          );
        }),
      )
      ..add(
        _service.positionStream.listen((position) {
          if (!ref.mounted) return;
          state = state.copyWith(position: position);
        }),
      )
      ..add(
        _service.durationStream.listen((duration) {
          if (!ref.mounted) return;
          state = state.copyWith(duration: duration);
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
