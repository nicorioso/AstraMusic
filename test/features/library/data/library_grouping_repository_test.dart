import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTrackRepository repository;
  setUp(() { database = AppDatabase(NativeDatabase.memory()); repository = DriftTrackRepository(database); });
  tearDown(() => database.close());

  test('agrupa artistas, álbumes y géneros con sus conteos', () async {
    await repository.upsertAll([
      _track('uno', artist: 'Aurora', album: 'Luz', genre: 'Rock', year: 2020),
      _track('dos', artist: 'Aurora', album: 'Luz', genre: 'Rock', year: 2020),
      _track('tres', artist: 'Aurora', album: 'Mar', genre: 'Jazz'),
    ]);
    final artist = (await repository.watchArtists().first).single;
    expect((artist.name, artist.trackCount, artist.albumCount), ('Aurora', 3, 2));
    expect((await repository.watchAlbums().first).map((item) => item.title), ['Luz', 'Mar']);
    expect(
      (await repository.watchGenres().first)
          .firstWhere((item) => item.name == 'Rock')
          .trackCount,
      2,
    );
  });

  test('agrupa carpetas registradas y ordena pistas de álbum por número', () async {
    await database.into(database.libraryFolders).insert(LibraryFoldersCompanion.insert(path: '/musica', addedAt: DateTime(2026)));
    await repository.upsertAll([
      _track('dos', artist: 'A', album: 'Álbum', trackNumber: 2, folderPath: '/musica'),
      _track('uno', artist: 'A', album: 'Álbum', trackNumber: 1, folderPath: '/musica'),
    ]);
    expect((await repository.watchFolders().first).single.trackCount, 2);
    expect((await repository.watchAlbumTracks(title: 'Álbum', artist: 'A').first).map((track) => track.title), ['uno', 'dos']);
  });
}

Track _track(String title, {String? artist, String? album, String? genre, int? year, int? trackNumber, String? folderPath}) => Track(
  uri: 'file:///$title.mp3', title: title, artist: artist, album: album, genre: genre, year: year,
  trackNumber: trackNumber, folderPath: folderPath, dateAdded: DateTime(2026),
);
