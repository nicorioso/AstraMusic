class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastPlayedAt,
  });

  final int id;
  final String name;
  final int trackCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPlayedAt;
}
