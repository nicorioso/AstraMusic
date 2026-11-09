import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/media_store_metadata_access.dart';
import 'package:astramusic/features/library/application/metadata_editor_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('escribe tags y carátula en MP3 y conserva la playlist', () async {
    final directory = await Directory.systemTemp.createTemp('metadata_edit_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/song.mp3');
    await file.writeAsBytes([
      ...'ID3'.codeUnits,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0xff,
      0xfb,
      0x90,
      0x64,
      ...List<int>.filled(413, 0),
    ]);
    final cover = File('${directory.path}/cover.png');
    await cover.writeAsBytes(
      image.encodePng(image.Image(width: 16, height: 16)),
    );

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftTrackRepository(database);
    await repository.upsertAll([
      Track(
        uri: file.uri.toString(),
        title: 'Viejo',
        dateAdded: DateTime.utc(2026),
        isFavorite: true,
      ),
    ]);
    final original = (await repository.watchAll().first).single;
    final playlistId = await database
        .into(database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: 'Lista',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
    await database
        .into(database.playlistTracks)
        .insert(
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            trackId: original.id!,
            position: 0,
            addedAt: DateTime.utc(2026),
          ),
        );
    await LocalMetadataEditorService(
      repository,
      cacheDirectory: () async => directory,
    ).save(
      original,
      MetadataEdit(
        title: 'Nuevo título',
        artist: 'Nueva artista',
        album: 'Nuevo álbum',
        year: 2024,
        genre: 'Rock',
        imagePath: cover.path,
      ),
    );

    final stored = (await repository.watchAll().first).single;
    final tags = readMetadata(file, getImage: true);
    expect(tags.title, 'Nuevo título');
    expect(tags.artist, 'Nueva artista');
    expect(tags.album, 'Nuevo álbum');
    expect(tags.year?.year, 2024);
    expect(tags.genres, contains('Rock'));
    expect(tags.pictures, isNotEmpty);
    expect(stored.title, 'Nuevo título');
    expect(stored.id, original.id);
    expect(stored.isFavorite, isTrue);
    expect(await File(stored.artworkPath!).exists(), isTrue);
    expect(
      (await database.select(database.playlistTracks).get()).single.trackId,
      original.id,
    );
    expect(
      (await repository.watchSearch('nuevo titulo').first).single.id,
      original.id,
    );
  });

  test('escribe una URI de MediaStore antes de actualizar Drift', () async {
    final directory = await Directory.systemTemp.createTemp('media_tags_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/working.mp3');
    await file.writeAsBytes([
      ...'ID3'.codeUnits,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0xff,
      0xfb,
      0x90,
      0x64,
      ...List<int>.filled(413, 0),
    ]);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftTrackRepository(database);
    const uri = 'content://media/external/audio/media/1';
    await repository.upsertAll([
      Track(uri: uri, title: 'Viejo', dateAdded: DateTime.utc(2026)),
    ]);
    final original = (await repository.watchAll().first).single;
    final access = _RecordingMediaAccess(file.path);
    await LocalMetadataEditorService(
      repository,
      cacheDirectory: () async => directory,
      mediaStoreAccess: access,
    ).save(
      original,
      const MetadataEdit(
        title: 'Nuevo',
        artist: 'Artista',
        album: null,
        year: null,
        genre: null,
      ),
    );
    expect(access.calls, ['prepare', 'commit', 'cleanup']);
    expect(readMetadata(file).title, 'Nuevo');
    expect((await repository.watchAll().first).single.id, original.id);
    expect((await repository.watchAll().first).single.title, 'Nuevo');
  });

  test('si MediaStore rechaza la escritura no cambia Drift', () async {
    final directory = await Directory.systemTemp.createTemp('media_fail_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/working.mp3');
    await file.writeAsBytes([
      ...'ID3'.codeUnits,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0xff,
      0xfb,
      0x90,
      0x64,
      ...List<int>.filled(413, 0),
    ]);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftTrackRepository(database);
    const uri = 'content://media/external/audio/media/2';
    await repository.upsertAll([
      Track(uri: uri, title: 'Viejo', dateAdded: DateTime.utc(2026)),
    ]);
    final original = (await repository.watchAll().first).single;
    final access = _RecordingMediaAccess(file.path)..failCommit = true;
    await expectLater(
      LocalMetadataEditorService(
        repository,
        cacheDirectory: () async => directory,
        mediaStoreAccess: access,
      ).save(
        original,
        const MetadataEdit(
          title: 'Nuevo',
          artist: null,
          album: null,
          year: null,
          genre: null,
        ),
      ),
      throwsStateError,
    );
    expect(access.calls, ['prepare', 'commit', 'cleanup']);
    expect((await repository.watchAll().first).single.title, 'Viejo');
  });

  test('rechaza formatos sin escritura', () {
    expect(
      canEditTrackMetadata(
        Track(
          id: 1,
          uri: 'file:///song.ogg',
          title: 'Tema',
          dateAdded: DateTime.utc(2026),
        ),
      ),
      isFalse,
    );
  });
}

final class _RecordingMediaAccess implements MediaStoreMetadataAccess {
  _RecordingMediaAccess(this.filePath);
  final String filePath;
  final List<String> calls = [];
  bool failCommit = false;

  @override
  Future<String> prepare(String uri) async {
    calls.add('prepare');
    return filePath;
  }

  @override
  Future<void> commit(String uri) async {
    calls.add('commit');
    if (failCommit) throw StateError('Permiso denegado');
  }

  @override
  Future<void> cleanup() async => calls.add('cleanup');
}
