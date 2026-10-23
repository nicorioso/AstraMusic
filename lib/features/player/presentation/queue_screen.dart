import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
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
      body: SafeArea(
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
                  return Dismissible(
                    key: itemKey,
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline),
                    ),
                    confirmDismiss: (_) async {
                      await controller.removeFromQueue(index);
                      return false;
                    },
                    child: Material(
                      key: isCurrent ? const Key('current-queue-item') : null,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: 0.6)
                          : Colors.transparent,
                      child: ListTile(
                        leading: Icon(
                          isCurrent ? Icons.graphic_eq : Icons.music_note,
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artist ?? 'Artista desconocido',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => controller.skipToIndex(index),
                        trailing: Semantics(
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
                      ),
                    ),
                  );
                },
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
