import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AstraAudioHandler extends BaseAudioHandler with SeekHandler {
  AstraAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(
      _broadcastPlaybackState,
      onError: (Object error, StackTrace stackTrace) {
        _broadcastError(_messageFor(error));
      },
    );
    _player.errorStream.listen((error) {
      _broadcastError(error.message ?? 'No fue posible reproducir el archivo.');
    });
    _player.durationStream.listen(_updateDuration);
  }

  final AudioPlayer _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> loadLocalFile({
    required String path,
    required String title,
  }) async {
    final uri = _sourceUri(path);
    final item = MediaItem(id: uri.toString(), title: title);

    mediaItem.add(item);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
        controls: const [MediaControl.play, MediaControl.stop],
        androidCompactActionIndices: const [0, 1],
        systemActions: const {MediaAction.seek},
        updatePosition: Duration.zero,
      ),
    );

    try {
      if (uri.scheme == 'file' && !await File(uri.toFilePath()).exists()) {
        throw const FileSystemException('El archivo seleccionado no existe.');
      }

      await _player.stop();
      final duration = await _player.setAudioSource(AudioSource.uri(uri));
      mediaItem.add(item.copyWith(duration: duration));
      _broadcastPlaybackState(_player.playbackEvent);
    } on PlayerException catch (error) {
      _broadcastError(
        error.message ?? 'El formato del archivo no es compatible.',
        code: error.code,
      );
    } on PlayerInterruptedException catch (error) {
      _broadcastError(
        error.message ?? 'La carga del archivo fue interrumpida.',
      );
    } on FileSystemException catch (error) {
      _broadcastError(error.message);
    } catch (error) {
      _broadcastError(_messageFor(error));
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  void _broadcastPlaybackState(PlaybackEvent event) {
    final hasItem = mediaItem.value != null;
    final playing = _player.playing;

    playbackState.add(
      playbackState.value.copyWith(
        controls: hasItem
            ? [
                if (playing) MediaControl.pause else MediaControl.play,
                MediaControl.stop,
              ]
            : const [],
        systemActions: hasItem ? const {MediaAction.seek} : const {},
        androidCompactActionIndices: hasItem ? const [0, 1] : const [],
        processingState: _processingState(_player.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  void _broadcastError(String message, {int? code}) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        controls: const [MediaControl.play, MediaControl.stop],
        androidCompactActionIndices: const [0, 1],
        systemActions: const {MediaAction.seek},
        errorCode: code ?? -1,
        errorMessage: message,
      ),
    );
  }

  void _updateDuration(Duration? duration) {
    final item = mediaItem.value;
    if (item == null || item.duration == duration) return;
    mediaItem.add(item.copyWith(duration: duration));
  }

  Uri _sourceUri(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return uri;
    return Uri.file(path);
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
