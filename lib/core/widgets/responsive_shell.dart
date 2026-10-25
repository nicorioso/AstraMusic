import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/library_screen.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:astramusic/features/player/presentation/seek_bar.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const desktopBreakpoint = 840.0;

class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= desktopBreakpoint
          ? const DesktopShell(key: Key('desktop-shell'))
          : const MobileShell(key: Key('mobile-shell')),
    );
  }
}

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  var _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    key: const Key('desktop-sidebar'),
                    width: _collapsed ? 72 : 300,
                    child: _DesktopSidebar(
                      collapsed: _collapsed,
                      onToggle: () => setState(() => _collapsed = !_collapsed),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      key: const Key('desktop-content-panel'),
                      margin: const EdgeInsets.all(8),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: context.astraColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const _DesktopCenter(),
                    ),
                  ),
                ],
              ),
            ),
            const DesktopPlayerBar(),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void selectLibrary() => ref
        .read(appDestinationProvider.notifier)
        .select(AppDestination.library);
    final playlists = ref.watch(playlistsProvider);
    final favoriteCount = ref.watch(favoriteTracksProvider).value?.length ?? 0;

    if (collapsed) {
      return Material(
        color: context.astraColors.surface,
        child: Column(
          children: [
            _CollapsedSidebarButton(
              key: const Key('collapsed-library-button'),
              tooltip: 'Tu biblioteca',
              icon: Icons.library_music_outlined,
              onPressed: selectLibrary,
            ),
            _CollapsedSidebarButton(
              key: const Key('expand-sidebar-button'),
              tooltip: 'Expandir barra lateral',
              icon: Icons.chevron_right,
              onPressed: onToggle,
            ),
            _CollapsedSidebarButton(
              key: const Key('collapsed-create-playlist-button'),
              tooltip: 'Crear playlist',
              icon: Icons.add,
              onPressed: () => createPlaylist(context, ref),
            ),
            Expanded(
              child: playlists.when(
                data: (items) => ListView(
                  children: [
                    _CollapsedSidebarButton(
                      key: const Key('collapsed-favorites-button'),
                      tooltip: 'Canciones que te gustan',
                      icon: Icons.favorite,
                      onPressed: () => ref
                          .read(appDestinationProvider.notifier)
                          .select(AppDestination.playlist(favoritesPlaylistId)),
                    ),
                    for (final playlist in items)
                      _CollapsedSidebarButton(
                        key: ValueKey('collapsed-playlist-${playlist.id}'),
                        tooltip: playlist.name,
                        icon: Icons.music_note,
                        onPressed: () => ref
                            .read(appDestinationProvider.notifier)
                            .select(AppDestination.playlist(playlist.id)),
                      ),
                  ],
                ),
                loading: () => const SizedBox(),
                error: (_, _) => const SizedBox(),
              ),
            ),
            _CollapsedSidebarButton(
              key: const Key('collapsed-settings-button'),
              tooltip: 'Ajustes',
              icon: Icons.settings_outlined,
              onPressed: () => ref
                  .read(appDestinationProvider.notifier)
                  .select(AppDestination.settings),
            ),
          ],
        ),
      );
    }

    return Material(
      color: context.astraColors.surface,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Tu biblioteca'),
            trailing: IconButton(
              tooltip: 'Plegar barra lateral',
              onPressed: onToggle,
              icon: const Icon(Icons.chevron_left),
            ),
            onTap: selectLibrary,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              key: const Key('desktop-create-playlist-button'),
              onPressed: () => createPlaylist(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Crear'),
            ),
          ),
          Expanded(
            child: playlists.when(
              data: (items) => items.isEmpty
                  ? ListView(
                      children: [
                        _FavoritesTile(count: favoriteCount),
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Aún no tienes playlists',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      key: const Key('desktop-playlist-list'),
                      itemCount: items.length + 1,
                      itemBuilder: (_, index) {
                        if (index == 0) {
                          return _FavoritesTile(count: favoriteCount);
                        }
                        final playlist = items[index - 1];
                        return ListTile(
                          key: ValueKey('sidebar-playlist-${playlist.id}'),
                          leading: PlaylistCover(playlist: playlist, size: 44),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            playlistTrackCount(playlist.trackCount),
                          ),
                          onTap: () => ref
                              .read(appDestinationProvider.notifier)
                              .select(AppDestination.playlist(playlist.id)),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Ajustes'),
            onTap: () => ref
                .read(appDestinationProvider.notifier)
                .select(AppDestination.settings),
          ),
        ],
      ),
    );
  }
}

