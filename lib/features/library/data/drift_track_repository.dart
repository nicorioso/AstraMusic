import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
import 'package:astramusic/features/library/data/track_mapper.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:drift/drift.dart';

final class DriftTrackRepository implements TrackRepository {
  DriftTrackRepository(this._database);

  final AppDatabase _database;

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

  List<Track> _toDomainList(List<TrackRow> rows) =>
      List.unmodifiable(rows.map((row) => row.toDomain()));
}

String _escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
