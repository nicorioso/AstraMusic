import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/dynamic_artwork_color.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [context.astraColors.ember, context.astraColors.surfaceHover],
      ),
    ),
    child: Icon(
      Icons.music_note,
      size: size * 0.5,
      color: context.astraColors.photon,
    ),
  );
}

class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({required this.playlist, required this.size, super.key});

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlist.id == favoritesPlaylistId) {
      return FavoritesArtwork(size: size);
    }
    final customArtworkPath = playlist.customArtworkPath;
    if (customArtworkPath != null && customArtworkPath.isNotEmpty) {
      return ClipRRect(
        key: ValueKey('playlist-custom-cover-${playlist.id}'),
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(customArtworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => PlaylistArtwork(size: size),
        ),
      );
    }
    final tracks = ref.watch(playlistCoverTracksProvider(playlist.id));
    return tracks.when(
      data: (items) {
        if (items.isEmpty) return PlaylistArtwork(size: size);
        if (items.length < 4) {
          return TrackArtwork(
            track: items.first,
            size: size,
            usage: ArtworkUsage.list,
          );
        }
        final tileSize = size / 2;
        return ClipRRect(
          key: ValueKey('playlist-cover-grid-${playlist.id}'),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox.square(
            dimension: size,
            child: Wrap(
              children: [
                for (final track in items.take(4))
                  TrackArtwork(
                    track: track,
                    size: tileSize,
                    usage: ArtworkUsage.list,
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => PlaylistArtwork(size: size),
      error: (_, _) => PlaylistArtwork(size: size),
    );
  }
}

class FavoritesArtwork extends StatelessWidget {
  const FavoritesArtwork({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [context.astraColors.accent, context.astraColors.ember],
      ),
    ),
    child: Icon(
      Icons.favorite,
      size: size * 0.5,
      color: context.astraColors.photon,
    ),
  );
}

const favoritesPlaylistId = -1;
const _mobilePlaylistHeaderCollapseHeight = 280.0;
const _desktopPlaylistHeaderCollapseHeight = 270.0;
const _mobilePlaylistHeaderExpandedHeight = 348.0;

String playlistTrackCount(int count) =>
    count == 1 ? 'Playlist · 1 canción' : 'Playlist · $count canciones';

Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PlaylistNameDialog(initialName: initialName),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({this.initialName});

  final String? initialName;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = _controller.text.trim();
    if (normalized.isEmpty) {
      setState(() => _error = 'Escribe un nombre.');
      return;
    }
    if (normalized.length > 60) {
      setState(() => _error = 'Máximo 60 caracteres.');
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialName == null ? 'Nueva playlist' : 'Renombrar playlist',
    ),
    content: TextField(
      key: const Key('playlist-name-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('save-playlist-button'),
        onPressed: _submit,
        child: const Text('Guardar'),
      ),
    ],
  );
}

Future<Playlist?> createPlaylist(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  final repository = ref.read(playlistRepositoryProvider);
  return _createPlaylist(navigator, repository);
}

Future<void> showAddTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final trackId = track.id;
  if (trackId == null) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(playlistRepositoryProvider);
  final isDesktop = MediaQuery.sizeOf(context).width >= 840;
  await Future<void>.delayed(Duration.zero);
  if (!navigator.mounted) return;
  final selected = isDesktop
      ? await showDialog<int>(
          context: navigator.context,
          builder: (_) => const _PlaylistChooser(dialog: true),
        )
      : await showModalBottomSheet<int>(
          context: navigator.context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => const _PlaylistChooser(dialog: false),
        );
  if (selected == null || !navigator.mounted) return;
  Playlist? playlist;
  if (selected == _newPlaylistId) {
    playlist = await _createPlaylist(navigator, repository);
  } else {
    playlist = await repository.watchById(selected).first;
  }
  if (playlist == null || !navigator.mounted) return;
  final result = await repository.addTracks(playlist.id, [trackId]);
  if (!messenger.mounted) return;
  final message = result.added > 0
      ? 'Añadida a ${playlist.name}'
      : 'Ya estaba en ${playlist.name}';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<Playlist?> _createPlaylist(
  NavigatorState navigator,
  PlaylistRepository repository,
) async {
  if (!navigator.mounted) return null;
  final name = await showPlaylistNameDialog(navigator.context);
  if (name == null || !navigator.mounted) return null;
  return repository.create(name);
}

const _newPlaylistId = -1;

class _PlaylistChooser extends ConsumerWidget {
  const _PlaylistChooser({required this.dialog});

  final bool dialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * 0.72, 480.0);
    final content = Column(
      children: [
        ListTile(
          key: const Key('new-playlist-option'),
          leading: const Icon(Icons.add),
          title: const Text('Nueva playlist'),
          onTap: () => Navigator.of(context).pop(_newPlaylistId),
        ),
        const Divider(height: 1),
        Expanded(
          child: playlists.when(
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aún no tienes playlists'),
                  )
                : ListView.builder(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(280),
                    addAutomaticKeepAlives: false,
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final playlist = items[index];
                      return ListTile(
                        leading: PlaylistCover(playlist: playlist, size: 40),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          playlistTrackCount(playlist.trackCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(playlist.id),
                      );
                    },
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('No fue posible cargar: $error')),
          ),
        ),
      ],
    );
    final bounded = ConstrainedBox(
      key: const Key('playlist-chooser'),
      constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
      child: SizedBox(width: 420, height: maxHeight, child: content),
    );
    if (!dialog) {
      return SafeArea(
        child: Align(alignment: Alignment.bottomCenter, child: bounded),
      );
    }
    return AlertDialog(
      title: const Text('Añadir a playlist'),
      content: bounded,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({
    required this.playlistId,
    this.embedded = false,
    super.key,
  });

  final int playlistId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlistId == favoritesPlaylistId) {
      final favorites = ref.watch(favoriteTracksProvider);
      return favorites.when(
        data: (items) => _PlaylistDetailBody(
          playlist: Playlist(
            id: favoritesPlaylistId,
            name: 'Canciones que te gustan',
            trackCount: items.length,
            addedAt: DateTime.fromMillisecondsSinceEpoch(0),
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          tracks: items,
          embedded: embedded,
          favorites: true,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('No fue posible cargar: $error')),
      );
    }
    final playlist = ref.watch(playlistProvider(playlistId));
    final tracks = ref.watch(playlistTracksProvider(playlistId));
    final body = playlist.when(
      data: (value) => value == null
          ? const Center(child: Text('La playlist ya no existe.'))
          : tracks.when(
              data: (items) => _PlaylistDetailBody(
                playlist: value,
                tracks: items,
                embedded: embedded,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('No fue posible cargar: $error')),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('No fue posible cargar: $error')),
    );
    return embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Playlist')),
            body: body,
          );
  }
}

