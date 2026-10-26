import 'dart:async';

import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/platform/android_system_settings.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/dynamic_artwork_color.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
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
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

const desktopBreakpoint = 840.0;

final androidSystemSettingsProvider = Provider<AndroidSystemSettings>(
  (ref) => const SystemAndroidSettings(),
);

class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key});

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(artworkBackfillServiceProvider).runOnce());
    });
  }

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
                        child: PlaylistCover(playlist: playlist, size: 40),
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
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  });

  final String tooltip;
  final IconData? icon;
  final Widget? child;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 56,
      child: IconButton(
        tooltip: tooltip,
        padding: const EdgeInsets.all(16),
        onPressed: onPressed,
        icon: child ?? Icon(icon),
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
    final content = AstraBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (navigation.canGoBack)
                  IconButton(
                    key: const Key('desktop-back-button'),
                    tooltip: 'Volver',
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
          Expanded(
            child: _DestinationBody(destination: destination, desktop: true),
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (navigation.canGoBack) navigation.back();
        },
      },
      child: Focus(autofocus: true, child: content),
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
            child: _DestinationBody(destination: destination, desktop: false),
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
  const _DestinationBody({required this.destination, required this.desktop});

  final AppDestination destination;
  final bool desktop;

  @override
  Widget build(BuildContext context) => switch (destination.type) {
    AppDestinationType.home => HomeDestination(desktop: desktop),
    AppDestinationType.search => SearchDestination(desktop: desktop),
    AppDestinationType.library => const PlaylistsDestination(),
    AppDestinationType.playlist => PlaylistDetailScreen(
      playlistId: destination.playlistId!,
      embedded: true,
    ),
    AppDestinationType.queue => const QueueScreen(embedded: true),
    AppDestinationType.folders => const MusicFoldersView(),
    AppDestinationType.settings => const SettingsDestination(),
    AppDestinationType.diagnostics => const DiagnosticsDestination(),
  };
}

