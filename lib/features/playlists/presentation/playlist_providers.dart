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

final recentPlaylistsProvider = StreamProvider<List<Playlist>>((ref) {
  return ref.watch(playlistRepositoryProvider).watchRecent(8);
});

final homePlaylistShortcutsProvider = Provider<List<HomePlaylistShortcut>>((
  ref,
) {
  final all = ref.watch(playlistsProvider).value;
  final recent = ref.watch(recentPlaylistsProvider).value;
  if (all == null || recent == null || all.isEmpty) return const [];
  return composeHomePlaylistShortcuts(recent: recent, all: all);
});

class HomePlaylistShortcut {
  const HomePlaylistShortcut.playlist(this.playlist) : isFavorites = false;
  const HomePlaylistShortcut.favorites() : playlist = null, isFavorites = true;

  final Playlist? playlist;
  final bool isFavorites;

  String get name => isFavorites ? 'Canciones que te gustan' : playlist!.name;
}

List<HomePlaylistShortcut> composeHomePlaylistShortcuts({
  required List<Playlist> recent,
  required List<Playlist> all,
  int limit = 8,
}) {
  if (limit <= 0 || all.isEmpty) return const [];
  final result = <HomePlaylistShortcut>[];
  final included = <int>{};
  for (final playlist in recent) {
    if (included.add(playlist.id)) {
      result.add(HomePlaylistShortcut.playlist(playlist));
    }
    if (result.length == limit) return List.unmodifiable(result);
  }

  result.add(const HomePlaylistShortcut.favorites());
  if (result.length == limit) return List.unmodifiable(result);

  final newest = [...all]
    ..sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  for (final playlist in newest) {
    if (included.add(playlist.id)) {
      result.add(HomePlaylistShortcut.playlist(playlist));
    }
    if (result.length == limit) break;
  }
  return List.unmodifiable(result);
}

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
