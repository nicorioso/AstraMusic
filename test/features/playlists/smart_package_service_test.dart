import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/playlists/application/smart_package_service.dart';
import 'package:astramusic/features/playlists/data/drift_playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
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

  testWidgets('exporta e importa audios y carátulas visibles en la UI', (
    tester,
  ) async {
    final importedData = await tester.runAsync(() async {
      final sourceTracks = DriftTrackRepository(sourceDb);
      final sourceLists = DriftPlaylistRepository(sourceDb);
      final original = <Track>[];
      final originalArtworks = <File>[];
      final cover = File(path.join(root.path, 'playlist-cover.png'));
      await cover.writeAsBytes(
        image.encodePng(image.Image(width: 8, height: 8)),
      );
      for (var i = 0; i < 2; i++) {
        final file = File(path.join(root.path, 'original-$i.mp3'));
        await file.writeAsBytes([i, i + 1, i + 2]);
        final artwork = File(path.join(root.path, 'track-$i.png'));
        await artwork.writeAsBytes(
          image.encodePng(image.Image(width: 8, height: 8)),
        );
        originalArtworks.add(artwork);
        original.add(
          Track(
            uri: i == 0 ? file.path : file.uri.toString(),
            title: 'Canción $i',
            artist: 'Artista $i',
            album: 'Álbum',
            duration: Duration(seconds: i + 1),
            dateAdded: DateTime.utc(2026),
            artworkPath: artwork.path,
          ),
        );
      }
      await sourceTracks.upsertAll(original);
      final ids = (await sourceTracks.findByUris(
        original.map((e) => e.uri).toSet(),
      )).map((track) => track.id!).toList()..sort();
      final list = await sourceLists.create('Viaje');
      await sourceLists.setCustomArtwork(list.id, cover.path);
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
      expect(manifest['coverImage'], 'images/playlist_cover.png');
      expect((manifest['tracks'] as List).length, 2);
      expect(
        (manifest['tracks'] as List).first['artUri'],
        'images/track_00000.png',
      );
      expect(archive.findFile('images/playlist_cover.png'), isNotNull);
      expect(archive.findFile('images/track_00000.png'), isNotNull);

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
      final importedList = (await targetLists
          .watchById(result.playlistId)
          .first)!;
      expect(await File(importedList.customArtworkPath!).exists(), isTrue);
      for (final track in imported) {
        expect(await File.fromUri(Uri.parse(track.uri)).exists(), isTrue);
        expect(await File(track.artworkPath!).exists(), isTrue);
      }
      await File(original.first.uri).delete();
      await cover.delete();
      for (final artwork in originalArtworks) {
        await artwork.delete();
      }
      expect(await File.fromUri(Uri.parse(imported.last.uri)).readAsBytes(), [
        0,
        1,
        2,
      ]);
      return (playlist: importedList, track: imported.first);
    });
    final importedList = importedData!.playlist;
    final importedTrack = importedData.track;
    final artworkProvider = CachedArtworkProvider();
    expect(
      await tester.runAsync(
        () => artworkProvider.artworkFor(importedTrack, size: 256),
      ),
      importedTrack.artworkPath,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [artworkProviderProvider.overrideWithValue(artworkProvider)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlaylistCover(playlist: importedList, size: 64),
                TrackArtwork(track: importedTrack, size: 48),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('playlist-custom-cover-${importedList.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('artwork-${importedTrack.uri}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  for (final invalidAudio in ['playlist.json', 'images/track_00000.png']) {
    test('rechaza $invalidAudio como archivo de audio', () async {
      final staging = Directory(path.join(root.path, 'invalid-audio'));
      await Directory(path.join(staging.path, 'images'))
          .create(recursive: true);
      await File(path.join(staging.path, 'images', 'track_00000.png'))
          .writeAsBytes(image.encodePng(image.Image(width: 1, height: 1)));
      await File(path.join(staging.path, 'playlist.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'name': 'Inválida',
          'description': '',
          'tracks': [
            {'title': 'Falsa', 'file': invalidAudio},
          ],
        }),
      );
      final package = File(path.join(root.path, 'invalid-audio.amplaylist'));
      await ZipFileEncoder().zipDirectory(staging, filename: package.path);
      final lists = DriftPlaylistRepository(targetDb);
      final library = Directory(path.join(root.path, 'library'));
      await expectLater(
        SmartPackageService(
          lists,
          DriftTrackRepository(targetDb),
          library,
        ).import(package),
        throwsFormatException,
      );
      expect(await lists.watchAll().first, isEmpty);
      expect(await library.exists(), isFalse);
    });
  }

  test('dos importaciones usan carpetas distintas', () async {
    final staging = Directory(path.join(root.path, 'repeated'));
    await Directory(path.join(staging.path, 'audio')).create(recursive: true);
    await File(path.join(staging.path, 'audio', '00000.mp3'))
        .writeAsBytes([1, 2, 3]);
    await File(path.join(staging.path, 'playlist.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'name': 'Repetida',
        'description': '',
        'tracks': [
          {'title': 'Pista', 'file': 'audio/00000.mp3'},
        ],
      }),
    );
    final package = File(path.join(root.path, 'repeated.amplaylist'));
    await ZipFileEncoder().zipDirectory(staging, filename: package.path);
    final lists = DriftPlaylistRepository(targetDb);
    final service = SmartPackageService(
      lists,
      DriftTrackRepository(targetDb),
      Directory(path.join(root.path, 'library')),
    );
    final imports = await Future.wait([
      service.import(package),
      service.import(package),
    ]);
    final first = (await lists.watchTracks(imports[0].playlistId).first).single;
    final second =
        (await lists.watchTracks(imports[1].playlistId).first).single;
    expect(first.uri, isNot(second.uri));
    expect(await File.fromUri(Uri.parse(first.uri)).exists(), isTrue);
    expect(await File.fromUri(Uri.parse(second.uri)).exists(), isTrue);
  });

  test('importa paquetes anteriores sin imágenes', () async {
    final staging = Directory(path.join(root.path, 'legacy'));
    await Directory(path.join(staging.path, 'audio')).create(recursive: true);
    await File(path.join(staging.path, 'audio', '00000.mp3'))
        .writeAsBytes([1, 2, 3]);
    await File(path.join(staging.path, 'playlist.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'name': 'Anterior',
        'description': '',
        'tracks': [
          {'title': 'Pista', 'file': 'audio/00000.mp3'},
        ],
      }),
    );
    final package = File(path.join(root.path, 'legacy.amplaylist'));
    await ZipFileEncoder().zipDirectory(staging, filename: package.path);
    final lists = DriftPlaylistRepository(targetDb);
    final result = await SmartPackageService(
      lists,
      DriftTrackRepository(targetDb),
      Directory(path.join(root.path, 'library')),
    ).import(package);
    expect(result.added, 1);
    expect(
      (await lists.watchById(result.playlistId).first)!.customArtworkPath,
      isNull,
    );
    expect(
      (await lists.watchTracks(result.playlistId).first).single.artworkPath,
      isNull,
    );
  });
}
