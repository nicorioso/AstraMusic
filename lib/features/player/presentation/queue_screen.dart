import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/section_title.dart';
import 'package:astramusic/core/widgets/track_tile.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playerControllerProvider.select((state) => state.queue),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final body = const PlayerQueueView();
    if (embedded) {
      return Column(
        key: const Key('queue-destination'),
        children: [
          SectionTitle(
            'Cola',
            trailing: TextButton(
              key: const Key('clear-queue-button'),
              onPressed: queue.isEmpty ? null : controller.clearQueue,
              child: const Text('Vaciar cola'),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
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
      body: AstraBackground(child: SafeArea(child: body)),
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
    if (queue.isEmpty) {
      return const Center(
        child: Text('La cola está vacía.', key: Key('empty-queue-message')),
      );
    }
    return ReorderableListView.builder(
      key: const Key('queue-list'),
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: controller.moveInQueue,
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
                    onSelected: (_) =>
                        showAddTrackToPlaylist(context, ref, track),
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
