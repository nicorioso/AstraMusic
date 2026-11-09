import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/application/metadata_editor_service.dart';
import 'package:astramusic/features/library/presentation/metadata_editor_dialog.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/queue_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/secondary_back_header.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({
    this.embedded = false,
    this.showMobileBackButton = false,
    super.key,
  });

  final bool embedded;
  final bool showMobileBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playerControllerProvider.select((state) => state.queue),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final canUndo = ref.watch(
      playerControllerProvider.select((state) => state.canUndoQueue),
    );
    Future<void> saveQueue() async {
      final messenger = ScaffoldMessenger.of(context);
      final repository = ref.read(playlistRepositoryProvider);
      final playlist = await createPlaylist(context, ref);
      if (playlist == null) return;
      try {
        await repository.addTracks(playlist.id, [
          for (final track in queue)
            if (track.id != null) track.id!,
        ]);
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Cola guardada en ${playlist.name}')),
          );
        }
      } catch (error) {
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('No se pudo guardar la cola: $error')),
          );
        }
      }
    }

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('save-queue-button'),
          tooltip: 'Guardar cola como playlist',
          onPressed: queue.isEmpty ? null : saveQueue,
          icon: const Icon(Icons.playlist_add),
        ),
        IconButton(
          key: const Key('undo-queue-button'),
          tooltip: 'Deshacer cambio en cola',
          onPressed: canUndo ? controller.undoQueueChange : null,
          icon: const Icon(Icons.undo),
        ),
        _ClearQueueButton(
          enabled: queue.isNotEmpty,
          onPressed: controller.clearQueue,
        ),
      ],
    );
    final body = const PlayerQueuePanel(child: PlayerQueueView());
    if (embedded) {
      return Column(
        key: const Key('queue-destination'),
        children: [
          if (showMobileBackButton)
            SecondaryBackHeader(title: 'Cola', trailing: actions)
          else
            SectionTitle('Cola', trailing: actions),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cola'), actions: [actions]),
      body: AstraBackground(child: SafeArea(child: body)),
    );
  }
}

class _ClearQueueButton extends StatelessWidget {
  const _ClearQueueButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('clear-queue-button'),
    onPressed: enabled ? onPressed : null,
    child: const Text('Vaciar cola'),
  );
}

class PlayerQueuePanel extends StatelessWidget {
  const PlayerQueuePanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    final fill = queuePanelFillColor(
      surface: colors.surface,
      text: colors.text,
      // El color dinámico ya está limitado a luminosidad HSL 0,2. Este es
      // el caso de mayor luminancia aproximada dentro de ese límite.
      background: const Color(0xFF666600),
    );
    return DecoratedBox(
      key: const Key('queue-panel'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

/// Lista de cola reutilizable por su pantalla dedicada, el panel móvil y el
/// reproductor de escritorio.
class PlayerQueueView extends ConsumerWidget {
  const PlayerQueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playerControllerProvider.select((state) => state.queue),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final recent = ref.watch(
      playerControllerProvider.select((state) => state.recentlyPlayed),
    );
    if (queue.isEmpty) {
      return const Center(
        child: Text('La cola está vacía.', key: Key('empty-queue-message')),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            key: const Key('queue-list'),
            itemExtent: 56,
            scrollCacheExtent: const ScrollCacheExtent.pixels(280),
            buildDefaultDragHandles: false,
            itemCount: queue.length,
            onReorderItem: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              controller.moveInQueue(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final track = queue[index];
              final itemKey = ValueKey(_queueIdentity(queue, index));
              return SizedBox(
                key: itemKey,
                height: 56,
                child: Dismissible(
                  key: ValueKey('dismiss-$itemKey'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline),
                  ),
                  confirmDismiss: (_) async {
                    await controller.removeFromQueue(index);
                    return false;
                  },
                  child: TrackTile(
                    track: track,
                    currentKey: const Key('current-queue-item'),
                    currentColor: context.astraColors.accent.withValues(
                      alpha: queueCurrentRowOpacity,
                    ),
                    hoverColor: Colors.white.withValues(
                      alpha: queueHoverOpacity,
                    ),
                    onTap: () => controller.skipToIndex(index),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Acciones de ${track.title}',
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              enabled: canEditTrackMetadata(track),
                              child: const Text('Editar metadatos'),
                            ),
                            const PopupMenuItem(
                              value: 'playlist',
                              child: Text('Añadir a playlist'),
                            ),
                            const PopupMenuItem(
                              value: 'next',
                              child: Text('Reproducir después de esta'),
                            ),
                          ],
                          onSelected: (action) {
                            if (action == 'edit') {
                              showMetadataEditor(context, track);
                            } else if (action == 'playlist') {
                              showAddTrackToPlaylist(context, ref, track);
                            } else {
                              final current = ref
                                  .read(playerControllerProvider)
                                  .currentIndex;
                              if (current != null && current != index) {
                                controller.moveInQueue(
                                  index,
                                  index < current ? current : current + 1,
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          key: ValueKey('remove-queue-item-$index'),
                          tooltip: 'Quitar ${track.title}',
                          onPressed: () => controller.removeFromQueue(index),
                          icon: const Icon(Icons.close),
                        ),
                        Semantics(
                          button: true,
                          label: 'Reordenar ${track.title}',
                          child: ReorderableDragStartListener(
                            index: index,
                            child: const Tooltip(
                              message: 'Mantener y arrastrar para reordenar',
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (recent.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('queue-history-button'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Reproducidas recientemente'),
                  content: SizedBox(
                    width: 400,
                    height: 320,
                    child: ListView(
                      children: [
                        for (final track in recent)
                          ListTile(title: Text(track.title)),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Historial reciente'),
            ),
          ),
      ],
    );
  }
}

String _queueIdentity(List<Track> queue, int index) {
  final uri = queue[index].uri;
  var occurrence = 0;
  for (var candidate = 0; candidate < index; candidate++) {
    if (queue[candidate].uri == uri) occurrence++;
  }
  return '$uri#$occurrence';
}