class HomeDestination extends ConsumerWidget {
  const HomeDestination({required this.desktop, super.key});

  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(allLibraryTracksProvider);
    final shortcuts = ref.watch(homePlaylistShortcutsProvider);
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
      key: const Key('home-destination'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Inicio'),
        Expanded(
          key: const Key('destination-content'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shortcuts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _HomeShortcutGrid(
                    shortcuts: shortcuts,
                    desktop: desktop,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Canciones recientes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    PlayCircleButton(
                      key: const Key('home-play-all-button'),
                      size: 48,
                      onPressed: state.actionsDisabled
                          ? null
                          : () => tracks.whenData((items) {
                              final recent = _byNewest(items);
                              controller.playAll(recent);
                            }),
                      isPlaying: ref.watch(
                        playerControllerProvider.select(
                          (state) => state.isPlaying,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('home-shuffle-button'),
                      tooltip: 'Aleatorio',
                      onPressed: state.actionsDisabled
                          ? null
                          : () => tracks.whenData((items) {
                              final recent = _byNewest(items);
                              controller.playAll(recent, shuffle: true);
                            }),
                      icon: const Icon(Icons.shuffle),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tracks.when(
                  data: (items) {
                    final recent = _byNewest(items);
                    return recent.isEmpty
                        ? _EmptyTracksState(desktop: desktop)
                        : _ResponsiveTrackList(
                            tracks: recent,
                            desktop: desktop,
                          );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => Center(
                    child: Text('No fue posible cargar la biblioteca: $error'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<Track> _byNewest(List<Track> tracks) => [...tracks]
  ..sort((a, b) {
    final byDate = b.dateAdded.compareTo(a.dateAdded);
    return byDate != 0 ? byDate : (b.id ?? -1).compareTo(a.id ?? -1);
  });

class _HomeShortcutGrid extends StatelessWidget {
  const _HomeShortcutGrid({required this.shortcuts, required this.desktop});

  final List<HomePlaylistShortcut> shortcuts;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('home-shortcut-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: desktop ? 4 : 2,
        mainAxisExtent: 64,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: shortcuts.length,
      itemBuilder: (_, index) => _HomeShortcutTile(
        shortcut: shortcuts[index],
        showPlayOnHover: desktop,
      ),
    );
  }
}

class _HomeShortcutTile extends ConsumerStatefulWidget {
  const _HomeShortcutTile({
    required this.shortcut,
    required this.showPlayOnHover,
  });

  final HomePlaylistShortcut shortcut;
  final bool showPlayOnHover;

  @override
  ConsumerState<_HomeShortcutTile> createState() => _HomeShortcutTileState();
}

class _HomeShortcutTileState extends ConsumerState<_HomeShortcutTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final shortcut = widget.shortcut;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        key: ValueKey(
          shortcut.isFavorites
              ? 'home-shortcut-favorites'
              : 'home-shortcut-${shortcut.playlist!.id}',
        ),
        color: context.astraColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPlaylist(
            context,
            ref,
            shortcut.isFavorites ? favoritesPlaylistId : shortcut.playlist!.id,
          ),
          child: Row(
            children: [
              if (shortcut.isFavorites)
                const FavoritesArtwork(size: 64)
              else
                PlaylistCover(playlist: shortcut.playlist!, size: 64),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shortcut.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (widget.showPlayOnHover && _hovered)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PlayCircleButton(
                    key: ValueKey(
                      shortcut.isFavorites
                          ? 'home-shortcut-play-favorites'
                          : 'home-shortcut-play-${shortcut.playlist!.id}',
                    ),
                    size: 44,
                    isPlaying: false,
                    onPressed: () => unawaited(_play(shortcut)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _play(HomePlaylistShortcut shortcut) async {
    final library = ref.read(libraryControllerProvider.notifier);
    if (shortcut.isFavorites) {
      final tracks = await ref
          .read(trackRepositoryProvider)
          .watchFavorites()
          .first;
      await library.playAll(tracks);
      return;
    }
    final playlist = shortcut.playlist!;
    final tracks = await ref
        .read(playlistRepositoryProvider)
        .watchTracks(playlist.id)
        .first;
    await library.playPlaylist(playlist.id, tracks);
  }
}

class SearchDestination extends ConsumerWidget {
  const SearchDestination({required this.desktop, super.key});

  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(librarySearchQueryProvider).trim();
    final tracks = ref.watch(libraryTracksProvider);
    final playlists = ref.watch(playlistsProvider);
    final normalized = normalizeForSearch(query);
    return Column(
      key: const Key('search-destination'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Buscar'),
        if (!desktop)
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
        Expanded(
          key: const Key('destination-content'),
          child: normalized.isEmpty
              ? const Center(
                  child: Text(
                    'Busca canciones, artistas, álbumes o playlists.',
                  ),
                )
              : tracks.when(
                  data: (trackWindow) => playlists.when(
                    data: (playlistItems) {
                      final trackItems = trackWindow.items;
                      final matches = playlistItems
                          .where(
                            (playlist) =>
                                normalizeForSearch(playlist.name)
                                    .contains(normalized),
                          )
                          .toList();
                      if (trackItems.isEmpty && matches.isEmpty) {
                        return const Center(child: Text('No hay resultados.'));
                      }
                      return CustomScrollView(
                        key: const Key('search-results'),
                        scrollCacheExtent: const ScrollCacheExtent.pixels(280),
                        slivers: [
                          if (trackItems.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: SectionTitle('Canciones'),
                            ),
                            SliverFixedExtentList(
                              itemExtent: 56,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (trackWindow.hasMore &&
                                      index == trackItems.length - 1) {
                                    scheduleMicrotask(
                                      ref
                                          .read(
                                            libraryTrackLimitProvider.notifier,
                                          )
                                          .loadMore,
                                    );
                                  }
                                  return _TrackListTile(
                                    track: trackItems[index],
                                    tracks: trackItems,
                                    index: index,
                                  );
                                },
                                childCount: trackItems.length,
                                addAutomaticKeepAlives: false,
                              ),
                            ),
                          ],
                          if (matches.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: SectionTitle('Playlists'),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _PlaylistTile(
                                  playlist: matches[index],
                                  onTap: () => _openPlaylist(
                                    context,
                                    ref,
                                    matches[index].id,
                                  ),
                                ),
                                childCount: matches.length,
                                addAutomaticKeepAlives: false,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(child: Text('$error')),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('$error')),
                ),
        ),
      ],
    );
  }
}

class _EmptyTracksState extends ConsumerWidget {
  const _EmptyTracksState({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('La biblioteca está vacía.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('empty-library-action'),
            onPressed: desktop ? controller.startScan : controller.addFiles,
            icon: Icon(
              desktop ? Icons.create_new_folder_outlined : Icons.audio_file,
            ),
            label: Text(desktop ? 'Añadir carpeta' : 'Añadir archivos'),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveTrackList extends StatelessWidget {
  const _ResponsiveTrackList({required this.tracks, required this.desktop});

  final List<Track> tracks;
  final bool desktop;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => desktop
        ? _DesktopTrackTable(
            tracks: tracks,
            showAlbum: constraints.maxWidth >= 1100,
          )
        : _MobileTrackList(tracks: tracks),
  );
}

class _MobileTrackList extends ConsumerStatefulWidget {
  const _MobileTrackList({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_MobileTrackList> createState() => _MobileTrackListState();
}

class _MobileTrackListState extends ConsumerState<_MobileTrackList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PerformanceDiagnostics.instance.recordListBuild();
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: MediaQuery.sizeOf(context).width >= desktopBreakpoint,
      child: ListView.builder(
        key: const Key('shell-track-list'),
        controller: _scrollController,
        itemExtent: 56,
        scrollCacheExtent: const ScrollCacheExtent.pixels(280),
        addAutomaticKeepAlives: false,
        itemCount: widget.tracks.length,
        itemBuilder: (context, index) {
          return _TrackListTile(
            track: widget.tracks[index],
            tracks: widget.tracks,
            index: index,
          );
        },
      ),
    );
  }
}

class _TrackListTile extends ConsumerWidget {
  const _TrackListTile({
    required this.track,
    required this.tracks,
    required this.index,
  });

  final Track track;
  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return TrackTile(
      track: track,
      showDateAdded: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_trackDuration(track.duration)),
          _TrackActionsMenu(track: track),
        ],
      ),
      onTap: track.isAvailable
          ? () => controller.playVisibleQueue(tracks, startIndex: index)
          : controller.showUnavailableMessage,
    );
  }
}

class _DesktopTrackTable extends StatelessWidget {
  const _DesktopTrackTable({required this.tracks, required this.showAlbum});

  final List<Track> tracks;
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    PerformanceDiagnostics.instance.recordListBuild();
    return Column(
      children: [
        _DesktopTrackHeader(showAlbum: showAlbum),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const Key('desktop-track-table'),
            itemExtent: 56,
            scrollCacheExtent: const ScrollCacheExtent.pixels(280),
            addAutomaticKeepAlives: false,
            itemCount: tracks.length,
            itemBuilder: (_, index) => _DesktopTrackRow(
              track: tracks[index],
              tracks: tracks,
              index: index,
              showAlbum: showAlbum,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopTrackHeader extends StatelessWidget {
  const _DesktopTrackHeader({required this.showAlbum});
  final bool showAlbum;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        const SizedBox(width: 56, child: Center(child: Text('#'))),
        const Expanded(flex: 5, child: Text('Título')),
        if (showAlbum)
          const Expanded(
            key: Key('desktop-album-header'),
            flex: 3,
            child: Text('Álbum'),
          ),
        const SizedBox(width: 128, child: Text('Fecha de adición')),
        const SizedBox(width: 96, child: Text('Duración')),
        const SizedBox(width: 48),
      ],
    ),
  );
}

class _DesktopTrackRow extends ConsumerWidget {
  const _DesktopTrackRow({
    required this.track,
    required this.tracks,
    required this.index,
    required this.showAlbum,
  });

  final Track track;
  final List<Track> tracks;
  final int index;
  final bool showAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(
      playerControllerProvider.select((state) => state.currentItem?.trackId),
    );
    final current = track.id != null && track.id == currentId;
    final color = current ? context.astraColors.accent : null;
    final controller = ref.read(libraryControllerProvider.notifier);
    return SizedBox(
      height: 56,
      child: Material(
        color: current
            ? context.astraColors.surfaceHover
            : context.astraColors.surface.withValues(alpha: 0),
        child: InkWell(
          hoverColor: context.astraColors.surfaceHover,
          onTap: track.isAvailable
              ? () => controller.playVisibleQueue(tracks, startIndex: index)
              : controller.showUnavailableMessage,
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Center(
                  child: current
                      ? Icon(
                          Icons.graphic_eq,
                          key: ValueKey('current-track-indicator-${track.id}'),
                          color: color,
                          size: 20,
                        )
                      : Text('${index + 1}'),
                ),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    TrackArtwork(track: track, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color),
                          ),
                          Text(
                            track.artist ?? 'Artista desconocido',
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
              if (showAlbum)
                Expanded(
                  key: ValueKey('desktop-album-${track.id}'),
                  flex: 3,
                  child: Text(
                    track.album ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              SizedBox(
                key: ValueKey('desktop-date-added-${track.id}'),
                width: 128,
                child: Text(formatTrackDate(track.dateAdded)),
              ),
              SizedBox(width: 96, child: Text(_trackDuration(track.duration))),
              SizedBox(width: 48, child: _TrackActionsMenu(track: track)),
            ],
          ),
        ),
      ),
    );
  }
}

String _trackDuration(Duration? duration) {
  if (duration == null) return '—';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _TrackActionsMenu extends ConsumerWidget {
  const _TrackActionsMenu({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return PopupMenuButton<_ShellTrackAction>(
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
            track.isFavorite ? 'Quitar de Me gusta' : 'Añadir a Me gusta',
          ),
        ),
        const PopupMenuItem(
          value: _ShellTrackAction.delete,
          child: Text('Eliminar de la biblioteca'),
        ),
      ],
    );
  }
}

enum _ShellTrackAction { playNext, addToQueue, addToPlaylist, favorite, delete }

class PlaylistsDestination extends ConsumerWidget {
  const PlaylistsDestination({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final favoriteCount = ref.watch(favoriteTracksProvider).value?.length ?? 0;
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
          ListTile(
            key: const Key('library-settings-button'),
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

class SettingsDestination extends ConsumerWidget {
  const SettingsDestination({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    final state = ref.watch(libraryControllerProvider);
    final isAndroid = ref.watch(isAndroidPlatformProvider);
    final notificationPermissionGranted = ref.watch(
      notificationPermissionGrantedProvider,
    );
    final systemSettings = ref.read(androidSystemSettingsProvider);
    ref.listen<String?>(
      libraryControllerProvider.select((value) => value.message),
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
        key: const Key('settings-destination'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SettingsHeader(),
          Expanded(
            key: const Key('destination-content'),
            child: ListView(
              children: [
                if (isAndroid && !notificationPermissionGranted)
                  ListTile(
                    key: const Key('settings-notification-warning'),
                    leading: const Icon(Icons.notifications_off_outlined),
                    title: const Text('Notificaciones desactivadas'),
                    subtitle: const Text(
                      'La música seguirá funcionando, pero Android puede '
                      'ocultar los controles de reproducción.',
                    ),
                    trailing: TextButton(
                      key: const Key('open-notification-settings'),
                      onPressed: systemSettings.openAppNotificationSettings,
                      child: const Text('Abrir ajustes'),
                    ),
                  ),
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
                if (kDebugMode)
                  ListTile(
                    key: const Key('settings-diagnostics-button'),
                    leading: const Icon(Icons.speed_outlined),
                    title: const Text('Diagnóstico'),
                    onTap: () => ref
                        .read(appDestinationProvider.notifier)
                        .select(AppDestination.diagnostics),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  enabled: !state.actionsDisabled,
                  onTap: () => _confirmClearLibrary(context, controller),
                ),
                if (isAndroid) ...[
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('background-playback-settings'),
                    leading: const Icon(Icons.battery_saver_outlined),
                    title: const Text('Reproducción en segundo plano'),
                    subtitle: const Text(
                      'Algunos fabricantes, como Samsung, cierran apps en '
                      'segundo plano. En Samsung: Batería → Límites de uso en '
                      'segundo plano → quita AstraMusic de Apps en suspensión '
                      'y añádela a Apps que nunca se suspenden.',
                    ),
                    trailing: TextButton(
                      key: const Key('open-battery-settings'),
                      onPressed: systemSettings.openBatteryOptimizationSettings,
                      child: const Text('Optimización'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('settings-brand-header'),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Row(
      children: [
        Image.asset(
          'assets/branding/logo.png',
          key: const Key('settings-brand-logo'),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'AstraMusic',
            key: const Key('settings-brand-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ],
    ),
  );
}

class DiagnosticsDestination extends ConsumerStatefulWidget {
  const DiagnosticsDestination({super.key});

  @override
  ConsumerState<DiagnosticsDestination> createState() =>
      _DiagnosticsDestinationState();
}

class _DiagnosticsDestinationState
    extends ConsumerState<DiagnosticsDestination> {
  late final Future<int> _artworkCacheBytes;

  @override
  void initState() {
    super.initState();
    _artworkCacheBytes = ref.read(artworkCacheProvider).sizeBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('diagnostics-destination'),
      color: context.astraColors.surface.withValues(alpha: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Diagnóstico',
            trailing: IconButton(
              key: const Key('close-diagnostics-button'),
              tooltip: 'Volver a Ajustes',
              onPressed: ref.read(appDestinationProvider.notifier).back,
              icon: const Icon(Icons.close),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<PerformanceSnapshot>(
              valueListenable: PerformanceDiagnostics.instance,
              builder: (context, snapshot, _) => ListView(
                children: [
                  _DiagnosticTile(
                    label: 'Canciones',
                    value: '${snapshot.songCount}',
                  ),
                  _DiagnosticTile(
                    label: 'Arranque hasta primer frame',
                    value: _durationLabel(snapshot.firstFrame),
                  ),
                  _DiagnosticTile(
                    label: 'Arranque hasta cargar biblioteca',
                    value: _durationLabel(snapshot.libraryLoad),
                  ),
                  _DiagnosticTile(
                    label: 'Última carga de cola',
                    value: _durationLabel(snapshot.lastQueueLoad),
                  ),
                  _DiagnosticTile(
                    label: 'Caché de imágenes',
                    value:
                        '${PaintingBinding.instance.imageCache.currentSizeBytes} bytes',
                  ),
                  FutureBuilder<int>(
                    future: _artworkCacheBytes,
                    builder: (context, bytes) => _DiagnosticTile(
                      label: 'Caché de carátulas',
                      value: bytes.hasData
                          ? '${bytes.data} bytes'
                          : 'Midiendo…',
                    ),
                  ),
                  _DiagnosticTile(
                    label: 'Reconstrucciones del listado',
                    value: '${snapshot.listBuilds}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), trailing: Text(value));
}

String _durationLabel(Duration? duration) =>
    duration == null ? 'Sin datos' : '${duration.inMilliseconds} ms';

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

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.astraColors.surface.withValues(alpha: 0),
    child: ListTile(
      key: ValueKey('library-playlist-${playlist.id}'),
      leading: PlaylistCover(playlist: playlist, size: 48),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(playlistTrackCount(playlist.trackCount)),
      onTap: onTap,
    ),
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
    final playback = ref.watch(
      playerControllerProvider.select(
        (state) => (state.currentItem!, state.status, state.isPlaying),
      ),
    );
    final item = playback.$1;
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
      child: DynamicArtworkColorBuilder(
        track: track,
        builder: (context, dynamicColor) => Material(
          key: const Key('mobile-mini-player'),
          color: dynamicColor ?? context.astraColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(playerScreenRoute(context)),
            child: SizedBox(
              height: 64,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Hero(
                            tag: playerArtworkHeroTag(item.path),
                            transitionOnUserGestures: true,
                            child: TrackArtwork(
                              track: track,
                              size: 46,
                              usage: ArtworkUsage.miniPlayer,
                            ),
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
                          onPressed: playback.$2 == AudioPlaybackStatus.error
                              ? null
                              : ref
                                    .read(playerControllerProvider.notifier)
                                    .togglePlayback,
                          isPlaying: playback.$3,
                          size: 48,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const _MobileMiniProgress(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMiniProgress extends ConsumerWidget {
  const _MobileMiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      playerControllerProvider.select(
        (state) => (state.position, state.duration),
      ),
    );
    final duration = progress.$2?.inMilliseconds ?? 0;
    final value = duration <= 0
        ? 0.0
        : (progress.$1.inMilliseconds / duration).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      key: const Key('mobile-mini-progress'),
      value: value,
      minHeight: 2,
      backgroundColor: context.astraColors.divider,
      color: context.astraColors.photon,
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
    final state = ref.watch(
      playerControllerProvider.select(
        (state) => (
          state.currentItem,
          state.status,
          state.isPlaying,
          state.shuffleEnabled,
          state.repeatMode,
          state.volume,
        ),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final (item, status, isPlaying, shuffleEnabled, repeatMode, volume) = state;
    final enabled = item != null && status != AudioPlaybackStatus.error;
    if (volume > 0) _lastAudibleVolume = volume;

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
                          color: shuffleEnabled
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
                          isPlaying: isPlaying,
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
                          color: repeatMode == RepeatMode.off
                              ? null
                              : context.astraColors.accent,
                          onPressed: enabled
                              ? controller.cycleRepeatMode
                              : null,
                          icon: Icon(
                            repeatMode == RepeatMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                          ),
                        ),
                      ],
                    ),
                    _DesktopProgressControls(enabled: enabled),
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
                    tooltip: volume == 0 ? 'Restaurar volumen' : 'Silenciar',
                    onPressed: () => controller.setVolume(
                      volume == 0 ? _lastAudibleVolume : 0,
                    ),
                    icon: Icon(
                      volume == 0 ? Icons.volume_off : Icons.volume_up,
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
                        value: volume.clamp(0.0, 1.0),
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

class _DesktopProgressControls extends ConsumerWidget {
  const _DesktopProgressControls({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      playerControllerProvider.select(
        (state) => (state.position, state.duration),
      ),
    );
    return SizedBox(
      height: 32,
      child: SeekBar(
        compact: true,
        position: progress.$1,
        duration: progress.$2,
        onSeek: enabled
            ? ref.read(playerControllerProvider.notifier).seek
            : null,
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
      onTap: () => Navigator.of(context).push(playerScreenRoute(context)),
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
