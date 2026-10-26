class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.addedAt,
    required this.createdAt,
    required this.updatedAt,
    this.lastPlayedAt,
    this.customArtworkPath,
  });

  final int id;
  final String name;
  final int trackCount;
  final DateTime addedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPlayedAt;
  final String? customArtworkPath;
}