class _PlaylistDetailBody extends ConsumerStatefulWidget {
  const _PlaylistDetailBody({
    required this.playlist,
    required this.tracks,
    required this.embedded,
    this.favorites = false,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final bool embedded;
  final bool favorites;

  @override
  ConsumerState<_PlaylistDetailBody> createState() =>
      _PlaylistDetailBodyState();
}

class _PlaylistDetailBodyState extends ConsumerState<_PlaylistDetailBody> {
  final Set<String> _selected = {};
  int? _anchor;

  @override
  void didUpdateWidget(covariant _PlaylistDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id ||
        oldWidget.favorites != widget.favorites) {
      _selected.clear();
      _anchor = null;
    }
  }

  void _select(int index) {
    final tracks = widget.tracks;
    final keyboard = HardwareKeyboard.instance;
    setState(() {
      if (keyboard.isShiftPressed && _anchor != null) {
        final start = _anchor! < index ? _anchor! : index;
        final end = _anchor! > index ? _anchor! : index;
        for (var i = start; i <= end; i++) {
          _selected.add(tracks[i].uri);
        }
      } else if (keyboard.isControlPressed || keyboard.isMetaPressed) {
        if (!_selected.add(tracks[index].uri)) {
          _selected.remove(tracks[index].uri);
        }
        _anchor = index;
      } else {
        _selected
          ..clear()
          ..add(tracks[index].uri);
        _anchor = index;
      }
    });
  }

  Future<void> _bulk(_PlaylistBulkAction action) async {
    final chosen = widget.tracks
        .where((track) => _selected.contains(track.uri))
        .toList();
    switch (action) {
      case _PlaylistBulkAction.queue:
        final controller = ref.read(libraryControllerProvider.notifier);
        for (final track in chosen.where((track) => track.isAvailable)) {
          await controller.addToQueue(track);
        }
      case _PlaylistBulkAction.playlist:
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
                content: Text('No se pudo guardar la selección: $error'),
              ),
            );
          }
        }
      case _PlaylistBulkAction.remove:
        if (widget.favorites) {
          final repository = ref.read(trackRepositoryProvider);
          for (final track in chosen) {
            if (track.id != null) {
              await repository.setFavorite(track.id!, false);
            }
          }
        } else {
          final repository = ref.read(playlistRepositoryProvider);
          for (final track in chosen) {
            if (track.id != null) {
              await repository.removeTrack(widget.playlist.id, track.id!);
            }
          }
        }
    }
    if (mounted) setState(_selected.clear);
  }

  Future<void> _contextMenu(int index, TapDownDetails details) async {
    if (!_selected.contains(widget.tracks[index].uri)) _select(index);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_PlaylistBulkAction>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: _PlaylistBulkAction.queue,
          child: Text('Añadir selección a la cola'),
        ),
        const PopupMenuItem(
          value: _PlaylistBulkAction.playlist,
          child: Text('Añadir selección a playlist'),
        ),
        PopupMenuItem(
          value: _PlaylistBulkAction.remove,
          child: Text(
            widget.favorites
                ? 'Quitar selección de Me gusta'
                : 'Quitar selección de esta playlist',
          ),
        ),
      ],
    );
    if (action != null && mounted) await _bulk(action);
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final tracks = widget.tracks;
    final embedded = widget.embedded;
    final favorites = widget.favorites;
    final isPlaying = ref.watch(
      playerControllerProvider.select((state) => state.isPlaying),
    );
    final library = ref.read(libraryControllerProvider.notifier);
    final available = tracks.where((track) => track.isAvailable).toList();
    final duration = tracks.fold<Duration>(
      Duration.zero,
      (total, track) => total + (track.duration ?? Duration.zero),
    );
    Widget artwork(double size) => favorites
        ? FavoritesArtwork(size: size)
        : PlaylistCover(playlist: playlist, size: size);
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          playlist.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${playlistTrackCount(playlist.trackCount)} · ${_durationLabel(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final menu = favorites
        ? null
        : PopupMenuButton<_PlaylistAction>(
            key: const Key('playlist-menu-button'),
            onSelected: (action) => switch (action) {
              _PlaylistAction.changeArtwork => _changeArtwork(context, ref),
              _PlaylistAction.rename => _rename(context, ref),
              _PlaylistAction.delete => _delete(context, ref),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _PlaylistAction.changeArtwork,
                child: Text('Cambiar carátula'),
              ),
              PopupMenuItem(
                value: _PlaylistAction.rename,
                child: Text('Renombrar'),
              ),
              PopupMenuItem(
                value: _PlaylistAction.delete,
                child: Text('Eliminar'),
              ),
            ],
          );
    return SizedBox.expand(
      key: const Key('playlist-detail'),
      child: CustomScrollView(
        key: const Key('playlist-tracks-viewport'),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: MediaQuery.sizeOf(context).width < 840
                ? _mobilePlaylistHeaderExpandedHeight
                : 300,
            leading: IconButton(
              key: const Key('playlist-detail-back-button'),
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (embedded) {
                  ref.read(appDestinationProvider.notifier).back();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
            actions: [?menu],
            flexibleSpace: FlexibleSpaceBar(
              background: DynamicArtworkColorBuilder(
                track: tracks.isEmpty ? null : tracks.first,
                imagePath: playlist.customArtworkPath,
                builder: (context, dynamicColor) => DecoratedBox(
                  key: const Key('playlist-detail-header'),
                  decoration: BoxDecoration(
                    gradient: dynamicColor == null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              context.astraColors.gradientTop,
                              context.astraColors.surface.withValues(alpha: 0),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              dynamicColor,
                              context.astraColors.surface.withValues(alpha: 0),
                            ],
                          ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, headerConstraints) {
                      // El shell determina la variante móvil. El panel central
                      // puede ser más angosto que 840 dp en escritorio por la
                      // barra lateral, pero debe conservar su composición
                      // horizontal y ajustar la portada al espacio disponible.
                      final mobile = MediaQuery.sizeOf(context).width < 840;
                      final collapseHeight = mobile
                          ? _mobilePlaylistHeaderCollapseHeight
                          : _desktopPlaylistHeaderCollapseHeight;
                      if (headerConstraints.maxHeight < collapseHeight) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(72, 64, 16, 12),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          mobile ? 56 : 36,
                          16,
                          12,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final coverSize = mobile
                                ? (constraints.maxHeight - 104).clamp(
                                    112.0,
                                    140.0,
                                  )
                                : math.min(
                                    (constraints.maxHeight - 48).clamp(
                                      72.0,
                                      250.0,
                                    ),
                                    (constraints.maxWidth - 144).clamp(
                                      72.0,
                                      250.0,
                                    ),
                                  );
                            if (mobile) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.center,
                                    child: KeyedSubtree(
                                      key: const Key('playlist-header-cover'),
                                      child: artwork(coverSize),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  details,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                KeyedSubtree(
                                  key: const Key('playlist-header-cover'),
                                  child: artwork(coverSize),
                                ),
                                const SizedBox(width: 24),
                                Expanded(child: details),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  PlayCircleButton(
                    key: const Key('playlist-play-button'),
                    onPressed: available.isEmpty
                        ? null
                        : () => favorites
                              ? library.playAll(tracks)
                              : library.playPlaylist(playlist.id, tracks),
                    isPlaying: isPlaying,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const Key('playlist-shuffle-button'),
                    onPressed: available.isEmpty
                        ? null
                        : () => favorites
                              ? library.playAll(tracks, shuffle: true)
                              : library.playPlaylist(
                                  playlist.id,
                                  tracks,
                                  shuffle: true,
                                ),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Aleatorio'),
                  ),
                ],
              ),
            ),
          ),
          if (_selected.any((uri) => tracks.any((track) => track.uri == uri)))
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Text(
                      '${_selected.where((uri) => tracks.any((track) => track.uri == uri)).length} seleccionadas',
                    ),
                    TextButton(
                      onPressed: () => _bulk(_PlaylistBulkAction.queue),
                      child: const Text('A la cola'),
                    ),
                    TextButton(
                      onPressed: () => _bulk(_PlaylistBulkAction.playlist),
                      child: const Text('Playlist'),
                    ),
                    TextButton(
                      onPressed: () => _bulk(_PlaylistBulkAction.remove),
                      child: const Text('Quitar'),
                    ),
                    IconButton(
                      onPressed: () => setState(_selected.clear),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          if (MediaQuery.sizeOf(context).width >= 840 && tracks.isNotEmpty)
            const SliverToBoxAdapter(child: _PlaylistTrackHeader()),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Esta playlist aún no tiene canciones.',
                  key: Key('empty-playlist-message'),
                ),
              ),
            )
          else
            SliverReorderableList(
              key: const Key('playlist-track-list'),
              itemExtent: 56,
              onReorderItem: (oldIndex, newIndex) {
                if (favorites) return;
                // La cola en reproducción es una copia y no se reordena.
                if (newIndex > oldIndex) newIndex--;
                ref
                    .read(playlistRepositoryProvider)
                    .move(playlist.id, oldIndex, newIndex);
              },
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                void playTrack() => favorites
                    ? library.playVisibleQueue(tracks, startIndex: index)
                    : library.playPlaylist(
                        playlist.id,
                        tracks,
                        startIndex: index,
                      );
                void removeTrack() => favorites
                    ? ref
                          .read(trackRepositoryProvider)
                          .setFavorite(track.id!, false)
                    : ref
                          .read(playlistRepositoryProvider)
                          .removeTrack(playlist.id, track.id!);
                if (MediaQuery.sizeOf(context).width >= 840) {
                  final row = _PlaylistDesktopTrackRow(
                    track: track,
                    index: index,
                    onTap: track.isAvailable
                        ? () {
                            if (_selected.isNotEmpty ||
                                HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed ||
                                HardwareKeyboard.instance.isShiftPressed) {
                              _select(index);
                            } else {
                              playTrack();
                            }
                          }
                        : library.showUnavailableMessage,
                    selected: _selected.contains(track.uri),
                    onSelect: () => _select(index),
                    onContextMenu: (details) => _contextMenu(index, details),
                    removeLabel: favorites
                        ? 'Quitar de Me gusta'
                        : 'Quitar de esta playlist',
                    onRemove: removeTrack,
                  );
                  return favorites
                      ? KeyedSubtree(
                          key: ValueKey('favorite-track-${track.id}'),
                          child: row,
                        )
                      : _ReorderableTrackRow(
                          key: ValueKey('playlist-track-${track.id}'),
                          index: index,
                          child: row,
                        );
                }
                final tile = TrackTile(
                  track: track,
                  showDateAdded: true,
                  onTap: track.isAvailable
                      ? () {
                          if (_selected.isNotEmpty ||
                              HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed ||
                              HardwareKeyboard.instance.isShiftPressed) {
                            _select(index);
                          } else {
                            playTrack();
                          }
                        }
                      : library.showUnavailableMessage,
                  onSecondaryTapDown: (details) => _contextMenu(index, details),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selected.contains(track.uri))
                        Checkbox(value: true, onChanged: (_) => _select(index)),
                      if (track.duration case final duration?)
                        Text(_trackDuration(duration)),
                      PopupMenuButton<bool>(
                        tooltip: 'Acciones de ${track.title}',
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: true,
                            child: Text(
                              favorites
                                  ? 'Quitar de Me gusta'
                                  : 'Quitar de esta playlist',
                            ),
                          ),
                        ],
                        onSelected: (_) => removeTrack(),
                      ),
                    ],
                  ),
                );
                if (favorites) {
                  return KeyedSubtree(
                    key: ValueKey('favorite-track-${track.id}'),
                    child: tile,
                  );
                }
                return _ReorderableTrackRow(
                  key: ValueKey('playlist-track-${track.id}'),
                  index: index,
                  child: tile,
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _changeArtwork(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ref.read(playlistArtworkPickerProvider);
    final repository = ref.read(playlistRepositoryProvider);
    try {
      final path = await picker.pickImage();
      if (path == null) return;
      await repository.setCustomArtwork(widget.playlist.id, path);
    } catch (_) {
      if (!messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No fue posible cambiar la carátula.')),
        );
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repository = ref.read(playlistRepositoryProvider);
    await Future<void>.delayed(Duration.zero);
    if (!navigator.mounted) return;
    final name = await showPlaylistNameDialog(
      navigator.context,
      initialName: widget.playlist.name,
    );
    if (name != null) {
      await repository.rename(widget.playlist.id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repository = ref.read(playlistRepositoryProvider);
    final appNavigation = widget.embedded
        ? ref.read(appDestinationProvider.notifier)
        : null;
    await Future<void>.delayed(Duration.zero);
    if (!navigator.mounted) return;
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text(
          'Se eliminará la playlist ${widget.playlist.name}. Tus canciones no se borran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-delete-playlist-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !navigator.mounted) return;
    await repository.delete(widget.playlist.id);
    if (!navigator.mounted) return;
    if (widget.embedded) {
      appNavigation!.back();
    } else {
      navigator.pop();
    }
  }
}

enum _PlaylistBulkAction { queue, playlist, remove }

class _PlaylistTrackHeader extends StatelessWidget {
  const _PlaylistTrackHeader();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(width: 56, child: Center(child: Text('#'))),
            Expanded(flex: 5, child: Text('Título')),
            Expanded(flex: 3, child: Text('Álbum')),
            SizedBox(width: 128, child: Text('Fecha de adición')),
            SizedBox(width: 80, child: Text('Duración')),
            SizedBox(width: 96),
          ],
        ),
      ),
      Divider(height: 1),
    ],
  );
}

