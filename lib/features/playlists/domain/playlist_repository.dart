import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';

class AddTracksResult {
  const AddTracksResult({required this.added, required this.alreadyPresent});

  final int added;
  final int alreadyPresent;
}

abstract interface class PlaylistRepository {
  Future<Playlist> create(String name);
  Future<void> rename(int id, String name);
  Future<void> delete(int id);
  Stream<List<Playlist>> watchAll();
  Stream<Playlist?> watchById(int id);
  Stream<List<Track>> watchTracks(int id);
  Future<AddTracksResult> addTracks(int playlistId, List<int> trackIds);
  Future<void> removeTrack(int playlistId, int trackId);
}
