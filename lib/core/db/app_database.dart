import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:astramusic/core/utils/search_normalization.dart';

part 'app_database.g.dart';

@DataClassName('TrackRow')
@TableIndex(name: 'tracks_sort_title_idx', columns: {#sortTitle, #id})
@TableIndex(name: 'tracks_artist_idx', columns: {#artist, #id})
@TableIndex(name: 'tracks_album_idx', columns: {#album, #id})
@TableIndex(name: 'tracks_date_added_idx', columns: {#dateAdded, #id})
@TableIndex(name: 'tracks_is_favorite_idx', columns: {#isFavorite, #id})
@TableIndex(name: 'tracks_folder_path_idx', columns: {#folderPath, #id})
@TableIndex(name: 'tracks_genre_idx', columns: {#genre, #id})
@TableIndex(
  name: 'tracks_search_sort_idx',
  columns: {#searchText, #sortTitle, #id},
)
@TableIndex(name: 'tracks_artist_sort_idx', columns: {#artist, #sortTitle, #id})
@TableIndex(name: 'tracks_album_artist_idx', columns: {#album, #artist, #id})
@TableIndex(
  name: 'tracks_folder_sort_idx',
  columns: {#folderPath, #sortTitle, #id},
)
@TableIndex(name: 'tracks_favorited_at_idx', columns: {#favoritedAt, #id})
@TableIndex(name: 'tracks_play_count_idx', columns: {#playCount, #id})
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uri => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get genre => text().nullable()();
  TextColumn get folderPath => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get dateModified => dateTime().nullable()();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  TextColumn get sortTitle => text().withDefault(const Constant(''))();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get favoritedAt => dateTime().nullable()();
  TextColumn get artworkPath => text().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get customArtworkPath => text().nullable()();
  DateTimeColumn get addedAt =>
      dateTime().withDefault(const CustomExpression<DateTime>('0'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
}

@DataClassName('PlaylistTrackRow')
@TableIndex(
  name: 'playlist_tracks_playlist_position_idx',
  columns: {#playlistId, #position},
)
@TableIndex(
  name: 'playlist_tracks_playlist_track_idx',
  columns: {#playlistId, #trackId},
  unique: true,
)
class PlaylistTracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();
}

@DataClassName('PlayHistoryRow')
@TableIndex(name: 'play_history_played_at_idx', columns: {#playedAt, #id})
@TableIndex(name: 'play_history_track_id_idx', columns: {#trackId, #id})
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime()();
}

@DataClassName('LibraryFolderRow')
class LibraryFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();
}

@DataClassName('PlaybackStateRow')
class PlaybackState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get currentIndex => integer().nullable()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  BoolColumn get shuffle => boolean().withDefault(const Constant(false))();
  TextColumn get repeatMode => text().withDefault(const Constant('off'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('QueueItemRow')
class QueueItems extends Table {
  IntColumn get position => integer()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get originalPosition => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {position};
}

@DataClassName('ExcludedUriRow')
class ExcludedUris extends Table {
  TextColumn get uri => text()();

  @override
  Set<Column<Object>> get primaryKey => {uri};
}

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistTracks,
    PlayHistory,
    LibraryFolders,
    PlaybackState,
    QueueItems,
    ExcludedUris,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'astramusic'));

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createTrackSearchIndex();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(libraryFolders);
      }
      if (from < 3) {
        await migrator.addColumn(tracks, tracks.dateModified);
        await migrator.addColumn(tracks, tracks.searchText);
        await migrator.addColumn(tracks, tracks.sortTitle);
        await transaction(() async {
          const batchSize = 500;
          var offset = 0;
          while (true) {
            final rows = await customSelect(
              'SELECT id, title, artist, album FROM tracks ORDER BY id LIMIT ? OFFSET ?',
              variables: [
                Variable.withInt(batchSize),
                Variable.withInt(offset),
              ],
            ).get();
            if (rows.isEmpty) break;
            await batch((batch) {
              for (final row in rows) {
                batch.update(
                  tracks,
                  TracksCompanion(
                    searchText: Value(
                      buildTrackSearchText(
                        title: row.read<String>('title'),
                        artist: row.read<String?>('artist'),
                        album: row.read<String?>('album'),
                      ),
                    ),
                    sortTitle: Value(
                      normalizeForSearch(row.read<String>('title')),
                    ),
                  ),
                  where: (track) => track.id.equals(row.read<int>('id')),
                );
              }
            });
            offset += rows.length;
          }
        });
        await customStatement('DROP INDEX IF EXISTS tracks_title_idx');
        await migrator.createIndex(tracksSortTitleIdx);
      }
      if (from < 4) {
        await migrator.addColumn(tracks, tracks.artworkPath);
      }
      if (from < 5) {
        await migrator.createTable(playbackState);
        await migrator.createTable(queueItems);
      }
      if (from < 6) {
        await migrator.createTable(excludedUris);
      }
      if (from < 7) {
        await migrator.addColumn(playlists, playlists.lastPlayedAt);
        await customStatement('''
          DELETE FROM playlist_tracks
          WHERE id NOT IN (
            SELECT MIN(id)
            FROM playlist_tracks
            GROUP BY playlist_id, track_id
          )
        ''');
        await migrator.createIndex(playlistTracksPlaylistTrackIdx);
      }
      if (from < 8) {
        await migrator.addColumn(tracks, tracks.favoritedAt);
        await customStatement('''
          UPDATE tracks
          SET favorited_at = date_added
          WHERE is_favorite = 1
        ''');
      }
      if (from < 9) {
        await migrator.addColumn(playlists, playlists.customArtworkPath);
        await migrator.addColumn(playlists, playlists.addedAt);
        await customStatement('''
          UPDATE playlists
          SET added_at = created_at
          WHERE added_at = 0
        ''');
      }
      if (from < 10) {
        await migrator.createIndex(tracksArtistIdx);
        await migrator.createIndex(tracksAlbumIdx);
        await migrator.createIndex(tracksDateAddedIdx);
        await migrator.createIndex(tracksIsFavoriteIdx);
      }
      if (from < 11) {
        await migrator.addColumn(tracks, tracks.genre);
        await migrator.addColumn(tracks, tracks.folderPath);
        await migrator.createIndex(tracksFolderPathIdx);
        await migrator.createIndex(tracksGenreIdx);
      }
      if (from < 12) {
        await migrator.createIndex(tracksSearchSortIdx);
        await migrator.createIndex(tracksArtistSortIdx);
        await migrator.createIndex(tracksAlbumArtistIdx);
        await migrator.createIndex(tracksFolderSortIdx);
        await migrator.createIndex(tracksFavoritedAtIdx);
        await _createTrackSearchIndex();
      }
      if (from < 13) {
        await migrator.addColumn(tracks, tracks.playCount);
        await migrator.createIndex(tracksPlayCountIdx);
        await migrator.createTable(playHistory);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createTrackSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts
      USING fts5(search_text, content = 'tracks', content_rowid = 'id')
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_fts_insert AFTER INSERT ON tracks BEGIN
        INSERT INTO tracks_fts(rowid, search_text) VALUES (new.id, new.search_text);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_fts_delete AFTER DELETE ON tracks BEGIN
        INSERT INTO tracks_fts(tracks_fts, rowid, search_text)
        VALUES ('delete', old.id, old.search_text);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_fts_update
      AFTER UPDATE OF search_text ON tracks BEGIN
        INSERT INTO tracks_fts(tracks_fts, rowid, search_text)
        VALUES ('delete', old.id, old.search_text);
        INSERT INTO tracks_fts(rowid, search_text) VALUES (new.id, new.search_text);
      END
    ''');
    await customStatement(
      "INSERT INTO tracks_fts(tracks_fts) VALUES ('rebuild')",
    );
  }
}
