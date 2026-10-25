import 'dart:async';

import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
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
}) async {
  final controller = TextEditingController(text: initialName);
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          initialName == null ? 'Nueva playlist' : 'Renombrar playlist',
        ),
        content: TextField(
          key: const Key('playlist-name-field'),
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(labelText: 'Nombre', errorText: error),
          onSubmitted: (_) => _submitPlaylistName(
            dialogContext,
            controller.text,
            (value) => setState(() => error = value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('save-playlist-button'),
            onPressed: () => _submitPlaylistName(
              dialogContext,
              controller.text,
              (value) => setState(() => error = value),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

void _submitPlaylistName(
  BuildContext context,
  String value,
  ValueChanged<String?> setError,
) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    setError('Escribe un nombre.');
    return;
  }
  if (normalized.length > 60) {
    setError('Máximo 60 caracteres.');
    return;
  }
  Navigator.of(context).pop(normalized);
}

Future<Playlist?> createPlaylist(BuildContext context, WidgetRef ref) async {
  final name = await showPlaylistNameDialog(context);
  if (name == null || !context.mounted) return null;
  return ref.read(playlistRepositoryProvider).create(name);
}

Future<void> showAddTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final trackId = track.id;
  if (trackId == null) return;
  final isDesktop = MediaQuery.sizeOf(context).width >= 840;
  final selected = isDesktop
      ? await showDialog<int>(
          context: context,
          builder: (_) => const _PlaylistChooser(dialog: true),
        )
      : await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          builder: (_) => const _PlaylistChooser(dialog: false),
        );
  if (selected == null || !context.mounted) return;
  Playlist? playlist;
  if (selected == _newPlaylistId) {
    playlist = await createPlaylist(context, ref);
  } else {
    playlist = await ref
        .read(playlistRepositoryProvider)
        .watchById(selected)
        .first;
  }
  if (playlist == null || !context.mounted) return;
  final result = await ref.read(playlistRepositoryProvider).addTracks(
    playlist.id,
    [trackId],
  );
  if (!context.mounted) return;
  final message = result.added > 0
      ? 'Añadida a ${playlist.name}'
      : 'Ya estaba en ${playlist.name}';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

const _newPlaylistId = -1;

class _PlaylistChooser extends ConsumerWidget {
  const _PlaylistChooser({required this.dialog});

  final bool dialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final content = Column(
      mainAxisSize: dialog ? MainAxisSize.min : MainAxisSize.max,
      children: [
        ListTile(
          key: const Key('new-playlist-option'),
          leading: const Icon(Icons.add),
          title: const Text('Nueva playlist'),
          onTap: () => Navigator.of(context).pop(_newPlaylistId),
        ),
        const Divider(height: 1),
        Flexible(
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
    if (!dialog) return SafeArea(child: content);
    return AlertDialog(
      title: const Text('Añadir a playlist'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: content,
      ),
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
              : ListView.builder(
                  key: const Key('playlist-track-list'),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return Opacity(
                      opacity: track.isAvailable ? 1 : 0.48,
                      child: SizedBox(
                        height: 56,
                        child: ListTile(
                          leading: TrackArtwork(track: track, size: 48),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.isAvailable
                                ? track.artist ?? 'Artista desconocido'
                                : 'No disponible',
                          ),
                          onTap: track.isAvailable
                              ? () => library.playVisibleQueue(
                                  tracks,
                                  startIndex: index,
                                )
                              : library.showUnavailableMessage,
                          trailing: PopupMenuButton<void>(
                            tooltip: 'Acciones de ${track.title}',
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                child: Text('Quitar de esta playlist'),
                              ),
                            ],
                            onSelected: (_) => ref
                                .read(playlistRepositoryProvider)
                                .removeTrack(playlist.id, track.id!),
                          ),
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
    final name = await showPlaylistNameDialog(
      context,
      initialName: playlist.name,
    );
    if (name != null) {
      await ref.read(playlistRepositoryProvider).rename(playlist.id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed != true || !context.mounted) return;
    await ref.read(playlistRepositoryProvider).delete(playlist.id);
    if (!context.mounted) return;
    if (embedded) {
      ref.read(appDestinationProvider.notifier).back();
    } else {
      Navigator.of(context).pop();
    }
  }
}

enum _PlaylistAction { rename, delete }

String _durationLabel(Duration duration) {
  if (duration == Duration.zero) return '0 min';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '$hours h $minutes min' : '${duration.inMinutes} min';
}
