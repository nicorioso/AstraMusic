import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playerControllerProvider.select((state) => state.queue),
    );
    final currentIndex = ref.watch(
      playerControllerProvider.select((state) => state.currentIndex),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cola'),
        actions: [
          TextButton(
            key: const Key('clear-queue-button'),
            onPressed: queue.isEmpty ? null : controller.clearQueue,
            child: const Text('Vaciar cola'),
          ),
        ],
      ),
      body: AstraBackground(
        child: SafeArea(
          child: queue.isEmpty
              ? const Center(
                  child: Text(
                    'La cola está vacía.',
                    key: Key('empty-queue-message'),
                  ),
                )
              : ReorderableListView.builder(
                  key: const Key('queue-list'),
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorderItem: controller.moveInQueue,
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final itemKey = ValueKey(_queueIdentity(queue, index));
                    final isCurrent = index == currentIndex;
                    return SizedBox(
                      key: itemKey,
                      height: 56,
                      child: Dismissible(
                        key: ValueKey('dismiss-$itemKey'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: context.astraColors.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline),
                        ),
                        confirmDismiss: (_) async {
                          await controller.removeFromQueue(index);
                          return false;
                        },
                        child: Material(
                          key: isCurrent
                              ? const Key('current-queue-item')
                              : null,
                          color: isCurrent
                              ? context.astraColors.surfaceHover
                              : context.astraColors.voidColor.withValues(
                                  alpha: 0,
                                ),
                          child: ListTile(
                            minVerticalPadding: 0,
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
                            onTap: () => controller.skipToIndex(index),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<bool>(
                                  tooltip: 'Acciones de ${track.title}',
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: true,
                                      child: Text('Añadir a playlist'),
                                    ),
                                  ],
                                  onSelected: (_) => showAddTrackToPlaylist(
                                    context,
                                    ref,
                                    track,
                                  ),
                                ),
                                Semantics(
                                  button: true,
                                  label: 'Reordenar ${track.title}',
                                  child: ReorderableDragStartListener(
                                    index: index,
                                    child: const Tooltip(
                                      message:
                                          'Mantener y arrastrar para reordenar',
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
                      ),
                    );
                  },
                ),
        ),
      ),
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
