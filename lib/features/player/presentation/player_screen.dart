import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/dynamic_artwork_color.dart';
import 'package:astramusic/core/widgets/play_circle_button.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:astramusic/features/player/presentation/seek_bar.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

Route<void> playerScreenRoute(BuildContext context) {
  final animationsDisabled = MediaQuery.disableAnimationsOf(context);
  final duration = animationsDisabled
      ? Duration.zero
      : const Duration(milliseconds: 220);
  return PageRouteBuilder<void>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, _, _) => const PlayerScreen(),
    transitionsBuilder: (_, animation, _, child) {
      if (animationsDisabled) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

String playerArtworkHeroTag(String uri) => 'player-artwork-$uri';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationWarning = ref.watch(
      playerControllerProvider.select((state) => state.notificationWarning),
    );
    final currentItem = ref.watch(
      playerControllerProvider.select((state) => state.currentItem),
    );
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final content = desktop
        ? _DesktopPlayer(notificationWarning: notificationWarning)
        : _MobilePlayer(notificationWarning: notificationWarning);
    final navigator = Navigator.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): navigator.maybePop,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: DynamicArtworkBackground(
            track: currentItem == null ? null : _trackFor(currentItem),
            child: SafeArea(
              child: desktop
                  ? content
                  : _SwipeToClose(
                      key: const Key('swipe-to-close'),
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeToClose extends StatefulWidget {
  const _SwipeToClose({required this.child, super.key});

  final Widget child;

  @override
  State<_SwipeToClose> createState() => _SwipeToCloseState();
}

class _SwipeToCloseState extends State<_SwipeToClose> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _distance = 0,
    onPointerMove: (event) {
      if (event.delta.dy > 0) _distance += event.delta.dy;
    },
    onPointerUp: (_) {
      if (_distance >= 80) Navigator.of(context).maybePop();
    },
    child: widget.child,
  );
}

class _MobilePlayer extends StatelessWidget {
  const _MobilePlayer({required this.notificationWarning});

  final bool notificationWarning;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final artworkSize = (constraints.maxWidth - 48).clamp(180.0, 420.0);
      return SingleChildScrollView(
        key: const Key('mobile-player-scroll'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('close-player-button'),
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    const Expanded(
                      child: Text('Reproduciendo', textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                if (notificationWarning) const _NotificationWarning(),
                const SizedBox(height: 12),
                _CurrentTrack(artworkSize: artworkSize),
                const SizedBox(height: 20),
                const RepaintBoundary(child: _ProgressControls()),
                const SizedBox(height: 12),
                const _PlaybackControls(),
                const _PlayerError(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('open-queue-button'),
                  onPressed: () => _showQueue(context),
                  icon: const Icon(Icons.queue_music),
                  label: const Text('A continuación'),
                ),
                const _ChooseFileButton(),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _showQueue(BuildContext context) {
    final navigatorContext = context;
    showModalBottomSheet<void>(
      context: navigatorContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: PlayerQueuePanel(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'A continuación',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: PlayerQueueView()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPlayer extends StatelessWidget {
  const _DesktopPlayer({required this.notificationWarning});

  final bool notificationWarning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 48,
            child: IconButton(
              key: const Key('close-player-button'),
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const Key('desktop-player-scroll'),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (notificationWarning)
                                const _NotificationWarning(),
                              const SizedBox(height: 12),
                              _CurrentTrack(
                                artworkSize: (constraints.maxWidth - 48).clamp(
                                  180.0,
                                  420.0,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const RepaintBoundary(child: _ProgressControls()),
                              const SizedBox(height: 12),
                              const _PlaybackControls(),
                              const _PlayerError(),
                              const _ChooseFileButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              const Expanded(
                child: PlayerQueuePanel(
                  child: Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'A continuación',
                            key: Key('desktop-queue-title'),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Expanded(child: PlayerQueueView()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChooseFileButton extends ConsumerWidget {
  const _ChooseFileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItem = ref.watch(
      playerControllerProvider.select((state) => state.currentItem != null),
    );
    if (hasItem) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: FilledButton.icon(
        key: const Key('choose-audio-button'),
        onPressed: ref.read(playerControllerProvider.notifier).chooseFile,
        icon: const Icon(Icons.audio_file),
        label: const Text('Elegir archivo'),
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
    final favoriteIds = ref
        .watch(favoriteTracksProvider)
        .value
        ?.map((track) => track.id)
        .toSet();
    final isFavorite =
        item?.trackId != null &&
        (favoriteIds?.contains(item!.trackId) ?? false);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final switchDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Column(
      children: [
        if (item != null) ...[
          Hero(
            tag: playerArtworkHeroTag(item.path),
            transitionOnUserGestures: true,
            child: AnimatedSwitcher(
              duration: switchDuration,
              child: TrackArtwork(
                key: ValueKey(item.path),
                track: _trackFor(item),
                size: artworkSize,
                usage: ArtworkUsage.player,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: switchDuration,
                child: KeyedSubtree(
                  key: ValueKey(item?.path),
                  child: Text(
                    item?.title ?? 'Ningún archivo seleccionado',
                    key: const Key('current-audio-title'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            ),
            if (item?.trackId case final trackId?)
              IconButton(
                key: const Key('favorite-current-track-button'),
                tooltip: isFavorite
                    ? 'Quitar de Me gusta'
                    : 'Añadir a Me gusta',
                onPressed: () => ref
                    .read(trackRepositoryProvider)
                    .setFavorite(trackId, !isFavorite),
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? context.astraColors.accent : null,
                ),
              ),
          ],
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

Track _trackFor(AudioItem item) => Track(
  id: item.trackId,
  uri: item.path,
  title: item.title,
  artist: item.artist,
  duration: item.duration,
  dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
  artworkPath: item.artworkPath,
);

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
