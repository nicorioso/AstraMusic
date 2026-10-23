class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.path,
    required this.addedAt,
    this.lastScannedAt,
  });

  final int id;
  final String path;
  final DateTime addedAt;
  final DateTime? lastScannedAt;
}
