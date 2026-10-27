import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
import 'package:astramusic/features/library/data/track_mapper.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_list_query.dart';
import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/library_grouping_repository.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

final class DriftTrackRepository
    implements
        PaginatedTrackRepository,
        FilteredTrackRepository,
        LibraryGroupingRepository {
  DriftTrackRepository(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;

  @override
  Stream<List<Track>> watchAll() {
    final query = _database.select(_database.tracks)
      ..orderBy([
        (track) => OrderingTerm.asc(track.sortTitle),
        (track) => OrderingTerm.asc(track.id),
      ]);
    return query.watch().map(_toDomainList);
  }

  @override
  Stream<List<Track>> watchPage({
    required int limit,
    int offset = 0,
    String query = '',
  }) {
    return watchFilteredPage(
      limit: limit,
      offset: offset,
      query: TrackListQuery(search: query),
    );
  }

  @override
  Stream<List<Track>> watchFilteredPage({
    required int limit,
    int offset = 0,
    TrackListQuery query = const TrackListQuery(),
  }) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Debe ser mayor que cero.');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'No puede ser negativo.');
    }

    final normalizedQuery = normalizeForSearch(query.search);
    final statement = _database.select(_database.tracks);
    if (normalizedQuery.isNotEmpty) {
      final escapedQuery = _escapeLike(normalizedQuery);
      statement.where(
        (track) => track.searchText.like('%$escapedQuery%', escapeChar: r'\'),
      );
    }
    if (query.favoritesOnly) {
      statement.where((track) => track.favoritedAt.isNotNull());
    }
    if (query.availableOnly) {
      statement.where((track) => track.isAvailable.equals(true));
    }
    statement
      ..orderBy(_ordering(query.sort))
      ..limit(limit, offset: offset);
    return statement.watch().map(_toDomainList);
  }

  List<OrderingTerm Function(Tracks)> _ordering(TrackSort sort) =>
      switch (sort) {
        TrackSort.title => [
          (track) => OrderingTerm.asc(track.sortTitle),
          (track) => OrderingTerm.asc(track.id),
        ],
        TrackSort.dateAdded => [
          (track) => OrderingTerm.desc(track.dateAdded),
          (track) => OrderingTerm.desc(track.id),
        ],
        TrackSort.artist => [
          (track) => OrderingTerm.asc(track.artist),
          (track) => OrderingTerm.asc(track.sortTitle),
        ],
        TrackSort.year => [
          (track) => OrderingTerm.desc(track.year),
          (track) => OrderingTerm.asc(track.sortTitle),
        ],
        TrackSort.duration => [
          (track) => OrderingTerm.desc(track.durationMs),
          (track) => OrderingTerm.asc(track.sortTitle),
        ],
      };

  @override
  Stream<List<Track>> watchSearch(String query) {
    final normalizedQuery = normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return watchAll();
    final escapedQuery = _escapeLike(normalizedQuery);

    final statement = _database.select(_database.tracks)
      ..where(
        (track) => track.searchText.like('%$escapedQuery%', escapeChar: r'\'),
      )
      ..orderBy([
        (track) => OrderingTerm.asc(track.sortTitle),
        (track) => OrderingTerm.asc(track.id),
      ]);
    return statement.watch().map(_toDomainList);
  }

  @override
  Stream<List<Track>> watchFavorites() {
    final query = _database.select(_database.tracks)
      ..where((track) => track.favoritedAt.isNotNull())
      ..orderBy([
        (track) => OrderingTerm.desc(track.favoritedAt),
        (track) => OrderingTerm.desc(track.id),
      ]);
    return query.watch().map(_toDomainList);
  }

  @override
  Stream<List<ArtistGroup>> watchArtists() => _database
      .customSelect(
        '''SELECT COALESCE(NULLIF(TRIM(artist), ''), 'Artista desconocido') AS name,
       COUNT(*) AS track_count,
       COUNT(DISTINCT NULLIF(TRIM(album), '')) AS album_count,
       MAX(artwork_path) AS artwork_path
       FROM tracks GROUP BY COALESCE(NULLIF(TRIM(artist), ''), 'Artista desconocido')
       ORDER BY name COLLATE NOCASE''',
        readsFrom: {_database.tracks},
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (row) => ArtistGroup(
              name: row.read<String>('name'),
              trackCount: row.read<int>('track_count'),
              albumCount: row.read<int>('album_count'),
              artworkPath: row.read<String?>('artwork_path'),
            ),
          ),
        ),
      );

  @override
  Stream<List<AlbumGroup>> watchAlbums() => _database
      .customSelect(
        '''SELECT COALESCE(NULLIF(TRIM(album), ''), 'Álbum desconocido') AS title,
       COALESCE(NULLIF(TRIM(artist), ''), 'Artista desconocido') AS artist,
       COUNT(*) AS track_count, MAX(artwork_path) AS artwork_path, MIN(year) AS year
       FROM tracks
       GROUP BY COALESCE(NULLIF(TRIM(album), ''), 'Álbum desconocido'),
                COALESCE(NULLIF(TRIM(artist), ''), 'Artista desconocido')
       ORDER BY title COLLATE NOCASE, artist COLLATE NOCASE''',
        readsFrom: {_database.tracks},
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (row) => AlbumGroup(
              title: row.read<String>('title'),
              artist: row.read<String>('artist'),
              trackCount: row.read<int>('track_count'),
              artworkPath: row.read<String?>('artwork_path'),
              year: row.read<int?>('year'),
            ),
          ),
        ),
      );

  @override
  Stream<List<GenreGroup>> watchGenres() => _database
      .customSelect(
        '''SELECT COALESCE(NULLIF(TRIM(genre), ''), 'Sin género') AS name,
       COUNT(*) AS track_count, MAX(artwork_path) AS artwork_path FROM tracks
       GROUP BY COALESCE(NULLIF(TRIM(genre), ''), 'Sin género')
       ORDER BY name COLLATE NOCASE''',
        readsFrom: {_database.tracks},
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (row) => GenreGroup(
              name: row.read<String>('name'),
              trackCount: row.read<int>('track_count'),
              artworkPath: row.read<String?>('artwork_path'),
            ),
          ),
        ),
      );

  @override
  Stream<List<FolderGroup>> watchFolders() => _database
      .customSelect(
        '''SELECT library_folders.id, library_folders.path, COUNT(tracks.id) AS track_count
       FROM library_folders LEFT JOIN tracks ON tracks.folder_path = library_folders.path
       GROUP BY library_folders.id, library_folders.path
       ORDER BY library_folders.path COLLATE NOCASE''',
        readsFrom: {_database.libraryFolders, _database.tracks},
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (row) => FolderGroup(
              id: row.read<int>('id'),
              path: row.read<String>('path'),
              trackCount: row.read<int>('track_count'),
            ),
          ),
        ),
      );

  @override
  Stream<List<Track>> watchArtistTracks(String artist) => _watchGroupTracks(
    artist == 'Artista desconocido'
        ? _database.tracks.artist.isNull() | _database.tracks.artist.equals('')
        : _database.tracks.artist.equals(artist),
  );

  @override
  Stream<List<Track>> watchAlbumTracks({
    required String title,
    required String artist,
  }) {
    final album = title == 'Álbum desconocido'
        ? _database.tracks.album.isNull() | _database.tracks.album.equals('')
        : _database.tracks.album.equals(title);
    final owner = artist == 'Artista desconocido'
        ? _database.tracks.artist.isNull() | _database.tracks.artist.equals('')
        : _database.tracks.artist.equals(artist);
    return _watchGroupTracks(album & owner, byTrack: true);
  }

  @override
  Stream<List<Track>> watchGenreTracks(String genre) => _watchGroupTracks(
    genre == 'Sin género'
        ? _database.tracks.genre.isNull() | _database.tracks.genre.equals('')
        : _database.tracks.genre.equals(genre),
  );

  @override
  Stream<List<Track>> watchFolderTracks(String path) =>
      _watchGroupTracks(_database.tracks.folderPath.equals(path));

  Stream<List<Track>> _watchGroupTracks(
    Expression<bool> predicate, {
    bool byTrack = false,
  }) {
    final query = _database.select(_database.tracks)..where((_) => predicate);
    query.orderBy(
      byTrack
          ? [
              (track) => OrderingTerm.asc(track.trackNumber),
              (track) => OrderingTerm.asc(track.sortTitle),
            ]
          : [
              (track) => OrderingTerm.asc(track.sortTitle),
              (track) => OrderingTerm.asc(track.id),
            ],
    );
    return query.watch().map(_toDomainList);
  }

  @override
  Future<void> setFavorite(int id, bool favorite) async {
    await (_database.update(
      _database.tracks,
    )..where((track) => track.id.equals(id))).write(
      TracksCompanion(
        isFavorite: Value(favorite),
        favoritedAt: Value(favorite ? _now() : null),
      ),
    );
  }

  @override
  Future<void> upsertAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    await _database.transaction(() async {
      await _database.batch((batch) {
        for (final track in tracks) {
          final companion = track.toCompanion();
          batch.insert(
            _database.tracks,
            companion,
            onConflict: DoUpdate(
              (_) => companion,
              target: [_database.tracks.uri],
            ),
          );
        }
      });
    });
  }

  @override
  Future<void> markUnavailable(Set<String> uris) async {
    if (uris.isEmpty) return;

    await (_database.update(_database.tracks)
          ..where((track) => track.uri.isIn(uris)))
        .write(const TracksCompanion(isAvailable: Value(false)));
  }

  @override
  Future<void> setAvailability(Map<String, bool> availability) async {
    if (availability.isEmpty) return;
    await _database.batch((batch) {
      for (final entry in availability.entries) {
        batch.update(
          _database.tracks,
          TracksCompanion(isAvailable: Value(entry.value)),
          where: (track) => track.uri.equals(entry.key),
        );
      }
    });
  }

  @override
  Future<Track?> getById(int id) async {
    final query = _database.select(_database.tracks)
      ..where((track) => track.id.equals(id));
    return (await query.getSingleOrNull())?.toDomain();
  }

  @override
  Future<int> count() async {
    final countExpression = _database.tracks.id.count();
    final query = _database.selectOnly(_database.tracks)
      ..addColumns([countExpression]);
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  @override
  Future<void> deleteByUris(Set<String> uris) async {
    if (uris.isEmpty) return;
    await (_database.delete(
      _database.tracks,
    )..where((track) => track.uri.isIn(uris))).go();
  }

  @override
  Future<void> deleteAll() async {
    await _database.delete(_database.tracks).go();
  }

  @override
  Future<Set<String>> excludedUris() async {
    final rows = await _database.select(_database.excludedUris).get();
    return rows.map((row) => row.uri).toSet();
  }

  @override
  Future<void> excludeAndDelete(Track track) async {
    await _database.transaction(() async {
      await _database
          .into(_database.excludedUris)
          .insertOnConflictUpdate(ExcludedUrisCompanion.insert(uri: track.uri));
      await (_database.delete(
        _database.tracks,
      )..where((row) => row.uri.equals(track.uri))).go();
    });
  }

  @override
  Future<void> restoreExcluded(Set<String> uris) async {
    if (uris.isEmpty) return;
    await (_database.delete(
      _database.excludedUris,
    )..where((row) => row.uri.isIn(uris))).go();
  }

  @override
  Future<void> clearLibrary() async {
    await _database.transaction(() async {
      await _database.delete(_database.playlistTracks).go();
      await _database.delete(_database.queueItems).go();
      await _database.delete(_database.playbackState).go();
      await _database.delete(_database.playlists).go();
      await _database.delete(_database.tracks).go();
      await _database.delete(_database.libraryFolders).go();
      await _database.delete(_database.excludedUris).go();
    });
  }

  List<Track> _toDomainList(List<TrackRow> rows) {
    final stopwatch = Stopwatch()..start();
    final result = List<Track>.unmodifiable(rows.map((row) => row.toDomain()));
    stopwatch.stop();
    if (kDebugMode && rows.length >= 500) {
      debugPrint(
        'AstraMusic DB: mapeó ${rows.length} canciones en '
        '${stopwatch.elapsedMilliseconds} ms.',
      );
    }
    return result;
  }
}

String _escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
