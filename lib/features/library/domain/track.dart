class Track {
  const Track({
    this.id,
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
    this.fileSize,
    required this.dateAdded,
    this.dateModified,
    this.isAvailable = true,
    this.isFavorite = false,
    this.artworkPath,
  });

  final int? id;
  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final int? trackNumber;
  final int? year;
  final int? fileSize;
  final DateTime dateAdded;
  final DateTime? dateModified;
  final bool isAvailable;
  final bool isFavorite;
  final String? artworkPath;

  Track withAvailability(bool value) => Track(
    id: id,
    uri: uri,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    trackNumber: trackNumber,
    year: year,
    fileSize: fileSize,
    dateAdded: dateAdded,
    dateModified: dateModified,
    isAvailable: value,
    isFavorite: isFavorite,
    artworkPath: artworkPath,
  );
}
