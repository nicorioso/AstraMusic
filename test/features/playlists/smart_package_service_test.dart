import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/playlists/application/smart_package_service.dart';
import 'package:astramusic/features/playlists/data/drift_playlist_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  late AppDatabase sourceDb;
  late AppDatabase targetDb;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('smart-package-test-');
    sourceDb = AppDatabase(NativeDatabase.memory());
    targetDb = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
    await root.delete(recursive: true);
  });

  test('exporta e importa audios y reconstruye playlist en orden', () async {
    final sourceTracks = DriftTrackRepository(sourceDb);
    final sourceLists = DriftPlaylistRepository(sourceDb);
    final original = <Track>[];
    for (var i = 0; i < 2; i++) {
      final file = File(path.join(root.path, 'original-$i.mp3'));
      await file.writeAsBytes([i, i + 1, i + 2]);
      original.add(
        Track(
          uri: i == 0 ? file.path : file.uri.toString(),
          title: 'Canción $i',
          artist: 'Artista $i',
          album: 'Álbum',
          duration: Duration(seconds: i + 1),
          dateAdded: DateTime.utc(2026),
        ),
      );
    }
    await sourceTracks.upsertAll(original);
    final ids = (await sourceTracks.findByUris(
      original.map((e) => e.uri).toSet(),
    )).map((track) => track.id!).toList()..sort();
    final list = await sourceLists.create('Viaje');
    await sourceLists.addTracks(list.id, ids.reversed.toList());
    final package = File(path.join(root.path, 'viaje.amplaylist'));
    await SmartPackageService(
      sourceLists,
      sourceTracks,
      root,
    ).export(list.id, package);

    final archive = ZipDecoder().decodeBytes(await package.readAsBytes());
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('playlist.json')!.content),
    );
    expect(manifest['version'], 1);
    expect(manifest['name'], 'Viaje');
    expect(manifest['description'], '');
    expect((manifest['tracks'] as List).length, 2);

    final targetTracks = DriftTrackRepository(targetDb);
    final targetLists = DriftPlaylistRepository(targetDb);
    final result = await SmartPackageService(
      targetLists,
      targetTracks,
      Directory(path.join(root.path, 'library')),
    ).import(package);
    expect(result.added, 2);
    final imported = await targetLists.watchTracks(result.playlistId).first;
    expect(imported.map((track) => track.title), ['Canción 1', 'Canción 0']);
    expect(imported.map((track) => track.duration?.inSeconds), [2, 1]);
    for (final track in imported) {
      expect(await File.fromUri(Uri.parse(track.uri)).exists(), isTrue);
    }
    await File(original.first.uri).delete();
    expect(await File.fromUri(Uri.parse(imported.last.uri)).readAsBytes(), [
      0,
      1,
      2,
    ]);
  });

  test('rechaza manifiesto incompleto sin crear playlist', () async {
    final package = File(path.join(root.path, 'broken.amplaylist'));
    final encoder = ZipFileEncoder()..create(package.path);
    await encoder.addFile(
      await File(path.join(root.path, 'playlist.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'name': 'Rota',
          'description': '',
          'tracks': [
            {'title': 'Perdida', 'file': 'audio/00000.mp3'},
          ],
        }),
      ),
      'playlist.json',
    );
    await encoder.close();
    final lists = DriftPlaylistRepository(targetDb);
    await expectLater(
      SmartPackageService(
        lists,
        DriftTrackRepository(targetDb),
        root,
      ).import(package),
      throwsFormatException,
    );
    expect(await lists.watchAll().first, isEmpty);
  });
}
