import 'dart:collection';
import 'dart:io';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/contrast.dart';
import 'package:astramusic/core/widgets/astra_background.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const minimumDynamicColorContrast = 4.5;
const maximumDynamicColorLightness = 0.2;

Color? darkAccessibleArtworkColor(Color? source, {required Color foreground}) {
  if (source == null) return null;
  final hsl = HSLColor.fromColor(source);
  final darkened = hsl
      .withLightness(hsl.lightness.clamp(0.0, maximumDynamicColorLightness))
      .toColor();
  return contrastRatio(foreground, darkened) >= minimumDynamicColorContrast
      ? darkened
      : null;
}

final dynamicArtworkColorCacheProvider = Provider<DynamicArtworkColorCache>(
  (ref) => DynamicArtworkColorCache(ref.watch(artworkProviderProvider)),
);

final class DynamicArtworkColorCache {
  DynamicArtworkColorCache(this._artworkProvider, {this.capacity = 48});

  final ArtworkProvider _artworkProvider;
  final int capacity;
  final LinkedHashMap<String, Future<Color?>> _colors = LinkedHashMap();

  Future<Color?> colorFor(Track track, {required Color foreground}) {
    final key = artworkCacheKey(
      artist: track.artist,
      album: track.album,
      uri: track.uri,
    );
    final cached = _colors.remove(key);
    if (cached != null) {
      _colors[key] = cached;
      return cached;
    }
    final result = _extract(track, foreground);
    _colors[key] = result;
    while (_colors.length > capacity) {
      _colors.remove(_colors.keys.first);
    }
    return result;
  }

  Future<Color?> _extract(Track track, Color foreground) async {
    try {
      final path = await _artworkProvider.artworkFor(
        track,
        size: artworkThumbnailBucket(ArtworkUsage.dynamicColor),
      );
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final scheme = await ColorScheme.fromImageProvider(
        provider: FileImage(file),
        brightness: Brightness.dark,
      );
      return darkAccessibleArtworkColor(
        scheme.primaryContainer,
        foreground: foreground,
      );
    } on Object {
      return null;
    }
  }
}

typedef DynamicArtworkColorWidgetBuilder = Widget Function(
  BuildContext context,
  Color? color,
);

class DynamicArtworkColorBuilder extends ConsumerStatefulWidget {
  const DynamicArtworkColorBuilder({
    required this.track,
    required this.builder,
    super.key,
  });

  final Track? track;
  final DynamicArtworkColorWidgetBuilder builder;

  @override
  ConsumerState<DynamicArtworkColorBuilder> createState() =>
      _DynamicArtworkColorBuilderState();
}

class _DynamicArtworkColorBuilderState
    extends ConsumerState<DynamicArtworkColorBuilder> {
  Future<Color?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(DynamicArtworkColorBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identity(oldWidget.track) != _identity(widget.track)) _load();
  }

  void _load() {
    final track = widget.track;
    _future = track == null
        ? Future<Color?>.value()
        : ref
              .read(dynamicArtworkColorCacheProvider)
              .colorFor(track, foreground: context.astraColors.text);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Color?>(
    future: _future,
    builder: (context, snapshot) => widget.builder(context, snapshot.data),
  );
}

String? _identity(Track? track) => track == null
    ? null
    : artworkCacheKey(artist: track.artist, album: track.album, uri: track.uri);

class DynamicArtworkBackground extends StatelessWidget {
  const DynamicArtworkBackground({
    required this.track,
    required this.child,
    super.key,
  });

  final Track? track;
  final Widget child;

  @override
  Widget build(BuildContext context) => DynamicArtworkColorBuilder(
    track: track,
    builder: (context, color) {
      if (color == null) return AstraBackground(child: child);
      return ColoredBox(
        key: const Key('dynamic-artwork-background'),
        color: context.astraColors.voidColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, context.astraColors.voidColor],
            ),
          ),
          child: child,
        ),
      );
    },
  );
}
