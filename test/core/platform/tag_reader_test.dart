import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('normaliza campos y une artistas sin duplicados', () {
    final tags = normalizeAudioTags(
      fallbackTitle: 'respaldo',
      title: '  Canción  ',
      artists: const [' Artista ', '', 'Invitado', 'Artista'],
      album: '  Álbum  ',
      genres: const [' ', ' Rock '],
      trackNumber: 4,
      year: 2026,
      durationMs: 1234,
    );

    expect(tags.title, 'Canción');
    expect(tags.artist, 'Artista, Invitado');
    expect(tags.album, 'Álbum');
    expect(tags.genre, 'Rock');
    expect(tags.trackNumber, 4);
    expect(tags.year, 2026);
    expect(tags.durationMs, 1234);
  });

  test('usa fallback y descarta números inválidos', () {
    final tags = normalizeAudioTags(
      fallbackTitle: '  archivo  ',
      title: ' ',
      trackNumber: 0,
      year: -1,
      durationMs: 0,
    );

    expect(tags.title, 'archivo');
    expect(tags.artist, isNull);
    expect(tags.album, isNull);
    expect(tags.trackNumber, isNull);
    expect(tags.year, isNull);
    expect(tags.durationMs, isNull);
  });

  test('el lector reporta un archivo ilegible', () {
    final result = readTagsSafely(
      const AudioMetadataTagReader(),
      File('/ruta/que/no/existe/audio.mp3'),
    );

    expect(result.hadError, isTrue);
    expect(result.tags.title, 'audio');
  });

  test('convierte rutas file y rechaza content URI', () {
    final fileUri = Uri.file('/música/tema.mp3').toString();
    expect(localFilePathFromLocation(fileUri), '/música/tema.mp3');
    expect(
      localFilePathFromLocation('content://media/external/audio/media/1'),
      isNull,
    );
  });

  test('extrae la carátula incrustada de un archivo MP3 de prueba', () async {
    final directory = await Directory.systemTemp.createTemp('tag_artwork_');
    addTearDown(() => directory.delete(recursive: true));
    final audio = File('${directory.path}/sample.mp3');
    final sourceImage = image.encodePng(image.Image(width: 1200, height: 900));
    await audio.writeAsBytes(_mp3WithPicture(Uint8List.fromList(sourceImage)));

    final result = readLocalAudioFileWithArtwork(audio.path, directory.path);

    expect(result.artworkPath, isNotNull);
    final saved = image.decodeImage(
      await File(result.artworkPath!).readAsBytes(),
    );
    expect(saved, isNotNull);
    expect(saved!.width, 640);
    expect(saved.height, 480);
    expect(result.artworkPath, endsWith('.jpg'));
  });

  test('prefiere la portada frontal entre varias imágenes incrustadas', () {
    final back = Picture(
      Uint8List.fromList([1]),
      'image/jpeg',
      PictureType.coverBack,
    );
    final front = Picture(
      Uint8List.fromList([2]),
      'image/jpeg',
      PictureType.coverFront,
    );

    expect(selectPrimaryArtwork([back, front]), same(front));
  });
}

Uint8List _mp3WithPicture(Uint8List image) {
  final payload = <int>[3, ...'image/png'.codeUnits, 0, 3, 0, ...image];
  final frame = <int>[
    ...'APIC'.codeUnits,
    ..._syncSafe(payload.length),
    0,
    0,
    ...payload,
  ];
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    4,
    0,
    0,
    ..._syncSafe(frame.length),
    ...frame,
  ]);
}

List<int> _syncSafe(int value) => [
  (value >> 21) & 0x7f,
  (value >> 14) & 0x7f,
  (value >> 7) & 0x7f,
  value & 0x7f,
];
