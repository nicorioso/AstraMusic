import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/playlists/data/drift_playlist_repository.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return DriftPlaylistRepository(
    ref.watch(appDatabaseProvider),
    useAlbumArtworkIdentity: ref.watch(isAndroidPlatformProvider),
  );
});

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  return ref.watch(playlistRepositoryProvider).watchAll();
});

final playlistProvider = StreamProvider.family<Playlist?, int>((ref, id) {
  return ref.watch(playlistRepositoryProvider).watchById(id);
});

final playlistTracksProvider = StreamProvider.family<List<Track>, int>((
  ref,
  id,
) {
  return ref.watch(playlistRepositoryProvider).watchTracks(id);
});

final playlistCoverTracksProvider = FutureProvider.family<List<Track>, int>((
  ref,
  id,
) {
  return ref.watch(playlistRepositoryProvider).coverTracks(id);
});
