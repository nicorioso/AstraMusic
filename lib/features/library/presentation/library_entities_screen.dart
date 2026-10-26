import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryEntitiesHub extends ConsumerWidget {
  const LibraryEntitiesHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    key: const Key('library-entities-hub'),
    children: [
      const SectionTitle('Biblioteca'),
      const _EntityLink('Artistas', Icons.person_outline, AppDestination.artists),
      const _EntityLink('Álbumes', Icons.album_outlined, AppDestination.albums),
      const _EntityLink('Géneros', Icons.category_outlined, AppDestination.genres),
      const _EntityLink('Carpetas', Icons.folder_outlined, AppDestination.folders),
    ],
  );
}

class _EntityLink extends ConsumerWidget {
  const _EntityLink(this.label, this.icon, this.destination);
  final String label;
  final IconData icon;
  final AppDestination destination;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: Key('library-$label-tab'), leading: Icon(icon), title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => ref.read(appDestinationProvider.notifier).select(destination),
  );
}

class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({this.artist, super.key});
  final String? artist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artist != null) return _TrackDetail(title: artist!, tracks: ref.watch(libraryGroupingRepositoryProvider).watchArtistTracks(artist!));
    return _GroupsList<ArtistGroup>(
      title: 'Artistas', stream: ref.watch(artistsProvider),
      item: (item) => ListTile(key: ValueKey('artist-${item.name}'), leading: const Icon(Icons.person_outline), title: Text(item.name), subtitle: Text('${item.trackCount} canciones · ${item.albumCount} álbumes'), onTap: () => ref.read(appDestinationProvider.notifier).select(AppDestination.artist(item.name))),
    );
  }
}

class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({this.title, this.artist, super.key});
  final String? title;
  final String? artist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (title != null && artist != null) return _TrackDetail(title: title!, tracks: ref.watch(libraryGroupingRepositoryProvider).watchAlbumTracks(title: title!, artist: artist!));
    return _GroupsList<AlbumGroup>(
      title: 'Álbumes', stream: ref.watch(albumsProvider),
      item: (item) => ListTile(key: ValueKey('album-${item.title}-${item.artist}'), leading: const Icon(Icons.album_outlined), title: Text(item.title), subtitle: Text('${item.artist}${item.year == null ? '' : ' · ${item.year}'} · ${item.trackCount} canciones'), onTap: () => ref.read(appDestinationProvider.notifier).select(AppDestination.album(item.title, item.artist))),
    );
  }
}

class GenresScreen extends ConsumerWidget {
  const GenresScreen({this.genre, super.key});
  final String? genre;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (genre != null) return _TrackDetail(title: genre!, tracks: ref.watch(libraryGroupingRepositoryProvider).watchGenreTracks(genre!));
    return _GroupsList<GenreGroup>(
      title: 'Géneros', stream: ref.watch(genresProvider),
      item: (item) => ListTile(key: ValueKey('genre-${item.name}'), leading: const Icon(Icons.category_outlined), title: Text(item.name), subtitle: Text('${item.trackCount} canciones'), onTap: () => ref.read(appDestinationProvider.notifier).select(AppDestination.genre(item.name))),
    );
  }
}

class FolderGroupsScreen extends ConsumerWidget {
  const FolderGroupsScreen({this.path, super.key});
  final String? path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path != null) return _TrackDetail(title: path!, tracks: ref.watch(libraryGroupingRepositoryProvider).watchFolderTracks(path!));
    return _GroupsList<FolderGroup>(
      title: 'Carpetas', stream: ref.watch(folderGroupsProvider),
      item: (item) => ListTile(key: ValueKey('folder-${item.id}'), leading: const Icon(Icons.folder_outlined), title: Text(item.path), subtitle: Text('${item.trackCount} canciones'), onTap: () => ref.read(appDestinationProvider.notifier).select(AppDestination.folder(item.path))),
    );
  }
}

class _GroupsList<T> extends StatelessWidget {
  const _GroupsList({required this.title, required this.stream, required this.item});
  final String title;
  final AsyncValue<List<T>> stream;
  final Widget Function(T item) item;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    SectionTitle(title), Expanded(child: stream.when(data: (items) => items.isEmpty ? const Center(child: Text('No hay elementos todavía.')) : ListView.builder(key: Key('${title.toLowerCase()}-list'), itemCount: items.length, itemBuilder: (_, index) => item(items[index])), loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => Center(child: Text('No fue posible cargar: $error')))),
  ]);
}

class _TrackDetail extends StatelessWidget {
  const _TrackDetail({required this.title, required this.tracks});
  final String title;
  final Stream<List<Track>> tracks;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    SectionTitle(title), Expanded(child: StreamBuilder<List<Track>>(stream: tracks, builder: (context, snapshot) {
      final items = snapshot.data;
      if (items == null) return const Center(child: CircularProgressIndicator());
      return ListView.builder(key: const Key('library-entity-track-list'), itemExtent: 56, itemCount: items.length, itemBuilder: (_, index) { final track = items[index]; return ListTile(title: Text(track.title), subtitle: Text(track.artist ?? 'Artista desconocido'), trailing: track.trackNumber == null ? null : Text('${track.trackNumber}')); });
    })),
  ]);
}