class _PlaylistDesktopTrackRow extends ConsumerWidget {
  const _PlaylistDesktopTrackRow({
    required this.track,
    required this.index,
    required this.onTap,
    required this.selected,
    required this.onSelect,
    required this.onContextMenu,
    required this.removeLabel,
    required this.onRemove,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback onSelect;
  final GestureTapDownCallback onContextMenu;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(
      playerControllerProvider.select((state) => state.currentItem?.trackId),
    );
    final current = track.id != null && track.id == currentId;
    final currentColor = current ? context.astraColors.accent : null;
    return Material(
      color: current
          ? context.astraColors.surfaceHover
          : context.astraColors.surface.withValues(alpha: 0),
      child: InkWell(
        hoverColor: context.astraColors.surfaceHover,
        onTap: onTap,
        onSecondaryTapDown: onContextMenu,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Center(
                child: selected
                    ? Checkbox(value: true, onChanged: (_) => onSelect())
                    : current
                    ? Icon(Icons.graphic_eq, color: currentColor, size: 20)
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
                          style: TextStyle(color: currentColor),
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
            Expanded(
              flex: 3,
              child: Text(
                track.album ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 128, child: Text(formatTrackDate(track.dateAdded))),
            SizedBox(
              width: 80,
              child: Text(
                track.duration == null ? '—' : _trackDuration(track.duration!),
              ),
            ),
            SizedBox(
              width: 48,
              child: PopupMenuButton<bool>(
                tooltip: 'Acciones de ${track.title}',
                itemBuilder: (_) => [
                  PopupMenuItem(value: true, child: Text(removeLabel)),
                ],
                onSelected: (_) => onRemove(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderableTrackRow extends StatefulWidget {
  const _ReorderableTrackRow({
    required this.index,
    required this.child,
    super.key,
  });

  final int index;
  final Widget child;

  @override
  State<_ReorderableTrackRow> createState() => _ReorderableTrackRowState();
}

class _ReorderableTrackRowState extends State<_ReorderableTrackRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 840) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        children: [
          Expanded(child: widget.child),
          AnimatedOpacity(
            opacity: _hovered ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: ReorderableDragStartListener(
              index: widget.index,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlaylistAction { changeArtwork, rename, delete }

String _durationLabel(Duration duration) {
  if (duration == Duration.zero) return '0 min';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '$hours h $minutes min' : '${duration.inMinutes} min';
}

String _trackDuration(Duration duration) {
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}:$seconds';
}
