import 'dart:io';

import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza campos y une artistas sin duplicados', () {
    final tags = normalizeAudioTags(
      fallbackTitle: 'respaldo',
      title: '  Canción  ',
      artists: const [' Artista ', '', 'Invitado', 'Artista'],
      album: '  Álbum  ',
      trackNumber: 4,
      year: 2026,
      durationMs: 1234,
    );

    expect(tags.title, 'Canción');
    expect(tags.artist, 'Artista, Invitado');
    expect(tags.album, 'Álbum');
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
}
