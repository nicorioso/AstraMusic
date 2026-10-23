enum AudioPlaybackStatus { idle, loading, paused, playing, completed, error }

class AudioPlaybackState {
  const AudioPlaybackState(this.status, {this.errorMessage});

  const AudioPlaybackState.idle() : this(AudioPlaybackStatus.idle);

  final AudioPlaybackStatus status;
  final String? errorMessage;
}

class AudioItem {
  const AudioItem({required this.path, required this.title, this.duration});

  final String path;
  final String title;
  final Duration? duration;
}

class AudioPlayerException implements Exception {
  const AudioPlayerException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AudioPlayerService {
  Stream<AudioPlaybackState> get playbackStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<AudioItem?> get currentItemStream;

  Future<void> loadFile({required String path, required String title});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
}
