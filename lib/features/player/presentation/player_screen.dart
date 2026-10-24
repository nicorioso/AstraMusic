import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:astramusic/features/player/presentation/seek_bar.dart';
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
      body: AstraBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (notificationWarning) const _NotificationWarning(),
                          const Spacer(),
                          _CurrentTrack(
                            artworkSize: constraints.maxHeight < 760
                                ? 220
                                : 280,
                          ),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentTrack extends ConsumerWidget {
  const _CurrentTrack({required this.artworkSize});

  final double artworkSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      playerControllerProvider.select((state) => state.currentItem),
    );
    return Column(
      children: [
        if (item != null) ...[
          TrackArtwork(
            track: Track(
              uri: item.path,
              title: item.title,
              artist: item.artist,
              duration: item.duration,
              dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
              artworkPath: item.artworkPath,
            ),
            size: artworkSize,
            usage: ArtworkUsage.player,
          ),
          const SizedBox(height: 24),
        ],
        Text(
          item?.title ?? 'Ningún archivo seleccionado',
          key: const Key('current-audio-title'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (item?.artist case final artist?) ...[
          const SizedBox(height: 6),
          Text(
            artist,
            key: const Key('current-audio-artist'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: context.astraColors.textMuted),
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
            _ActiveControl(
              active: shuffleEnabled,
              child: IconButton(
                key: const Key('shuffle-button'),
                tooltip: shuffleEnabled
                    ? 'Desactivar aleatorio'
                    : 'Activar aleatorio',
                color: shuffleEnabled ? context.astraColors.accent : null,
                onPressed: enabled ? controller.toggleShuffle : null,
                icon: Icon(shuffleEnabled ? Icons.shuffle_on : Icons.shuffle),
              ),
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
              PlayCircleButton(
                key: const Key('play-pause-button'),
                onPressed: enabled ? controller.togglePlayback : null,
                isPlaying: isPlaying,
                size: 64,
              ),
            IconButton(
              key: const Key('next-button'),
              tooltip: 'Siguiente',
              iconSize: 36,
              onPressed: enabled ? controller.next : null,
              icon: const Icon(Icons.skip_next),
            ),
            _ActiveControl(
              active: repeatMode != RepeatMode.off,
              child: IconButton(
                key: const Key('repeat-button'),
                tooltip: _repeatTooltip(repeatMode),
                color: repeatMode == RepeatMode.off
                    ? null
                    : context.astraColors.accent,
                onPressed: enabled ? controller.cycleRepeatMode : null,
                icon: Icon(
                  repeatMode == RepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                ),
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

class _ActiveControl extends StatelessWidget {
  const _ActiveControl({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? context.astraColors.accent
                : context.astraColors.voidColor.withValues(alpha: 0),
            shape: BoxShape.circle,
          ),
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
    return SeekBar(
      position: position,
      duration: nullableDuration,
      onSeek: hasItem ? ref.read(playerControllerProvider.notifier).seek : null,
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              error,
              key: const Key('player-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          IconButton(
            key: const Key('dismiss-player-error'),
            tooltip: 'Descartar error',
            onPressed: ref.read(playerControllerProvider.notifier).clearError,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _NotificationWarning extends StatelessWidget {
  const _NotificationWarning();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.astraColors.surfaceRaised,
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
