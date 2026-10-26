import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/track.dart';

abstract interface class LibraryGroupingRepository {
  Stream<List<ArtistGroup>> watchArtists();
  Stream<List<AlbumGroup>> watchAlbums();
  Stream<List<GenreGroup>> watchGenres();
  Stream<List<FolderGroup>> watchFolders();
  Stream<List<Track>> watchArtistTracks(String artist);
  Stream<List<Track>> watchAlbumTracks({
    required String title,
    required String artist,
  });
  Stream<List<Track>> watchGenreTracks(String genre);
  Stream<List<Track>> watchFolderTracks(String path);
}
