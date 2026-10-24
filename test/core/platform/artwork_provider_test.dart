import 'dart:io';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
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
}
