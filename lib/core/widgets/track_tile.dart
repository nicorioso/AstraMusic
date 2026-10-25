import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    required this.track,
    this.onTap,
    this.trailing,
    this.enabled = true,
    this.currentKey,
    this.hoverColor,
    super.key,
  });

  final Track track;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool enabled;
  final Key? currentKey;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrackId = ref.watch(
      playerControllerProvider.select((state) => state.currentItem?.trackId),
    );
    final isCurrent = track.id != null && track.id == currentTrackId;
    return Opacity(
      key: ValueKey('track-availability-${track.uri}'),
      opacity: track.isAvailable ? 1 : 0.48,
      child: SizedBox(
        height: 56,
        child: Material(
          key: isCurrent
              ? currentKey ?? ValueKey('current-track-${track.id}')
              : null,
          color: isCurrent
              ? context.astraColors.surfaceHover
              : context.astraColors.surface.withValues(alpha: 0),
          child: ListTile(
            minVerticalPadding: 0,
            enabled: enabled,
            hoverColor: hoverColor ?? context.astraColors.surfaceHover,
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
              track.isAvailable
                  ? track.artist ?? 'Artista desconocido'
                  : 'No disponible',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: enabled ? onTap : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCurrent)
                  Icon(
                    Icons.graphic_eq,
                    key: ValueKey('current-track-indicator-${track.id}'),
                    color: context.astraColors.accent,
                  ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
