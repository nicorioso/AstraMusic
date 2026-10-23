import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationWarning = ref.watch(
      playerControllerProvider.select((state) => state.notificationWarning),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AstraMusic'),
        actions: [
          IconButton(
            key: const Key('open-queue-button'),
            tooltip: 'Ver cola',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
            ),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
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
                  if (notificationWarning) const _NotificationWarning(),
                  const Spacer(),
                  const _CurrentTrack(),
                  const SizedBox(height: 24),
                  const _PlaybackControls(),
                  const SizedBox(height: 24),
                  const _ProgressControls(),
                  const _PlayerError(),
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
}

class _CurrentTrack extends ConsumerWidget {
  const _CurrentTrack();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      playerControllerProvider.select((state) => state.currentItem),
    );
    return Column(
      children: [
        Text(
          item?.title ?? 'Ningún archivo seleccionado',
          key: const Key('current-audio-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (item?.artist case final artist?) ...[
          const SizedBox(height: 6),
          Text(
            artist,
            key: const Key('current-audio-artist'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(
      playerControllerProvider.select(
        (state) => (
          state.status,
          state.currentItem != null,
          state.shuffleEnabled,
          state.repeatMode,
        ),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final (status, hasItem, shuffleEnabled, repeatMode) = playback;
    final isPlaying = status == AudioPlaybackStatus.playing;
    final isLoading = status == AudioPlaybackStatus.loading;
    final enabled = hasItem && status != AudioPlaybackStatus.error;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('shuffle-button'),
              tooltip: shuffleEnabled
                  ? 'Desactivar aleatorio'
                  : 'Activar aleatorio',
              color: shuffleEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: enabled ? controller.toggleShuffle : null,
              icon: Icon(shuffleEnabled ? Icons.shuffle_on : Icons.shuffle),
            ),
            IconButton(
              key: const Key('previous-button'),
              tooltip: 'Anterior',
              iconSize: 36,
              onPressed: enabled ? controller.previous : null,
              icon: const Icon(Icons.skip_previous),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 48,
                  child: CircularProgressIndicator(),
                ),
              )
            else
              IconButton.filled(
                key: const Key('play-pause-button'),
                onPressed: enabled ? controller.togglePlayback : null,
                tooltip: isPlaying ? 'Pausar' : 'Reproducir',
                iconSize: 48,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
            IconButton(
              key: const Key('next-button'),
              tooltip: 'Siguiente',
              iconSize: 36,
              onPressed: enabled ? controller.next : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              key: const Key('repeat-button'),
              tooltip: _repeatTooltip(repeatMode),
              color: repeatMode == RepeatMode.off
                  ? null
                  : Theme.of(context).colorScheme.primary,
              onPressed: enabled ? controller.cycleRepeatMode : null,
              icon: Icon(
                repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
              ),
            ),
          ],
        ),
        Text(
          _repeatLabel(repeatMode),
          key: const Key('repeat-mode-label'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _ProgressControls extends ConsumerWidget {
  const _ProgressControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      playerControllerProvider.select(
        (state) => (state.position, state.duration, state.currentItem != null),
      ),
    );
    final (position, nullableDuration, hasItem) = progress;
    final duration = nullableDuration ?? Duration.zero;
    final maxMilliseconds = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final positionMilliseconds = position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();

    return Column(
      children: [
        Slider(
          value: positionMilliseconds,
          max: maxMilliseconds,
          onChanged: !hasItem || duration == Duration.zero
              ? null
              : (value) => ref
                    .read(playerControllerProvider.notifier)
                    .seek(Duration(milliseconds: value.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(position)),
            Text(_formatDuration(duration)),
          ],
        ),
      ],
    );
  }
}

class _PlayerError extends ConsumerWidget {
  const _PlayerError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(
      playerControllerProvider.select((state) => state.errorMessage),
    );
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        error,
        key: const Key('player-error'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
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

String _repeatLabel(RepeatMode mode) => switch (mode) {
  RepeatMode.off => 'Repetir: desactivado',
  RepeatMode.all => 'Repetir: toda la cola',
  RepeatMode.one => 'Repetir: una canción',
};

String _repeatTooltip(RepeatMode mode) => switch (mode) {
  RepeatMode.off => 'Activar repetición de la cola',
  RepeatMode.all => 'Repetir una canción',
  RepeatMode.one => 'Desactivar repetición',
};

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
