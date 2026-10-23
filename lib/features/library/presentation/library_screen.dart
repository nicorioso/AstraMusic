import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
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
    final playerState = ref.watch(playerControllerProvider);
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
                builder: (_) => const _MusicFoldersDialog(),
              ),
              icon: const Icon(Icons.folder_copy_outlined),
            ),
          PopupMenuButton<_LibraryAction>(
            tooltip: 'Más acciones',
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('library-search-field'),
                onChanged: ref.read(librarySearchQueryProvider.notifier).update,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Buscar por título, artista o álbum',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (libraryState.isScanning)
              _ScanProgressCard(
                foundCount: libraryState.foundCount,
                errorCount: libraryState.scanErrorCount,
                onCancel: libraryController.cancelScan,
              ),
            Expanded(
              child: tracks.when(
                data: (items) => items.isEmpty
                    ? const _EmptyLibrary()
                    : _TrackList(
                        tracks: items,
                        enabled: !libraryState.actionsDisabled,
                        onTrackTap: libraryController.playTrack,
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
      bottomNavigationBar: playerState.currentItem == null
          ? null
          : _MiniPlayer(state: playerState),
    );
  }
}

class _ScanProgressCard extends StatelessWidget {
  const _ScanProgressCard({
    required this.foundCount,
    required this.errorCount,
    required this.onCancel,
  });

  final int foundCount;
  final int errorCount;
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
                'Escaneando: $foundCount encontradas, $errorCount errores',
                key: const Key('scan-progress-text'),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}

class _MusicFoldersDialog extends ConsumerWidget {
  const _MusicFoldersDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersProvider);
    return AlertDialog(
      title: const Text('Carpetas de música'),
      content: SizedBox(
        width: 560,
        child: folders.when(
          data: (items) => items.isEmpty
              ? const Text('No hay carpetas guardadas.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _FolderTile(folder: items[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              Text('No fue posible cargar las carpetas: $error'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
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
      title: Text(folder.path),
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
    required this.enabled,
    required this.onTrackTap,
  });

  final List<Track> tracks;
  final bool enabled;
  final ValueChanged<Track> onTrackTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('library-track-list'),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          enabled: enabled,
          leading: Icon(track.isAvailable ? Icons.music_note : Icons.music_off),
          title: Text(track.title),
          subtitle: Text(track.artist ?? 'Artista desconocido'),
          trailing: track.duration == null
              ? null
              : Text(_formatDuration(track.duration!)),
          onTap: enabled ? () => onTrackTap(track) : null,
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
  const _MiniPlayer({required this.state});

  final PlayerViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          key: const Key('mini-player'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.music_note),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.currentItem!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    key: const Key('mini-player-play-pause'),
                    tooltip: state.isPlaying ? 'Pausar' : 'Reproducir',
                    onPressed: state.status == AudioPlaybackStatus.error
                        ? null
                        : controller.togglePlayback,
                    icon: Icon(
                      state.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
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
