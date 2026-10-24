import 'package:astramusic/features/library/domain/track.dart';

enum AudioPlaybackStatus { idle, loading, paused, playing, completed, error }

enum RepeatMode { off, all, one }

class AudioPlaybackState {
  const AudioPlaybackState(this.status, {this.errorMessage});

  const AudioPlaybackState.idle() : this(AudioPlaybackStatus.idle);

  final AudioPlaybackStatus status;
  final String? errorMessage;
}

class AudioItem {
  const AudioItem({
    required this.path,
    required this.title,
    this.artist,
    this.duration,
    this.trackId,
    this.artworkPath,
  });

  final String path;
  final String title;
  final String? artist;
  final Duration? duration;
  final int? trackId;
  final String? artworkPath;
}

class AudioPlaybackFailure {
  const AudioPlaybackFailure({required this.track, required this.message});

  final Track track;
  final String message;
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
  Stream<List<Track>> get queueStream;
  Stream<int?> get currentIndexStream;
  Stream<bool> get shuffleEnabledStream;
  Stream<RepeatMode> get repeatModeStream;
  Stream<double> get volumeStream;
  Stream<AudioPlaybackFailure> get failureStream;

  Future<void> loadFile({required String path, required String title});
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> skipToIndex(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> setVolume(double volume);
  Future<void> addToQueue(Track track);
  Future<void> playNext(Track track);
  Future<void> removeFromQueue(int index);
  Future<void> moveInQueue(int oldIndex, int newIndex);
  Future<void> clearQueue();
}

abstract interface class OriginalQueueProvider {
  List<Track> get originalQueue;
  List<Track> get playbackQueue;
}
