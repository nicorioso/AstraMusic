import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/playback_state_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/drift.dart';

final class DriftPlaybackStateRepository implements PlaybackStateRepository {
  DriftPlaybackStateRepository(this._database);

  final AppDatabase _database;

  @override
  Future<PersistedPlaybackState?> load() async {
    final state = await _database
        .select(_database.playbackState)
        .getSingleOrNull();
    if (state == null) return null;
    final query =
        _database.select(_database.queueItems).join([
            innerJoin(
              _database.tracks,
              _database.tracks.id.equalsExp(_database.queueItems.trackId),
            ),
          ])
          ..where(_database.tracks.isAvailable.equals(true))
          ..orderBy([OrderingTerm.asc(_database.queueItems.position)]);
    final rows = await query.get();
    final items = rows
        .map((row) {
          final item = row.readTable(_database.queueItems);
          return PersistedQueueItem(
            track: _toTrack(row.readTable(_database.tracks)),
            position: item.position,
            originalPosition: item.originalPosition,
          );
        })
        .toList(growable: false);
    if (items.isEmpty) return null;
    final savedIndex = state.currentIndex;
    final adjustedIndex = savedIndex == null
        ? null
        : items
              .where((item) => item.position < savedIndex)
              .length
              .clamp(0, items.length - 1);
    return PersistedPlaybackState(
      queue: items,
      currentIndex: adjustedIndex,
      position: Duration(milliseconds: state.positionMs),
      shuffle: state.shuffle,
      repeatMode: RepeatMode.values.firstWhere(
        (mode) => mode.name == state.repeatMode,
        orElse: () => RepeatMode.off,
      ),
    );
  }

  @override
  Future<void> save(PlaybackStateSnapshot snapshot) async {
    final valid = snapshot.queue.every((track) => track.id != null);
    if (!valid) return;
    final originalPositions = <int, List<int>>{};
    for (var index = 0; index < snapshot.originalQueue.length; index++) {
      final id = snapshot.originalQueue[index].id;
      if (id != null) (originalPositions[id] ??= []).add(index);
    }
    final usedOccurrences = <int, int>{};
    await _database.transaction(() async {
      await _database.delete(_database.queueItems).go();
      await _database.delete(_database.playbackState).go();
      if (snapshot.queue.isEmpty) return;
      await _database.batch((batch) {
        batch.insert(
          _database.playbackState,
          PlaybackStateCompanion.insert(
            currentIndex: Value(snapshot.currentIndex),
            positionMs: Value(snapshot.position.inMilliseconds),
            shuffle: Value(snapshot.shuffle),
            repeatMode: Value(snapshot.repeatMode.name),
            updatedAt: DateTime.now(),
          ),
        );
        for (var index = 0; index < snapshot.queue.length; index++) {
          final id = snapshot.queue[index].id!;
          final occurrence = usedOccurrences.update(
            id,
            (value) => value + 1,
            ifAbsent: () => 0,
          );
          final positions = originalPositions[id];
          batch.insert(
            _database.queueItems,
            QueueItemsCompanion.insert(
              position: Value(index),
              trackId: id,
              originalPosition: Value(
                snapshot.shuffle &&
                        positions != null &&
                        occurrence < positions.length
                    ? positions[occurrence]
                    : null,
              ),
            ),
          );
        }
      });
    });
  }

  Track _toTrack(TrackRow row) => Track(
    id: row.id,
    uri: row.uri,
    title: row.title,
    artist: row.artist,
    album: row.album,
    duration: row.durationMs == null
        ? null
        : Duration(milliseconds: row.durationMs!),
    trackNumber: row.trackNumber,
    year: row.year,
    fileSize: row.fileSize,
    dateAdded: row.dateAdded,
    dateModified: row.dateModified,
    isAvailable: row.isAvailable,
    isFavorite: row.isFavorite,
    artworkPath: row.artworkPath,
  );
}
