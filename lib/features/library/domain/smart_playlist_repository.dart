import 'package:astramusic/features/library/domain/track.dart';

enum SmartPlaylist { recentlyPlayed, mostPlayed, neverPlayed, recentlyAdded }

abstract interface class SmartPlaylistRepository {
  Stream<List<Track>> watch(SmartPlaylist playlist, {int limit = 100});
  Future<void> recordPlay(int trackId);
}
