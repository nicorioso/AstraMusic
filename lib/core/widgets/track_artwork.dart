import 'dart:io';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrackArtwork extends ConsumerStatefulWidget {
  const TrackArtwork({
    super.key,
    required this.track,
    required this.size,
    this.usage = ArtworkUsage.list,
  });

  final Track track;
  final double size;
  final ArtworkUsage usage;

  @override
  ConsumerState<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends ConsumerState<TrackArtwork> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.uri != widget.track.uri ||
        oldWidget.track.artworkPath != widget.track.artworkPath ||
        oldWidget.size != widget.size ||
        oldWidget.usage != widget.usage) {
      _path = null;
      _load();
    }
  }

  Future<void> _load() async {
    final uri = widget.track.uri;
    final result = await ref
        .read(artworkProviderProvider)
        .artworkFor(widget.track, size: artworkThumbnailBucket(widget.usage));
    if (mounted && widget.track.uri == uri) setState(() => _path = result);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null || !File(path).existsSync()) return _placeholder(context);
    final physicalSize = physicalArtworkPixels(
      widget.size,
      MediaQuery.devicePixelRatioOf(context),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(path),
        key: ValueKey('artwork-${widget.track.uri}'),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: physicalSize,
        cacheHeight: physicalSize,
        errorBuilder: (_, _, _) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    key: ValueKey('artwork-placeholder-${widget.track.uri}'),
    width: widget.size,
    height: widget.size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [context.astraColors.surfaceHover, context.astraColors.ember],
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Icon(
      Icons.music_note,
      color: context.astraColors.accent,
      size: widget.size * 0.5,
    ),
  );
}

int physicalArtworkPixels(double logicalSize, double devicePixelRatio) =>
    (logicalSize * devicePixelRatio).ceil();
