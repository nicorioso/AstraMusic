class Track {
  const Track({
    this.id,
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.genre,
    this.folderPath,
    this.duration,
    this.trackNumber,
    this.year,
    this.fileSize,
    required this.dateAdded,
    this.dateModified,
    this.isAvailable = true,
    bool isFavorite = false,
    DateTime? favoritedAt,
    this.artworkPath,
  }) : favoritedAt = favoritedAt ?? (isFavorite ? dateAdded : null);

  final int? id;
  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? folderPath;
  final Duration? duration;
  final int? trackNumber;
  final int? year;
  final int? fileSize;
  final DateTime dateAdded;
  final DateTime? dateModified;
  final bool isAvailable;
  final DateTime? favoritedAt;
  bool get isFavorite => favoritedAt != null;
  final String? artworkPath;

  Track withAvailability(bool value) => Track(
    id: id,
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    folderPath: folderPath,
    duration: duration,
    trackNumber: trackNumber,
    year: year,
    fileSize: fileSize,
    dateAdded: dateAdded,
    dateModified: dateModified,
    isAvailable: value,
    favoritedAt: favoritedAt,
    artworkPath: artworkPath,
  );

  Track withArtworkPath(String value) => Track(
    id: id,
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    folderPath: folderPath,
    duration: duration,
    trackNumber: trackNumber,
    year: year,
    fileSize: fileSize,
    dateAdded: dateAdded,
    dateModified: dateModified,
    isAvailable: isAvailable,
    favoritedAt: favoritedAt,
    artworkPath: value,
  );
}
