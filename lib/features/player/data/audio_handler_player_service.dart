import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:audio_service/audio_service.dart';

final class AudioHandlerPlayerService implements AudioPlayerService {
  AudioHandlerPlayerService(this._handler);

  final AstraAudioHandler _handler;

  @override
  Stream<AudioPlaybackState> get playbackStateStream =>
      _handler.playbackState.map(_toPlaybackState).distinct(_sameState);

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration?> get durationStream => _handler.durationStream;

  @override
  Stream<AudioItem?> get currentItemStream => _handler.mediaItem.map(
    (item) => item == null
        ? null
        : AudioItem(path: item.id, title: item.title, duration: item.duration),
  );

  @override
  Future<void> loadFile({required String path, required String title}) =>
      _handler.loadLocalFile(path: path, title: title);

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  AudioPlaybackState _toPlaybackState(PlaybackState state) {
    final status = switch (state.processingState) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => AudioPlaybackStatus.loading,
      AudioProcessingState.completed => AudioPlaybackStatus.completed,
      AudioProcessingState.error => AudioPlaybackStatus.error,
      AudioProcessingState.idle || AudioProcessingState.ready =>
        state.playing
            ? AudioPlaybackStatus.playing
            : AudioPlaybackStatus.paused,
    };

    return AudioPlaybackState(status, errorMessage: state.errorMessage);
  }

  bool _sameState(AudioPlaybackState previous, AudioPlaybackState next) =>
      previous.status == next.status &&
      previous.errorMessage == next.errorMessage;
}
