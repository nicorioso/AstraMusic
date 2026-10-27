import 'dart:io';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/theme/contrast.dart';
import 'package:astramusic/core/theme/dynamic_artwork_color.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:image/image.dart' as image;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('oscurece el color y conserva contraste AA', () {
    const foreground = Color(0xFFF5EBDD);
    final result = darkAccessibleArtworkColor(
      const Color(0xFFFFD54F),
      foreground: foreground,
    );

    expect(result, isNotNull);
    expect(
      HSLColor.fromColor(result!).lightness,
      lessThanOrEqualTo(maximumDynamicColorLightness),
    );
    expect(
      contrastRatio(foreground, result),
      greaterThanOrEqualTo(minimumDynamicColorContrast),
    );
  });

  test('rechaza el color si no puede dar contraste y acepta ausencia', () {
    expect(
      darkAccessibleArtworkColor(
        const Color(0xFF101010),
        foreground: Colors.black,
      ),
      isNull,
    );
    expect(darkAccessibleArtworkColor(null, foreground: Colors.white), isNull);
  });

  test('sin carátula la caché indica usar el fondo por defecto', () async {
    final cache = DynamicArtworkColorCache(_NoArtworkProvider());
    final color = await cache.colorFor(
      Track(
        uri: 'file:///sin-portada.mp3',
        title: 'Sin portada',
        dateAdded: DateTime(2026),
      ),
      foreground: Colors.white,
    );

    expect(color, isNull);
  });

  test('calcula el color una sola vez por clave de carátula', () async {
    final provider = _CountingArtworkProvider();
    final cache = DynamicArtworkColorCache(provider);
    final track = Track(
      uri: 'file:///album/cancion.mp3',
      title: 'Canción',
      artist: 'Artista',
      album: 'Álbum',
      dateAdded: DateTime(2026),
    );

    await Future.wait([
      cache.colorFor(track, foreground: Colors.white),
      cache.colorFor(track, foreground: Colors.white),
    ]);

    expect(provider.calls, 1);
  });

  test('cachea la carátula personalizada sin consultar canciones', () async {
    final directory = await Directory.systemTemp.createTemp('astra-cover-');
    addTearDown(() => directory.delete(recursive: true));
    final bitmap = image.Image(width: 32, height: 32);
    image.fill(bitmap, color: image.ColorRgb8(220, 30, 50));
    final file = File('${directory.path}/playlist.png')
      ..writeAsBytesSync(image.encodePng(bitmap));
    final scheme = await ColorScheme.fromImageProvider(
      provider: FileImage(file),
      brightness: Brightness.dark,
    );
    expect(scheme.primaryContainer, isA<Color>());
    final provider = _CountingArtworkProvider();
    final cache = DynamicArtworkColorCache(provider);

    final first = cache.colorForImage(file.path, foreground: Colors.white);
    final second = cache.colorForImage(file.path, foreground: Colors.white);

    expect(identical(first, second), isTrue);
    expect(await first, isNotNull);
    expect(provider.calls, 0);
  });
}

final class _NoArtworkProvider implements ArtworkProvider {
  @override
  Future<String?> artworkFor(Track track, {required int size}) async => null;
}

final class _CountingArtworkProvider implements ArtworkProvider {
  int calls = 0;

  @override
  Future<String?> artworkFor(Track track, {required int size}) async {
    calls++;
    return null;
  }
}
