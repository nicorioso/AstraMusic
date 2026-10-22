import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final duration = state.duration ?? Duration.zero;
    final maxMilliseconds = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final positionMilliseconds = state.position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('AstraMusic')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.notificationWarning) const _NotificationWarning(),
                  const Spacer(),
                  Text(
                    state.currentItem?.title ?? 'Ningún archivo seleccionado',
                    key: const Key('current-audio-title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  if (state.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    IconButton.filled(
                      key: const Key('play-pause-button'),
                      onPressed:
                          state.currentItem == null ||
                              state.status == AudioPlaybackStatus.error
                          ? null
                          : controller.togglePlayback,
                      tooltip: state.isPlaying ? 'Pausar' : 'Reproducir',
                      iconSize: 48,
                      icon: Icon(
                        state.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Slider(
                    value: positionMilliseconds,
                    max: maxMilliseconds,
                    onChanged:
                        state.currentItem == null || duration == Duration.zero
                        ? null
                        : (value) => controller.seek(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(state.position)),
                      Text(_formatDuration(duration)),
                    ],
                  ),
                  if (state.errorMessage case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      key: const Key('player-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('choose-audio-button'),
                    onPressed: controller.chooseFile,
                    icon: const Icon(Icons.audio_file),
                    label: const Text('Elegir archivo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
}

class _NotificationWarning extends StatelessWidget {
  const _NotificationWarning();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'La reproducción continuará, pero la notificación podría no '
                'mostrarse.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
