import 'package:astramusic/core/db/app_database.dart';
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
        (track) => OrderingTerm.asc(track.title.collate(Collate.noCase)),
      ]);
    return query.watch().map(_toDomainList);
  }

  @override
  Stream<List<Track>> watchSearch(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return watchAll();

    final statement = _database.select(_database.tracks)
      ..where(
        (track) =>
            track.title.lower().contains(normalizedQuery) |
            track.artist.lower().contains(normalizedQuery) |
            track.album.lower().contains(normalizedQuery),
      )
      ..orderBy([
        (track) => OrderingTerm.asc(track.title.collate(Collate.noCase)),
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
  Future<void> deleteAll() async {
    await _database.delete(_database.tracks).go();
  }

  List<Track> _toDomainList(List<TrackRow> rows) =>
      List.unmodifiable(rows.map((row) => row.toDomain()));
}
