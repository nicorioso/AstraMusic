import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
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
    dateModified: dateModified,
    isAvailable: isAvailable,
    favoritedAt: favoritedAt,
    artworkPath: artworkPath,
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
    dateModified: Value(dateModified),
    searchText: Value(
      buildTrackSearchText(title: title, artist: artist, album: album),
    ),
    sortTitle: Value(normalizeForSearch(title)),
    isAvailable: Value(isAvailable),
    isFavorite: Value(isFavorite),
    favoritedAt: Value(favoritedAt),
    artworkPath: Value(artworkPath),
  );
}
