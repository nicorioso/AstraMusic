import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/application/metadata_editor_service.dart';
import 'package:astramusic/features/library/presentation/metadata_editor_dialog.dart';
import 'package:astramusic/features/library/domain/track_list_query.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryTracksProvider);
    final filters = ref.watch(libraryTrackFiltersProvider);
    final libraryState = ref.watch(libraryControllerProvider);
    final currentPath = ref.watch(
      playerControllerProvider.select((state) => state.currentItem?.path),
    );
    final isAndroid = ref.watch(isAndroidPlatformProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);

    ref.listen<String?>(
      libraryControllerProvider.select((state) => state.message),
      (previous, next) {
        if (next == null || next == previous) return;
        final offerSettings = ref.read(
          libraryControllerProvider.select((state) => state.offerSettings),
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next),
              action: offerSettings
                  ? SnackBarAction(
                      label: 'Abrir ajustes',
                      onPressed: libraryController.openAppSettings,
                    )
                  : null,
            ),
          );
        libraryController.clearMessage();
      },
    );
    ref.listen<String?>(
      playerControllerProvider.select((state) => state.errorMessage),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        actions: [
          if (!isAndroid)
            IconButton(
              key: const Key('music-folders-button'),
              tooltip: 'Carpetas de música',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const MusicFoldersDialog(),
              ),
              icon: const Icon(Icons.folder_copy_outlined),
            ),
          PopupMenuButton<_LibraryAction>(
            tooltip: 'Más acciones',
            enabled: !libraryState.actionsDisabled,
            onSelected: (action) {
              switch (action) {
                case _LibraryAction.update:
                  unawaited(libraryController.updateLibrary());
                case _LibraryAction.addFiles:
                  unawaited(libraryController.addFiles());
                case _LibraryAction.loadDebugTracks:
                  unawaited(libraryController.loadDebugTracks());
              }
            },
            itemBuilder: (context) => [
              if (!isAndroid)
                const PopupMenuItem(
                  value: _LibraryAction.update,
                  child: Text('Actualizar biblioteca'),
                ),
              const PopupMenuItem(
                key: Key('add-files-menu-item'),
                value: _LibraryAction.addFiles,
                child: Text('Añadir archivos'),
              ),
              if (kDebugMode) ...const [
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _LibraryAction.loadDebugTracks,
                  child: Text('Cargar datos de prueba'),
                ),
              ],
            ],
          ),
        ],
      ),
      body: AstraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const Key('library-search-field'),
                  onChanged: ref
                      .read(librarySearchQueryProvider.notifier)
                      .update,
                  decoration: const InputDecoration(
                    hintText: 'Buscar por título, artista o álbum',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              _LibraryFilterBar(filters: filters),
              if (libraryState.scanActive)
                _ScanProgressCard(
                  foundCount: libraryState.foundCount,
                  errorCount: libraryState.scanErrorCount,
                  unchangedCount: libraryState.unchangedCount,
                  isCancelling: libraryState.isCancelling,
                  onCancel: libraryController.cancelScan,
                ),
              Expanded(
                child: tracks.when(
                  data: (window) => window.items.isEmpty
                      ? const _EmptyLibrary()
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      key: const Key('play-all-button'),
                                      onPressed: libraryState.actionsDisabled
                                          ? null
                                          : () => libraryController.playAll(
                                              window.items,
                                            ),
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('Reproducir todo'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      key: const Key('shuffle-all-button'),
                                      onPressed: libraryState.actionsDisabled
                                          ? null
                                          : () => libraryController.playAll(
                                              window.items,
                                              shuffle: true,
                                            ),
                                      icon: const Icon(Icons.shuffle),
                                      label: const Text('Aleatorio'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SectionTitle('Canciones'),
                            Expanded(
                              child: _TrackList(
                                tracks: window.items,
                                hasMore: window.hasMore,
                                onLoadMore: ref
                                    .read(libraryTrackLimitProvider.notifier)
                                    .loadMore,
                                enabled: !libraryState.actionsDisabled,
                                onTrackTap: (index) =>
                                    libraryController.playVisibleQueue(
                                      window.items,
                                      startIndex: index,
                                    ),
                                onUnavailable:
                                    libraryController.showUnavailableMessage,
                                onPlayNext: libraryController.playNext,
                                onAddToQueue: libraryController.addToQueue,
                                onAddToPlaylist: (track) =>
                                    showAddTrackToPlaylist(context, ref, track),
                                onEdit: (track) =>
                                    showMetadataEditor(context, track),
                                onFavorite: (track) => ref
                                    .read(trackRepositoryProvider)
                                    .setFavorite(track.id!, !track.isFavorite),
                                onDelete: libraryController.deleteTrack,
                              ),
                            ),
                          ],
                        ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      key: Key('library-loading-indicator'),
                    ),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No fue posible cargar la biblioteca: $error',
                        key: const Key('library-error'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isAndroid
          ? null
          : FloatingActionButton.extended(
              key: const Key('scan-library-button'),
              onPressed: libraryState.actionsDisabled
                  ? null
                  : libraryController.startScan,
              icon: libraryState.isBusy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.create_new_folder),
              label: const Text('Añadir carpeta'),
            ),
      bottomNavigationBar: currentPath != null ? const _MiniPlayer() : null,
    );
  }
}

