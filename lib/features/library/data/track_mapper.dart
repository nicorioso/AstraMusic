import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:drift/drift.dart';

extension TrackRowMapper on TrackRow {
  Track toDomain() => Track(
    id: id,
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    duration: durationMs == null ? null : Duration(milliseconds: durationMs!),
    trackNumber: trackNumber,
    year: year,
    fileSize: fileSize,
    dateAdded: dateAdded,
    isAvailable: isAvailable,
    isFavorite: isFavorite,
  );
}

extension TrackCompanionMapper on Track {
  TracksCompanion toCompanion() => TracksCompanion.insert(
    uri: uri,
    title: title,
    artist: Value(artist),
    album: Value(album),
    durationMs: Value(duration?.inMilliseconds),
    trackNumber: Value(trackNumber),
    year: Value(year),
    fileSize: Value(fileSize),
    dateAdded: dateAdded,
    isAvailable: Value(isAvailable),
    isFavorite: Value(isFavorite),
  );
}
