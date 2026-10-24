import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula el tamaño físico redondeando hacia arriba', () {
    expect(physicalArtworkPixels(48, 1), 48);
    expect(physicalArtworkPixels(48, 2), 96);
    expect(physicalArtworkPixels(55.5, 2.625), 146);
  });

  testWidgets('muestra placeholder cuando no hay carátula', (tester) async {
    final track = Track(
      uri: 'file:///sin-caratula.mp3',
      title: 'Sin carátula',
      dateAdded: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkProviderProvider.overrideWithValue(_EmptyArtworkProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: TrackArtwork(track: track, size: 48)),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('artwork-placeholder-file:///sin-caratula.mp3'),
      ),
      findsOneWidget,
    );
  });
}

final class _EmptyArtworkProvider implements ArtworkProvider {
  @override
  Future<String?> artworkFor(Track track, {required int size}) async => null;
}