class _LibraryFilterBar extends ConsumerWidget {
  const _LibraryFilterBar({required this.filters});
  final LibraryTrackFilterState filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryTrackFiltersProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            key: const Key('library-favorites-filter'),
            label: const Text('Favoritas'),
            selected: filters.favoritesOnly,
            onSelected: (_) => controller.toggleFavorites(),
          ),
          FilterChip(
            key: const Key('library-available-filter'),
            label: const Text('Disponibles'),
            selected: filters.availableOnly,
            onSelected: (_) => controller.toggleAvailable(),
          ),
          PopupMenuButton<TrackSort>(
            key: const Key('library-sort-menu'),
            tooltip: 'Ordenar',
            onSelected: controller.setSort,
            itemBuilder: (_) => TrackSort.values
                .map(
                  (sort) =>
                      PopupMenuItem(value: sort, child: Text(_sortLabel(sort))),
                )
                .toList(),
            child: Chip(
              avatar: const Icon(Icons.sort, size: 18),
              label: Text(_sortLabel(filters.sort)),
            ),
          ),
        ],
      ),
    );
  }
}

String _sortLabel(TrackSort sort) => switch (sort) {
  TrackSort.title => 'Nombre',
  TrackSort.dateAdded => 'Fecha de adición',
  TrackSort.artist => 'Artista',
  TrackSort.year => 'Año',
  TrackSort.duration => 'Duración',
};

class _ScanProgressCard extends StatelessWidget {
  const _ScanProgressCard({
    required this.foundCount,
    required this.errorCount,
    required this.unchangedCount,
    required this.isCancelling,
    required this.onCancel,
  });

  final int foundCount;
  final int errorCount;
  final int unchangedCount;
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('scan-progress'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isCancelling
                    ? 'Cancelando...'
                    : 'Escaneando: $foundCount encontradas, '
                          '$unchangedCount sin cambios, $errorCount errores',
                key: const Key('scan-progress-text'),
              ),
            ),
            if (!isCancelling)
              TextButton(onPressed: onCancel, child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}

