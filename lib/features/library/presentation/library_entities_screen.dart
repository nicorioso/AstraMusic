import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryEntitiesHub extends ConsumerWidget {
  const LibraryEntitiesHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    key: const Key('library-entities-hub'),
    children: [
      const SectionTitle('Biblioteca'),
      const _EntityLink(
        'Artistas',
        Icons.person_outline,
        AppDestination.artists,
      ),
      const _EntityLink('Álbumes', Icons.album_outlined, AppDestination.albums),
      const _EntityLink(
        'Géneros',
        Icons.category_outlined,
        AppDestination.genres,
      ),
      const _EntityLink(
        'Carpetas',
        Icons.folder_outlined,
        AppDestination.folders,
      ),
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
    key: Key('library-$label-tab'),
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => ref.read(appDestinationProvider.notifier).select(destination),
  );
}

class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({this.artist, super.key});
  final String? artist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artist != null) {
      return _TrackDetail(
        title: artist!,
        tracks: ref
            .watch(libraryGroupingRepositoryProvider)
            .watchArtistTracks(artist!),
      );
    }
    return _GroupsList<ArtistGroup>(
      title: 'Artistas',
      stream: ref.watch(artistsProvider),
      item: (item) => _EntityTile(
        key: ValueKey('artist-${item.name}'),
        title: Text(item.name),
        subtitle: Text(
          '${item.trackCount} canciones · ${item.albumCount} álbumes',
        ),
        artwork: _groupArtwork(
          identity: 'artist:${item.name}',
          title: item.name,
          artist: item.name,
          artworkPath: item.artworkPath,
        ),
        onTap: () => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.artist(item.name)),
      ),
    );
  }
}

class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({this.title, this.artist, super.key});
  final String? title;
  final String? artist;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (title != null && artist != null) {
      return _TrackDetail(
        title: title!,
        tracks: ref
            .watch(libraryGroupingRepositoryProvider)
            .watchAlbumTracks(title: title!, artist: artist!),
      );
    }
    return _GroupsList<AlbumGroup>(
      title: 'Álbumes',
      stream: ref.watch(albumsProvider),
      item: (item) => _EntityTile(
        key: ValueKey('album-${item.title}-${item.artist}'),
        title: Text(item.title),
        subtitle: Text(
          '${item.artist}${item.year == null ? '' : ' · ${item.year}'} · ${item.trackCount} canciones',
        ),
        artwork: _groupArtwork(
          identity: 'album:${item.artist}:${item.title}',
          title: item.title,
          artist: item.artist,
          artworkPath: item.artworkPath,
        ),
        onTap: () => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.album(item.title, item.artist)),
      ),
    );
  }
}

class GenresScreen extends ConsumerWidget {
  const GenresScreen({this.genre, super.key});
  final String? genre;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (genre != null) {
      return _TrackDetail(
        title: genre!,
        tracks: ref
            .watch(libraryGroupingRepositoryProvider)
            .watchGenreTracks(genre!),
      );
    }
    return _GroupsList<GenreGroup>(
      title: 'Géneros',
      stream: ref.watch(genresProvider),
      item: (item) => _EntityTile(
        key: ValueKey('genre-${item.name}'),
        title: Text(item.name),
        subtitle: Text('${item.trackCount} canciones'),
        artwork: _groupArtwork(
          identity: 'genre:${item.name}',
          title: item.name,
          artworkPath: item.artworkPath,
        ),
        onTap: () => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.genre(item.name)),
      ),
    );
  }
}

Track _groupArtwork({
  required String identity,
  required String title,
  String? artist,
  String? artworkPath,
}) => Track(
  uri: 'group://$identity',
  title: title,
  artist: artist,
  artworkPath: artworkPath,
  dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
);

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.onTap,
    super.key,
  });

  final Widget title;
  final Widget subtitle;
  final Track artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: TrackArtwork(track: artwork, size: 56),
    title: title,
    subtitle: subtitle,
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class FolderGroupsScreen extends ConsumerWidget {
  const FolderGroupsScreen({this.path, super.key});
  final String? path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path != null) {
      return _TrackDetail(
        title: path!,
        tracks: ref
            .watch(libraryGroupingRepositoryProvider)
            .watchFolderTracks(path!),
      );
    }
    return _GroupsList<FolderGroup>(
      title: 'Carpetas',
      stream: ref.watch(folderGroupsProvider),
      item: (item) => ListTile(
        key: ValueKey('folder-${item.id}'),
        leading: const Icon(Icons.folder_outlined),
        title: Text(item.path),
        subtitle: Text('${item.trackCount} canciones'),
        onTap: () => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.folder(item.path)),
      ),
    );
  }
}

class _GroupsList<T> extends StatelessWidget {
  const _GroupsList({
    required this.title,
    required this.stream,
    required this.item,
  });
  final String title;
  final AsyncValue<List<T>> stream;
  final Widget Function(T item) item;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionTitle(title),
      Expanded(
        child: stream.when(
          data: (items) => items.isEmpty
              ? const Center(child: Text('No hay elementos todavía.'))
              : ListView.builder(
                  key: Key('${title.toLowerCase()}-list'),
                  itemCount: items.length,
                  itemBuilder: (_, index) => item(items[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('No fue posible cargar: $error')),
        ),
      ),
    ],
  );
}

class _TrackDetail extends ConsumerWidget {
  const _TrackDetail({required this.title, required this.tracks});
  final String title;
  final Stream<List<Track>> tracks;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          IconButton(
            key: const Key('library-entity-back-button'),
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => ref.read(appDestinationProvider.notifier).back(),
          ),
          Expanded(child: SectionTitle(title)),
        ],
      ),
      Expanded(
        child: StreamBuilder<List<Track>>(
          stream: tracks,
          builder: (context, snapshot) {
            final items = snapshot.data;
            if (items == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () => ref
                                .read(libraryControllerProvider.notifier)
                                .playAll(items),
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Reproducir (${items.length})'),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: const Key('library-entity-track-list'),
                    itemExtent: 56,
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final track = items[index];
                      final controller = ref.read(
                        libraryControllerProvider.notifier,
                      );
                      return ListTile(
                        enabled: track.isAvailable,
                        leading: TrackArtwork(track: track, size: 48),
                        title: Text(track.title),
                        subtitle: Text(track.artist ?? 'Artista desconocido'),
                        onTap: track.isAvailable
                            ? () => controller.playVisibleQueue(
                                items,
                                startIndex: index,
                              )
                            : controller.showUnavailableMessage,
                        trailing: PopupMenuButton<_TrackAction>(
                          tooltip: 'Acciones de ${track.title}',
                          onSelected: (action) => switch (action) {
                            _TrackAction.addToQueue => controller.addToQueue(
                              track,
                            ),
                            _TrackAction.toggleFavorite when track.id != null =>
                              ref
                                  .read(trackRepositoryProvider)
                                  .setFavorite(track.id!, !track.isFavorite),
                            _ => null,
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: _TrackAction.addToQueue,
                              child: Text('Añadir a la cola'),
                            ),
                            if (track.id != null)
                              PopupMenuItem(
                                value: _TrackAction.toggleFavorite,
                                child: Text(
                                  track.isFavorite
                                      ? 'Quitar de favoritos'
                                      : 'Añadir a favoritos',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

enum _TrackAction { addToQueue, toggleFavorite }
