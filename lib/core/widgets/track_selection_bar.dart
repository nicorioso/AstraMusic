import 'package:flutter/material.dart';

class TrackSelectionBar extends StatelessWidget {
  const TrackSelectionBar({
    required this.count,
    required this.onPlay,
    required this.onQueue,
    required this.onPlaylist,
    required this.onRemove,
    required this.removeLabel,
    required this.onClose,
    super.key,
  });

  final int count;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback onPlaylist;
  final VoidCallback onRemove;
  final String removeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Salir del modo selector',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
        Expanded(child: Text('$count seleccionadas', maxLines: 1)),
        IconButton(
          tooltip: 'Reproducir selección',
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Añadir selección a la cola',
          onPressed: onQueue,
          icon: const Icon(Icons.queue_music),
        ),
        IconButton(
          tooltip: 'Añadir selección a playlist',
          onPressed: onPlaylist,
          icon: const Icon(Icons.playlist_add),
        ),
        IconButton(
          tooltip: removeLabel,
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}