class MusicFoldersDialog extends ConsumerWidget {
  const MusicFoldersDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersProvider);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
      child: SizedBox(
        width: 560,
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Text(
                'Carpetas de música',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: folders.when(
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No hay carpetas guardadas.'))
                    : ListView.builder(
                        key: const Key('music-folders-list'),
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _FolderTile(folder: items[index]),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No fue posible cargar las carpetas: $error'),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MusicFoldersView extends ConsumerWidget {
  const MusicFoldersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersProvider);
    return Column(
      key: const Key('music-folders-destination'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Carpetas de música'),
        Expanded(
          child: folders.when(
            data: (items) => items.isEmpty
                ? const Center(child: Text('No hay carpetas guardadas.'))
                : ListView.builder(
                    key: const Key('music-folders-list'),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _FolderTile(folder: items[index]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No fue posible cargar las carpetas: $error'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({required this.folder});

  final LibraryFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      minVerticalPadding: 0,
      title: Text(folder.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        folder.lastScannedAt == null
            ? 'Nunca escaneada'
            : 'Último escaneo: ${folder.lastScannedAt}',
      ),
      trailing: IconButton(
        tooltip: 'Quitar carpeta',
        onPressed: () async {
          final controller = ref.read(libraryControllerProvider.notifier);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Quitar carpeta'),
              content: const Text(
                'Se quitarán sus canciones de la biblioteca. '
                'Los archivos del disco no se borrarán.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Quitar'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await controller.removeFolder(folder);
          }
        },
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _TrackList extends ConsumerStatefulWidget {
  const _TrackList({
    required this.tracks,
    required this.hasMore,
    required this.onLoadMore,
    required this.enabled,
    required this.onTrackTap,
    required this.onUnavailable,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Track> tracks;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final bool enabled;
  final ValueChanged<int> onTrackTap;
  final VoidCallback onUnavailable;
  final ValueChanged<Track> onPlayNext;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onFavorite;
  final ValueChanged<Track> onEdit;
  final ValueChanged<Track> onDelete;

  @override
  ConsumerState<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends ConsumerState<_TrackList> {
  final Set<String> _selected = {};
  int? _anchor;

  void _select(int index) {
    final keys = HardwareKeyboard.instance;
    setState(() {
      if (keys.isShiftPressed && _anchor != null) {
        final start = _anchor! < index ? _anchor! : index;
        final end = _anchor! > index ? _anchor! : index;
        for (var i = start; i <= end; i++) {
          _selected.add(widget.tracks[i].uri);
        }
      } else if (keys.isControlPressed || keys.isMetaPressed) {
        if (!_selected.add(widget.tracks[index].uri)) {
          _selected.remove(widget.tracks[index].uri);
        }
        _anchor = index;
      } else {
        _selected
          ..clear()
          ..add(widget.tracks[index].uri);
        _anchor = index;
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      final uri = widget.tracks[index].uri;
      if (!_selected.add(uri)) _selected.remove(uri);
      _anchor = index;
    });
  }

  List<Track> get _chosen =>
      widget.tracks.where((track) => _selected.contains(track.uri)).toList();

  Future<void> _bulk(_TrackAction action) async {
    final chosen = _chosen;
    switch (action) {
      case _TrackAction.edit:
        if (chosen.length == 1) widget.onEdit(chosen.single);
      case _TrackAction.addToQueue:
        for (final track in chosen.where((track) => track.isAvailable)) {
          widget.onAddToQueue(track);
        }
      case _TrackAction.addToPlaylist:
        final messenger = ScaffoldMessenger.of(context);
        final repository = ref.read(playlistRepositoryProvider);
        final playlist = await createPlaylist(context, ref);
        if (playlist == null) return;
        try {
          await repository.addTracks(playlist.id, [
            for (final track in chosen)
              if (track.id != null) track.id!,
          ]);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Añadidas a ${playlist.name}')),
            );
          }
        } catch (error) {
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('No se pudieron añadir canciones: $error'),
              ),
            );
          }
        }
      case _TrackAction.delete:
        for (final track in chosen) {
          widget.onDelete(track);
        }
      case _TrackAction.playNext:
        for (final track in chosen.reversed.where(
          (track) => track.isAvailable,
        )) {
          widget.onPlayNext(track);
        }
      case _TrackAction.favorite:
        for (final track in chosen) {
          widget.onFavorite(track);
        }
    }
    if (mounted) setState(_selected.clear);
  }

  Future<void> _contextMenu(TapDownDetails details, int index) async {
    if (!_selected.contains(widget.tracks[index].uri)) _select(index);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_TrackAction>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _TrackAction.addToQueue,
          child: Text('Añadir selección a la cola'),
        ),
        PopupMenuItem(
          value: _TrackAction.addToPlaylist,
          child: Text('Añadir selección a playlist'),
        ),
        PopupMenuItem(
          value: _TrackAction.delete,
          child: Text('Eliminar selección'),
        ),
      ],
    );
    if (action != null && mounted) await _bulk(action);
  }

  @override
  Widget build(BuildContext context) {
    PerformanceDiagnostics.instance.recordListBuild();
    final tracks = widget.tracks;
    final hasMore = widget.hasMore;
    final enabled = widget.enabled;
    final onLoadMore = widget.onLoadMore;
    final onTrackTap = widget.onTrackTap;
    final onUnavailable = widget.onUnavailable;
    final onPlayNext = widget.onPlayNext;
    final onAddToQueue = widget.onAddToQueue;
    final onAddToPlaylist = widget.onAddToPlaylist;
    final onFavorite = widget.onFavorite;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    return Column(
      children: [
        if (_selected.isNotEmpty)
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Text('${_selected.length} seleccionadas'),
                TextButton(
                  onPressed: () => _bulk(_TrackAction.addToQueue),
                  child: const Text('A la cola'),
                ),
                TextButton(
                  onPressed: () => _bulk(_TrackAction.addToPlaylist),
                  child: const Text('Playlist'),
                ),
                TextButton(
                  onPressed: () => _bulk(_TrackAction.delete),
                  child: const Text('Eliminar'),
                ),
                IconButton(
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: const Key('library-track-list'),
            padding: const EdgeInsets.only(bottom: 88),
            itemExtent: 56,
            scrollCacheExtent: const ScrollCacheExtent.pixels(280),
            addAutomaticKeepAlives: false,
            itemCount: tracks.length + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == tracks.length) {
                scheduleMicrotask(onLoadMore);
                return const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      key: Key('library-page-loading-indicator'),
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              final track = tracks[index];
              return TrackTile(
                track: track,
                enabled: enabled,
                onSecondaryTapDown: (details) => _contextMenu(details, index),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 840)
                      Checkbox(
                        value: _selected.contains(track.uri),
                        onChanged: enabled ? (_) => _toggle(index) : null,
                      ),
                    if (track.duration case final duration?)
                      Text(_formatDuration(duration)),
                    PopupMenuButton<_TrackAction>(
                      tooltip: 'Acciones de ${track.title}',
                      enabled: enabled,
                      onSelected: (action) {
                        switch (action) {
                          case _TrackAction.playNext:
                            onPlayNext(track);
                          case _TrackAction.addToQueue:
                            onAddToQueue(track);
                          case _TrackAction.addToPlaylist:
                            onAddToPlaylist(track);
                          case _TrackAction.edit:
                            onEdit(track);
                          case _TrackAction.favorite:
                            onFavorite(track);
                          case _TrackAction.delete:
                            onDelete(track);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _TrackAction.playNext,
                          enabled: track.isAvailable,
                          child: const Text('Reproducir a continuación'),
                        ),
                        PopupMenuItem(
                          value: _TrackAction.addToQueue,
                          enabled: track.isAvailable,
                          child: const Text('Añadir a la cola'),
                        ),
                        const PopupMenuItem(
                          value: _TrackAction.addToPlaylist,
                          child: Text('Añadir a playlist'),
                        ),
                        PopupMenuItem(
                          value: _TrackAction.favorite,
                          child: Text(
                            track.isFavorite
                                ? 'Quitar de Me gusta'
                                : 'Añadir a Me gusta',
                          ),
                        ),
                        PopupMenuItem(
                          value: _TrackAction.edit,
                          enabled: canEditTrackMetadata(track),
                          child: const Text('Editar metadatos'),
                        ),
                        const PopupMenuItem(
                          value: _TrackAction.delete,
                          child: Text('Eliminar de la biblioteca'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: !enabled
                    ? null
                    : track.isAvailable
                    ? () {
                        if (HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed ||
                            HardwareKeyboard.instance.isShiftPressed ||
                            _selected.isNotEmpty) {
                          _select(index);
                        } else {
                          onTrackTap(index);
                        }
                      }
                    : onUnavailable,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'La biblioteca está vacía. Escanea tu música para comenzar.',
          key: Key('empty-library-message'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _MiniPlayer extends ConsumerWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.watch(
      playerControllerProvider.select(
        (state) =>
            (state.currentItem, state.status, state.isPlaying, state.isLoading),
      ),
    );
    final (currentItem, status, isPlaying, isLoading) = state;
    return SafeArea(
      top: false,
      child: Material(
        color: context.astraColors.surfaceRaised,
        child: InkWell(
          key: const Key('mini-player'),
          onTap: () => Navigator.of(context).push(playerScreenRoute(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Hero(
                  tag: playerArtworkHeroTag(currentItem!.path),
                  transitionOnUserGestures: true,
                  child: TrackArtwork(
                    track: Track(
                      uri: currentItem.path,
                      title: currentItem.title,
                      artist: currentItem.artist,
                      duration: currentItem.duration,
                      dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
                      artworkPath: currentItem.artworkPath,
                    ),
                    size: 48,
                    usage: ArtworkUsage.miniPlayer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentItem.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        currentItem.artist ?? 'Artista desconocido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PlayCircleButton(
                    key: const Key('mini-player-play-pause'),
                    onPressed: status == AudioPlaybackStatus.error
                        ? null
                        : controller.togglePlayback,
                    isPlaying: isPlaying,
                    size: 48,
                  ),
                IconButton(
                  key: const Key('mini-player-next'),
                  tooltip: 'Siguiente',
                  onPressed: status == AudioPlaybackStatus.error
                      ? null
                      : controller.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

enum _LibraryAction { update, addFiles, loadDebugTracks }

enum _TrackAction {
  edit,
  playNext,
  addToQueue,
  addToPlaylist,
  favorite,
  delete,
}
