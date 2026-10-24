import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_controller.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryTracksProvider);
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
                case _LibraryAction.clearLibrary:
                  unawaited(libraryController.deleteAll());
              }
            },
            itemBuilder: (context) => [
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
                PopupMenuItem(
                  value: _LibraryAction.clearLibrary,
                  child: Text('Vaciar biblioteca'),
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
                  data: (items) => items.isEmpty
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
                                              items,
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
                                              items,
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
                                tracks: items,
                                currentPath: currentPath,
                                enabled: !libraryState.actionsDisabled,
                                onTrackTap: (index) => libraryController
                                    .playVisibleQueue(items, startIndex: index),
                                onPlayNext: libraryController.playNext,
                                onAddToQueue: libraryController.addToQueue,
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('scan-library-button'),
        onPressed: libraryState.actionsDisabled
            ? null
            : libraryController.startScan,
        icon: libraryState.isBusy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(isAndroid ? Icons.audio_file : Icons.create_new_folder),
        label: Text(
          isAndroid ? 'Escanear música del dispositivo' : 'Añadir carpeta',
        ),
      ),
      bottomNavigationBar: currentPath != null ? const _MiniPlayer() : null,
    );
  }
}

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
            await ref
                .read(libraryControllerProvider.notifier)
                .removeFolder(folder);
          }
        },
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.currentPath,
    required this.enabled,
    required this.onTrackTap,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onDelete,
  });

  final List<Track> tracks;
  final String? currentPath;
  final bool enabled;
  final ValueChanged<int> onTrackTap;
  final ValueChanged<Track> onPlayNext;
  final ValueChanged<Track> onAddToQueue;
  final ValueChanged<Track> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('library-track-list'),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = track.uri == currentPath;
        return SizedBox(
          height: 56,
          child: Material(
            color: isCurrent
                ? context.astraColors.surfaceHover
                : context.astraColors.voidColor.withValues(alpha: 0),
            child: ListTile(
              minVerticalPadding: 0,
              enabled: enabled,
              leading: TrackArtwork(track: track, size: 48),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isCurrent
                    ? TextStyle(color: context.astraColors.accent)
                    : null,
              ),
              subtitle: Text(
                track.artist ?? 'Artista desconocido',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (track.duration case final duration?)
                    Text(_formatDuration(duration)),
                  PopupMenuButton<_TrackAction>(
                    tooltip: 'Acciones de ${track.title}',
                    enabled: enabled && track.isAvailable,
                    onSelected: (action) {
                      switch (action) {
                        case _TrackAction.playNext:
                          onPlayNext(track);
                        case _TrackAction.addToQueue:
                          onAddToQueue(track);
                        case _TrackAction.delete:
                          onDelete(track);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _TrackAction.playNext,
                        child: Text('Reproducir a continuación'),
                      ),
                      PopupMenuItem(
                        value: _TrackAction.addToQueue,
                        child: Text('Añadir a la cola'),
                      ),
                      PopupMenuItem(
                        value: _TrackAction.delete,
                        child: Text('Eliminar de la biblioteca'),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: enabled && track.isAvailable
                  ? () => onTrackTap(index)
                  : null,
            ),
          ),
        );
      },
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
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                TrackArtwork(
                  track: Track(
                    uri: currentItem!.path,
                    title: currentItem.title,
                    artist: currentItem.artist,
                    duration: currentItem.duration,
                    dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
                    artworkPath: currentItem.artworkPath,
                  ),
                  size: 48,
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

enum _LibraryAction { update, addFiles, loadDebugTracks, clearLibrary }

enum _TrackAction { playNext, addToQueue, delete }
