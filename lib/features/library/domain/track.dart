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
    this.isAvailable = true,
    this.isFavorite = false,
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
  final bool isAvailable;
  final bool isFavorite;
}
