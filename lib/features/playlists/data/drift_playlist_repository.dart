import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/track_mapper.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:drift/drift.dart';

final class DriftPlaylistRepository implements PlaylistRepository {
  DriftPlaylistRepository(
    this._database, {
    DateTime Function()? now,
    this.useAlbumArtworkIdentity = false,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;
  final bool useAlbumArtworkIdentity;
  late final Expression<int> _trackCount = _database.playlistTracks.id.count();

  @override
  Future<Playlist> create(String name) async {
    final normalized = _validName(name);
    final now = _now();
    final id = await _database
        .into(_database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: normalized,
            addedAt: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return Playlist(
      id: id,
      name: normalized,
      trackCount: 0,
      addedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> setCustomArtwork(int id, String? path) async {
    final normalized = path?.trim();
    await (_database.update(
      _database.playlists,
    )..where((row) => row.id.equals(id))).write(
      PlaylistsCompanion(
        customArtworkPath: Value(
          normalized == null || normalized.isEmpty ? null : normalized,
        ),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> rename(int id, String name) async {
    final normalized = _validName(name);
    await (_database.update(
      _database.playlists,
    )..where((row) => row.id.equals(id))).write(
      PlaylistsCompanion(name: Value(normalized), updatedAt: Value(_now())),
    );
  }

  @override
  Future<void> delete(int id) async {
    await (_database.delete(
      _database.playlists,
    )..where((row) => row.id.equals(id))).go();
  }

  @override
  Stream<List<Playlist>> watchAll() => _playlistQuery().watch().map(
    (rows) => List.unmodifiable(rows.map(_mapPlaylist)),
  );

  @override
  Stream<Playlist?> watchById(int id) {
    final query = _playlistQuery()..where(_database.playlists.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _mapPlaylist(row),
    );
  }

  @override
  Stream<List<Track>> watchTracks(int id) {
    final query = _database.select(_database.playlistTracks).join([
      innerJoin(
        _database.tracks,
        _database.tracks.id.equalsExp(_database.playlistTracks.trackId),
      ),
    ])..where(_database.playlistTracks.playlistId.equals(id));
    query.orderBy([OrderingTerm.asc(_database.playlistTracks.position)]);
    return query.watch().map(
      (rows) => List.unmodifiable(
        rows.map((row) => row.readTable(_database.tracks).toDomain()),
      ),
    );
  }

  @override
  Future<AddTracksResult> addTracks(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) {
      return const AddTracksResult(added: 0, alreadyPresent: 0);
    }
    return _database.transaction(() async {
      final existingRows = await (_database.select(
        _database.playlistTracks,
      )..where((row) => row.playlistId.equals(playlistId))).get();
      final existing = existingRows.map((row) => row.trackId).toSet();
      var position = existingRows.isEmpty
          ? 0
          : existingRows
                    .map((row) => row.position)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      var added = 0;
      var alreadyPresent = 0;
      final seen = <int>{};
      for (final trackId in trackIds) {
        if (!seen.add(trackId) || existing.contains(trackId)) {
          alreadyPresent++;
          continue;
        }
        await _database
            .into(_database.playlistTracks)
            .insert(
              PlaylistTracksCompanion.insert(
                playlistId: playlistId,
                trackId: trackId,
                position: position++,
                addedAt: _now(),
              ),
            );
        existing.add(trackId);
        added++;
      }
      if (added > 0) {
        await (_database.update(_database.playlists)
              ..where((row) => row.id.equals(playlistId)))
            .write(PlaylistsCompanion(updatedAt: Value(_now())));
      }
      return AddTracksResult(added: added, alreadyPresent: alreadyPresent);
    });
  }

  @override
  Future<void> removeTrack(int playlistId, int trackId) async {
    await _database.transaction(() async {
      await (_database.delete(_database.playlistTracks)..where(
            (row) =>
                row.playlistId.equals(playlistId) & row.trackId.equals(trackId),
          ))
          .go();
      final remaining =
          await (_database.select(_database.playlistTracks)
                ..where((row) => row.playlistId.equals(playlistId))
                ..orderBy([(row) => OrderingTerm.asc(row.position)]))
              .get();
      await _database.batch((batch) {
        for (var position = 0; position < remaining.length; position++) {
          batch.update(
            _database.playlistTracks,
            PlaylistTracksCompanion(position: Value(position)),
            where: (row) => row.id.equals(remaining[position].id),
          );
        }
      });
      await (_database.update(_database.playlists)
            ..where((row) => row.id.equals(playlistId)))
          .write(PlaylistsCompanion(updatedAt: Value(_now())));
    });
  }

  @override
  Future<void> move(int playlistId, int oldIndex, int newIndex) async {
    await _database.transaction(() async {
      final rows =
          await (_database.select(_database.playlistTracks)
                ..where((row) => row.playlistId.equals(playlistId))
                ..orderBy([(row) => OrderingTerm.asc(row.position)]))
              .get();
      if (oldIndex < 0 ||
          oldIndex >= rows.length ||
          newIndex < 0 ||
          newIndex >= rows.length) {
        throw RangeError('Índices de reordenamiento fuera de rango.');
      }
      if (oldIndex == newIndex) return;
      final reordered = List<PlaylistTrackRow>.of(rows);
      final moved = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, moved);
      await _database.batch((batch) {
        for (var position = 0; position < reordered.length; position++) {
          batch.update(
            _database.playlistTracks,
            PlaylistTracksCompanion(position: Value(position)),
            where: (row) => row.id.equals(reordered[position].id),
          );
        }
      });
      await (_database.update(_database.playlists)
            ..where((row) => row.id.equals(playlistId)))
          .write(PlaylistsCompanion(updatedAt: Value(_now())));
    });
  }

  @override
  Future<void> markPlayed(int id) async {
    await (_database.update(_database.playlists)
          ..where((row) => row.id.equals(id)))
        .write(PlaylistsCompanion(lastPlayedAt: Value(_now())));
  }

  @override
  Stream<List<Playlist>> watchRecent(int limit) {
    if (limit <= 0) return Stream.value(const []);
    final query = _playlistQuery()
      ..where(_database.playlists.lastPlayedAt.isNotNull())
      ..limit(limit);
    return query.watch().map(
      (rows) => List.unmodifiable(rows.map(_mapPlaylist)),
    );
  }

  @override
  Future<List<Track>> coverTracks(int playlistId, {int limit = 4}) async {
    if (limit <= 0) return const [];
    final rows =
        await (_database.select(_database.playlistTracks).join([
                innerJoin(
                  _database.tracks,
                  _database.tracks.id.equalsExp(
                    _database.playlistTracks.trackId,
                  ),
                ),
              ])
              ..where(_database.playlistTracks.playlistId.equals(playlistId))
              ..orderBy([OrderingTerm.asc(_database.playlistTracks.position)]))
            .get();
    final keys = <String>{};
    final result = <Track>[];
    for (final row in rows) {
      final track = row.readTable(_database.tracks).toDomain();
      final artworkPath = track.artworkPath?.trim();
      final artist = track.artist?.trim().toLowerCase();
      final album = track.album?.trim().toLowerCase();
      final key = useAlbumArtworkIdentity
          ? artist != null || album != null
                ? 'album:${artist ?? ''}\u0000${album ?? ''}'
                : 'track:${track.id}'
          : artworkPath != null && artworkPath.isNotEmpty
          ? 'artwork:$artworkPath'
          : 'track:${track.id}';
      if (!keys.add(key)) continue;
      result.add(track);
      if (result.length == limit) break;
    }
    return List.unmodifiable(result);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _playlistQuery() {
    final query = _database.select(_database.playlists).join([
      leftOuterJoin(
        _database.playlistTracks,
        _database.playlistTracks.playlistId.equalsExp(_database.playlists.id),
      ),
    ]);
    query
      ..addColumns([_trackCount])
      ..groupBy([_database.playlists.id])
      ..orderBy([
        OrderingTerm.desc(_database.playlists.lastPlayedAt),
        OrderingTerm.desc(_database.playlists.updatedAt),
      ]);
    return query;
  }

  Playlist _mapPlaylist(TypedResult row) {
    final data = row.readTable(_database.playlists);
    return Playlist(
      id: data.id,
      name: data.name,
      trackCount: row.read(_trackCount) ?? 0,
      addedAt: data.addedAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
      lastPlayedAt: data.lastPlayedAt,
      customArtworkPath: data.customArtworkPath,
    );
  }
}

String _validName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'El nombre no puede estar vacío.');
  }
  return normalized;
}
