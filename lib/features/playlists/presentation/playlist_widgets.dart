import 'dart:async';
import 'dart:math' as math;

import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter/material.dart';
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
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final playlist = items[index];
                      return ListTile(
                        leading: const PlaylistArtwork(size: 40),
                        title: Text(playlist.name),
                        subtitle: Text(playlistTrackCount(playlist.trackCount)),
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

class _PlaylistDetailBody extends ConsumerWidget {
  const _PlaylistDetailBody({
    required this.playlist,
    required this.tracks,
    required this.embedded,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final library = ref.read(libraryControllerProvider.notifier);
    final available = tracks.where((track) => track.isAvailable).toList();
    final duration = tracks.fold<Duration>(
      Duration.zero,
      (total, track) => total + (track.duration ?? Duration.zero),
    );
    return Column(
      key: const Key('playlist-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const PlaylistArtwork(size: 104),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${playlistTrackCount(playlist.trackCount)} · ${_durationLabel(duration)}',
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PlaylistAction>(
                key: const Key('playlist-menu-button'),
                onSelected: (action) => switch (action) {
                  _PlaylistAction.rename => _rename(context, ref),
                  _PlaylistAction.delete => _delete(context, ref),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PlaylistAction.rename,
                    child: Text('Renombrar'),
                  ),
                  PopupMenuItem(
                    value: _PlaylistAction.delete,
                    child: Text('Eliminar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              PlayCircleButton(
                key: const Key('playlist-play-button'),
                onPressed: available.isEmpty
                    ? null
                    : () => library.playAll(tracks),
                isPlaying: player.isPlaying,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('playlist-shuffle-button'),
                onPressed: available.isEmpty
                    ? null
                    : () => library.playAll(tracks, shuffle: true),
                icon: const Icon(Icons.shuffle),
                label: const Text('Aleatorio'),
              ),
            ],
          ),
        ),
        Expanded(
          key: const Key('playlist-tracks-viewport'),
          child: tracks.isEmpty
              ? const Center(
                  child: Text(
                    'Esta playlist aún no tiene canciones.',
                    key: Key('empty-playlist-message'),
                  ),
                )
              : ReorderableListView.builder(
                  key: const Key('playlist-track-list'),
                  buildDefaultDragHandles:
                      MediaQuery.sizeOf(context).width < 840,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    // La cola en reproducción es una copia y no se reordena.
                    ref
                        .read(playlistRepositoryProvider)
                        .move(playlist.id, oldIndex, newIndex);
                  },
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return _ReorderableTrackRow(
                      key: ValueKey('playlist-track-${track.id}'),
                      index: index,
                      child: TrackTile(
                        track: track,
                        onTap: track.isAvailable
                            ? () => library.playVisibleQueue(
                                tracks,
                                startIndex: index,
                              )
                            : library.showUnavailableMessage,
                        trailing: PopupMenuButton<bool>(
                          tooltip: 'Acciones de ${track.title}',
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: true,
                              child: Text('Quitar de esta playlist'),
                            ),
                          ],
                          onSelected: (_) => ref
                              .read(playlistRepositoryProvider)
                              .removeTrack(playlist.id, track.id!),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repository = ref.read(playlistRepositoryProvider);
    await Future<void>.delayed(Duration.zero);
    if (!navigator.mounted) return;
    final name = await showPlaylistNameDialog(
      navigator.context,
      initialName: playlist.name,
    );
    if (name != null) {
      await repository.rename(playlist.id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final repository = ref.read(playlistRepositoryProvider);
    final appNavigation = embedded
        ? ref.read(appDestinationProvider.notifier)
        : null;
    await Future<void>.delayed(Duration.zero);
    if (!navigator.mounted) return;
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text(
          'Se eliminará la playlist ${playlist.name}. Tus canciones no se borran.',
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
    await repository.delete(playlist.id);
    if (!navigator.mounted) return;
    if (embedded) {
      appNavigation!.back();
    } else {
      navigator.pop();
    }
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

enum _PlaylistAction { rename, delete }

String _durationLabel(Duration duration) {
  if (duration == Duration.zero) return '0 min';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '$hours h $minutes min' : '${duration.inMinutes} min';
}
