import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/core/widgets/playing_indicator.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrackTile extends ConsumerStatefulWidget {
  const TrackTile({
    required this.track,
    this.onTap,
    this.trailing,
    this.enabled = true,
    this.currentKey,
    this.currentColor,
    this.hoverColor,
    super.key,
  });

  final Track track;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool enabled;
  final Key? currentKey;
  final Color? currentColor;
  final Color? hoverColor;

  @override
  ConsumerState<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends ConsumerState<TrackTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(
      playerControllerProvider.select(
        (state) => (state.currentItem?.trackId, state.isPlaying),
      ),
    );
    final isCurrent = widget.track.id != null && widget.track.id == playback.$1;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final baseColor = isCurrent
        ? widget.currentColor ?? context.astraColors.surfaceHover
        : context.astraColors.surface.withValues(alpha: 0);
    final hoveredColor = widget.hoverColor ?? context.astraColors.surfaceHover;
    return Opacity(
      key: ValueKey('track-availability-${widget.track.uri}'),
      opacity: widget.track.isAvailable ? 1 : 0.48,
      child: SizedBox(
        height: 56,
        child: MouseRegion(
          onEnter: desktop ? (_) => setState(() => _hovered = true) : null,
          onExit: desktop ? (_) => setState(() => _hovered = false) : null,
          child: AnimatedContainer(
            duration: animationsDisabled
                ? Duration.zero
                : const Duration(milliseconds: 180),
            color: _hovered ? hoveredColor : baseColor,
            child: Material(
              key: isCurrent
                  ? widget.currentKey ??
                        ValueKey('current-track-${widget.track.id}')
                  : null,
              color: Colors.transparent,
              child: ListTile(
                minVerticalPadding: 0,
                enabled: widget.enabled,
                hoverColor: Colors.transparent,
                leading: TrackArtwork(track: widget.track, size: 48),
                title: Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isCurrent
                      ? TextStyle(color: context.astraColors.accent)
                      : null,
                ),
                subtitle: Text(
                  widget.track.isAvailable
                      ? widget.track.artist ?? 'Artista desconocido'
                      : 'No disponible',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: widget.enabled ? widget.onTap : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent)
                      PlayingIndicator(
                        key: ValueKey(
                          'current-track-indicator-${widget.track.id}',
                        ),
                        playing: playback.$2,
                      ),
                    ?widget.trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