class _CollapsedSidebarButton extends StatelessWidget {
  const _CollapsedSidebarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 56,
      child: IconButton(
        tooltip: tooltip,
        padding: const EdgeInsets.all(16),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _DesktopCenter extends ConsumerWidget {
  const _DesktopCenter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(appDestinationProvider);
    final navigation = ref.read(appDestinationProvider.notifier);
    return AstraBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (navigation.canGoBack)
                  IconButton(
                    key: const Key('desktop-back-button'),
                    tooltip: 'Atrás',
                    onPressed: navigation.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                IconButton(
                  key: const Key('desktop-home-button'),
                  tooltip: 'Inicio',
                  onPressed: () => ref
                      .read(appDestinationProvider.notifier)
                      .select(AppDestination.home),
                  icon: const Icon(Icons.home_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('desktop-search-field'),
                    onChanged: (query) {
                      ref
                          .read(librarySearchQueryProvider.notifier)
                          .update(query);
                      ref
                          .read(appDestinationProvider.notifier)
                          .select(AppDestination.search);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Buscar por título, artista o álbum',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _DestinationBody(destination: destination)),
        ],
      ),
    );
  }
}

class MobileShell extends ConsumerWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(appDestinationProvider);
    final navigation = ref.read(appDestinationProvider.notifier);
    final hasCurrent = ref.watch(
      playerControllerProvider.select((state) => state.currentItem != null),
    );
    return PopScope(
      canPop: !navigation.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && navigation.canGoBack) navigation.back();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AstraBackground(
            child: _DestinationBody(destination: destination),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasCurrent) const MobileMiniPlayer(),
              NavigationBar(
                selectedIndex: destination.navigationIndex,
                onDestinationSelected: (index) => ref
                    .read(appDestinationProvider.notifier)
                    .select(
                      [
                        AppDestination.home,
                        AppDestination.search,
                        AppDestination.library,
                      ][index],
                    ),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search),
                    label: 'Buscar',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Biblioteca',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationBody extends StatelessWidget {
  const _DestinationBody({required this.destination});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) => switch (destination.type) {
    AppDestinationType.home => const SongsDestination(showSearch: false),
    AppDestinationType.search => const SongsDestination(showSearch: true),
    AppDestinationType.library => const PlaylistsDestination(),
    AppDestinationType.playlist => PlaylistDetailScreen(
      playlistId: destination.playlistId!,
      embedded: true,
    ),
    AppDestinationType.queue => const QueueScreen(embedded: true),
    AppDestinationType.folders => const MusicFoldersView(),
    AppDestinationType.settings => const PlaylistsDestination(),
  };
}

