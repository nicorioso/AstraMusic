import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/track_mapper.dart';
import 'package:astramusic/features/library/domain/smart_playlist_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/drift.dart';

final class DriftSmartPlaylistRepository implements SmartPlaylistRepository {
  DriftSmartPlaylistRepository(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;

  @override
  Stream<List<Track>> watch(SmartPlaylist playlist, {int limit = 100}) {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final order = switch (playlist) {
      SmartPlaylist.recentlyPlayed => 'ORDER BY (SELECT MAX(played_at) FROM play_history WHERE track_id = tracks.id) DESC, (SELECT MAX(id) FROM play_history WHERE track_id = tracks.id) DESC',
      SmartPlaylist.mostPlayed =>
        'ORDER BY play_count DESC, tracks.sort_title ASC, tracks.id ASC',
      SmartPlaylist.neverPlayed => 'ORDER BY date_added DESC, tracks.id DESC',
      SmartPlaylist.recentlyAdded => 'ORDER BY date_added DESC, tracks.id DESC',
    };
    final filter = switch (playlist) {
      SmartPlaylist.recentlyPlayed =>
        'EXISTS (SELECT 1 FROM play_history WHERE track_id = tracks.id)',
      SmartPlaylist.mostPlayed => 'play_count > 0',
      SmartPlaylist.neverPlayed => 'play_count = 0',
      SmartPlaylist.recentlyAdded => '1 = 1',
    };
    return _database
        .customSelect(
          'SELECT tracks.* FROM tracks WHERE is_available = 1 AND $filter $order LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {_database.tracks, _database.playHistory},
        )
        .watch()
        .map(
          (rows) => List.unmodifiable(
            rows.map((row) => _database.tracks.map(row.data).toDomain()),
          ),
        );
  }

  @override
  Future<void> recordPlay(int trackId) => _database.transaction(() async {
    final changed = await _database.customUpdate(
      'UPDATE tracks SET play_count = play_count + 1 WHERE id = ?',
      variables: [Variable.withInt(trackId)],
      updates: {_database.tracks},
    );
    if (changed == 0) return;
    await _database
        .into(_database.playHistory)
        .insert(
          PlayHistoryCompanion.insert(trackId: trackId, playedAt: _now()),
        );
    await _database.customUpdate(
      'DELETE FROM play_history WHERE id <= '
      '(SELECT COALESCE(MAX(id), 0) - 10000 FROM play_history)',
      updates: {_database.playHistory},
    );
  });
}
