import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('elige el cubo de miniatura según el uso', () {
    expect(artworkThumbnailBucket(ArtworkUsage.list), 256);
    expect(artworkThumbnailBucket(ArtworkUsage.miniPlayer), 256);
    expect(artworkThumbnailBucket(ArtworkUsage.player), 640);
    expect(normalizeArtworkThumbnailBucket(48), 256);
    expect(normalizeArtworkThumbnailBucket(512), 640);
  });

  test('la clave de caché cambia entre cubos', () {
    final compact = artworkBucketCacheKey(
      artist: 'Artista',
      album: 'Álbum',
      uri: 'file:///song.mp3',
      bucket: 256,
    );
    final large = artworkBucketCacheKey(
      artist: 'Artista',
      album: 'Álbum',
      uri: 'file:///song.mp3',
      bucket: 640,
    );

    expect(compact, isNot(large));
  });

  test('la clave deduplica por artista y álbum y cae a URI', () {
    final first = artworkCacheKey(
      artist: ' Artista ',
      album: 'ÁLBUM',
      uri: 'uno.mp3',
    );
    final second = artworkCacheKey(
      artist: 'artista',
      album: 'álbum',
      uri: 'dos.mp3',
    );
    expect(first, second);
    expect(
      artworkCacheKey(artist: null, album: 'Álbum', uri: 'uno.mp3'),
      isNot(artworkCacheKey(artist: null, album: 'Álbum', uri: 'dos.mp3')),
    );
  });

  test(
    'selecciona cover antes de folder y front sin importar extensión',
    () async {
      final directory = await Directory.systemTemp.createTemp('artwork_');
      addTearDown(() => directory.delete(recursive: true));
      await File(path.join(directory.path, 'front.png')).writeAsBytes([1]);
      await File(path.join(directory.path, 'folder.jpg')).writeAsBytes([2]);
      await File(path.join(directory.path, 'COVER.PNG')).writeAsBytes([3]);

      expect(path.basename(selectFolderArtwork(directory)!.path), 'COVER.PNG');
    },
  );

  test('ignora una ruta de carátula inválida o eliminada', () async {
    final provider = CachedArtworkProvider();
    final track = Track(
      uri: 'file:///music/song.mp3',
      title: 'Canción',
      dateAdded: DateTime(2026),
      artworkPath: '\u0000ruta-inválida',
    );

    await expectLater(provider.artworkFor(track, size: 48), completion(isNull));
  });

  test('elige la fuente por uri y artworkPath, no por plataforma', () {
    Track track(String uri, {String? artworkPath}) => Track(
      uri: uri,
      title: 'Canción',
      dateAdded: DateTime(2026),
      artworkPath: artworkPath,
    );

    expect(
      artworkSourceFor(track('/cache/song.mp3', artworkPath: '/cover.jpg')),
      ArtworkSource.file,
    );
    expect(
      artworkSourceFor(track('content://media/external/audio/media/1')),
      ArtworkSource.mediaStore,
    );
    expect(artworkSourceFor(track('/cache/song.mp3')), ArtworkSource.none);
  });

  test('limita a tres cargas y deduplica peticiones iguales', () async {
    final directory = await Directory.systemTemp.createTemp('artwork_load_');
    addTearDown(() => directory.delete(recursive: true));
    var active = 0;
    var maximum = 0;
    var calls = 0;
    final gates = <Completer<void>>[];
    final provider = CachedArtworkProvider(
      cacheDirectory: () async => directory,
      thumbnailLoader: (uri, size) async {
        calls++;
        active++;
        maximum = maximum < active ? active : maximum;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        active--;
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    Track track(int id) => Track(
      uri: 'content://media/audio/$id',
      title: '$id',
      dateAdded: DateTime(2026),
    );

    final duplicateA = provider.artworkFor(track(1), size: 256);
    final duplicateB = provider.artworkFor(track(1), size: 256);
    final futures = [
      duplicateA,
      duplicateB,
      for (var id = 2; id <= 5; id++) provider.artworkFor(track(id), size: 256),
    ];
    for (var attempt = 0; calls < 3 && attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(calls, 3);
    expect(maximum, 3);
    while (gates.length < 5 || gates.any((gate) => !gate.isCompleted)) {
      for (final gate in List.of(gates)) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(futures);

    expect(calls, 5);
    expect(maximum, 3);
    expect(await duplicateA, await duplicateB);
  });
}
