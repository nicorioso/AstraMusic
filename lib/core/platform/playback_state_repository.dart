import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/library/domain/track.dart';

class PersistedQueueItem {
  const PersistedQueueItem({
    required this.track,
    required this.position,
    this.originalPosition,
  });

  final Track track;
  final int position;
  final int? originalPosition;
}

class PersistedPlaybackState {
  const PersistedPlaybackState({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.shuffle,
    required this.repeatMode,
  });

  final List<PersistedQueueItem> queue;
  final int? currentIndex;
  final Duration position;
  final bool shuffle;
  final RepeatMode repeatMode;
}

class PlaybackStateSnapshot {
  const PlaybackStateSnapshot({
    required this.queue,
    required this.originalQueue,
    required this.currentIndex,
    required this.position,
    required this.shuffle,
    required this.repeatMode,
  });

  final List<Track> queue;
  final List<Track> originalQueue;
  final int? currentIndex;
  final Duration position;
  final bool shuffle;
  final RepeatMode repeatMode;
}

abstract interface class PlaybackStateRepository {
  Future<PersistedPlaybackState?> load();
  Future<void> save(PlaybackStateSnapshot snapshot);
}