class SongsDestination extends ConsumerWidget {
  const SongsDestination({required this.showSearch, super.key});

  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryTracksProvider);
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    ref.listen<String?>(
      libraryControllerProvider.select((state) => state.message),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearMessage();
      },
    );
    return Column(
      key: Key(showSearch ? 'search-destination' : 'home-destination'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(showSearch ? 'Buscar' : 'Inicio'),
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const Key('mobile-search-field'),
              onChanged: ref.read(librarySearchQueryProvider.notifier).update,
              decoration: const InputDecoration(
                hintText: 'Buscar por título, artista o álbum',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        if (!showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.actionsDisabled
                        ? null
                        : () => tracks.whenData(controller.playAll),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Reproducir todo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.actionsDisabled
                        ? null
                        : () => tracks.whenData(
                            (items) => controller.playAll(items, shuffle: true),
                          ),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Aleatorio'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          key: const Key('destination-content'),
          child: tracks.when(
            data: (items) => items.isEmpty
                ? Center(
                    child: Text(
                      showSearch
                          ? 'No hay resultados.'
                          : 'La biblioteca está vacía.',
                    ),
                  )
                : _ShellTrackList(tracks: items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Text('No fue posible cargar la biblioteca: $error'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellTrackList extends ConsumerStatefulWidget {
  const _ShellTrackList({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_ShellTrackList> createState() => _ShellTrackListState();
}

class _ShellTrackListState extends ConsumerState<_ShellTrackList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: MediaQuery.sizeOf(context).width >= desktopBreakpoint,
      child: ListView.builder(
        key: const Key('shell-track-list'),
        controller: _scrollController,
        itemCount: widget.tracks.length,
        itemBuilder: (context, index) {
          final track = widget.tracks[index];
          return TrackTile(
            track: track,
            trailing: PopupMenuButton<_ShellTrackAction>(
              tooltip: 'Acciones de ${track.title}',
              onSelected: (action) {
                switch (action) {
                  case _ShellTrackAction.playNext:
                    controller.playNext(track);
                  case _ShellTrackAction.addToQueue:
                    controller.addToQueue(track);
                  case _ShellTrackAction.addToPlaylist:
                    showAddTrackToPlaylist(context, ref, track);
                  case _ShellTrackAction.favorite:
                    ref
                        .read(trackRepositoryProvider)
                        .setFavorite(track.id!, !track.isFavorite);
                  case _ShellTrackAction.delete:
                    controller.deleteTrack(track);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ShellTrackAction.playNext,
                  enabled: track.isAvailable,
                  child: const Text('Reproducir a continuación'),
                ),
                PopupMenuItem(
                  value: _ShellTrackAction.addToQueue,
                  enabled: track.isAvailable,
                  child: const Text('Añadir a la cola'),
                ),
                const PopupMenuItem(
                  value: _ShellTrackAction.addToPlaylist,
                  child: Text('Añadir a playlist'),
                ),
                PopupMenuItem(
                  value: _ShellTrackAction.favorite,
                  child: Text(
                    track.isFavorite
                        ? 'Quitar de Me gusta'
                        : 'Añadir a Me gusta',
                  ),
                ),
                const PopupMenuItem(
                  value: _ShellTrackAction.delete,
                  child: Text('Eliminar de la biblioteca'),
                ),
              ],
            ),
            onTap: track.isAvailable
                ? () => controller.playVisibleQueue(
                    widget.tracks,
                    startIndex: index,
                  )
                : controller.showUnavailableMessage,
          );
        },
      ),
    );
  }
}

enum _ShellTrackAction { playNext, addToQueue, addToPlaylist, favorite, delete }

class PlaylistsDestination extends ConsumerWidget {
  const PlaylistsDestination({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    final state = ref.watch(libraryControllerProvider);
    final isAndroid = ref.watch(isAndroidPlatformProvider);
    final playlists = ref.watch(playlistsProvider);
    final favoriteCount = ref.watch(favoriteTracksProvider).value?.length ?? 0;
    ref.listen<String?>(
      libraryControllerProvider.select((state) => state.message),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearMessage();
      },
    );
    return Material(
      color: context.astraColors.surface.withValues(alpha: 0),
      child: Column(
        key: const Key('library-destination'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Tu biblioteca',
            trailing: IconButton(
              key: const Key('create-playlist-button'),
              tooltip: 'Crear playlist',
              onPressed: () => createPlaylist(context, ref),
              icon: const Icon(Icons.add),
            ),
          ),
          Expanded(
            key: const Key('destination-content'),
            child: playlists.when(
              data: (items) => ListView.builder(
                key: const Key('mobile-playlist-list'),
                itemCount: items.length + 1,
                itemBuilder: (_, index) => index == 0
                    ? _FavoritesTile(count: favoriteCount)
                    : _PlaylistTile(
                        playlist: items[index - 1],
                        onTap: () =>
                            _openPlaylist(context, ref, items[index - 1].id),
                      ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
            ),
          ),
          const Divider(height: 1),
          if (!isAndroid) ...[
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Carpetas de música'),
              onTap: () => ref
                  .read(appDestinationProvider.notifier)
                  .select(AppDestination.folders),
            ),
            ListTile(
              leading: const Icon(Icons.library_add_outlined),
              title: const Text('Añadir carpeta'),
              enabled: !state.actionsDisabled,
              onTap: controller.startScan,
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Actualizar biblioteca'),
              enabled: !state.actionsDisabled,
              onTap: controller.updateLibrary,
            ),
          ],
          ListTile(
            key: const Key('settings-add-files-button'),
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Añadir archivos'),
            enabled: !state.actionsDisabled,
            onTap: controller.addFiles,
          ),
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Cargar datos de prueba'),
              enabled: !state.actionsDisabled,
              onTap: controller.loadDebugTracks,
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Zona de peligro',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
          ListTile(
            key: const Key('clear-library-button'),
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Eliminar toda la biblioteca',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: !state.actionsDisabled,
            onTap: () => _confirmClearLibrary(context, controller),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearLibrary(
    BuildContext context,
    LibraryController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar toda la biblioteca'),
        content: const Text(
          'Se eliminarán de AstraMusic todas las canciones, las playlists '
          'creadas, la cola y las carpetas guardadas. Tus archivos del '
          'dispositivo NO se borran. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar todo'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.clearLibrary();
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('library-playlist-${playlist.id}'),
    leading: PlaylistCover(playlist: playlist, size: 48),
    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(playlistTrackCount(playlist.trackCount)),
    onTap: onTap,
  );
}

class _FavoritesTile extends ConsumerWidget {
  const _FavoritesTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: const Key('favorites-playlist-tile'),
    leading: const FavoritesArtwork(size: 48),
    title: const Text('Canciones que te gustan'),
    subtitle: Text(playlistTrackCount(count)),
    onTap: () => _openPlaylist(context, ref, favoritesPlaylistId),
  );
}

void _openPlaylist(BuildContext context, WidgetRef ref, int playlistId) {
  ref
      .read(appDestinationProvider.notifier)
      .select(AppDestination.playlist(playlistId));
}

class MobileMiniPlayer extends ConsumerWidget {
  const MobileMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final item = state.currentItem!;
    final track = Track(
      uri: item.path,
      title: item.title,
      artist: item.artist,
      duration: item.duration,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
      artworkPath: item.artworkPath,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        key: const Key('mobile-mini-player'),
        color: context.astraColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TrackArtwork(
                    track: track,
                    size: 48,
                    usage: ArtworkUsage.miniPlayer,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.artist ?? 'Artista desconocido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PlayCircleButton(
                  key: const Key('mobile-mini-play-button'),
                  onPressed: state.status == AudioPlaybackStatus.error
                      ? null
                      : ref
                            .read(playerControllerProvider.notifier)
                            .togglePlayback,
                  isPlaying: state.isPlaying,
                  size: 48,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopPlayerBar extends ConsumerStatefulWidget {
  const DesktopPlayerBar({super.key});

  @override
  ConsumerState<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends ConsumerState<DesktopPlayerBar> {
  double _lastAudibleVolume = 1;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final item = state.currentItem;
    final enabled = item != null && state.status != AudioPlaybackStatus.error;
    if (state.volume > 0) _lastAudibleVolume = state.volume;

    return Material(
      key: const Key('desktop-player-bar'),
      color: context.astraColors.surfaceRaised,
      child: SizedBox(
        height: 88,
        child: Row(
          children: [
            Expanded(flex: 3, child: _DesktopNowPlaying(item: item)),
            Expanded(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          key: const Key('desktop-shuffle-button'),
                          tooltip: 'Aleatorio',
                          color: state.shuffleEnabled
                              ? context.astraColors.accent
                              : null,
                          onPressed: enabled ? controller.toggleShuffle : null,
                          icon: const Icon(Icons.shuffle),
                        ),
                        IconButton(
                          key: const Key('desktop-previous-button'),
                          tooltip: 'Anterior',
                          onPressed: enabled ? controller.previous : null,
                          icon: const Icon(Icons.skip_previous),
                        ),
                        PlayCircleButton(
                          key: const Key('desktop-play-button'),
                          onPressed: enabled ? controller.togglePlayback : null,
                          isPlaying: state.isPlaying,
                          size: 44,
                        ),
                        IconButton(
                          key: const Key('desktop-next-button'),
                          tooltip: 'Siguiente',
                          onPressed: enabled ? controller.next : null,
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          key: const Key('desktop-repeat-button'),
                          tooltip: 'Repetir',
                          color: state.repeatMode == RepeatMode.off
                              ? null
                              : context.astraColors.accent,
                          onPressed: enabled
                              ? controller.cycleRepeatMode
                              : null,
                          icon: Icon(
                            state.repeatMode == RepeatMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 32,
                      child: SeekBar(
                        compact: true,
                        position: state.position,
                        duration: state.duration,
                        onSeek: enabled ? controller.seek : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                key: const Key('desktop-volume-zone'),
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('desktop-mute-button'),
                    tooltip: state.volume == 0
                        ? 'Restaurar volumen'
                        : 'Silenciar',
                    onPressed: () => controller.setVolume(
                      state.volume == 0 ? _lastAudibleVolume : 0,
                    ),
                    icon: Icon(
                      state.volume == 0 ? Icons.volume_off : Icons.volume_up,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 132,
                    child: SliderTheme(
                      data: Theme.of(context).sliderTheme.copyWith(
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        key: const Key('desktop-volume-slider'),
                        value: state.volume.clamp(0.0, 1.0),
                        onChanged: controller.setVolume,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNowPlaying extends StatelessWidget {
  const _DesktopNowPlaying({required this.item});

  final AudioItem? item;

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox();
    final track = Track(
      uri: item!.path,
      title: item!.title,
      artist: item!.artist,
      duration: item!.duration,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
      artworkPath: item!.artworkPath,
    );
    return InkWell(
      key: const Key('desktop-now-playing'),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            TrackArtwork(
              track: track,
              size: 56,
              usage: ArtworkUsage.miniPlayer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item!.artist ?? 'Artista desconocido',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
