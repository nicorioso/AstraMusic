import 'package:flutter/foundation.dart';

@immutable
final class ArtistGroup {
  const ArtistGroup({
    required this.name,
    required this.trackCount,
    required this.albumCount,
  });

  final String name;
  final int trackCount;
  final int albumCount;
}

@immutable
final class AlbumGroup {
  const AlbumGroup({
    required this.title,
    required this.artist,
    required this.trackCount,
    this.artworkPath,
    this.year,
  });

  final String title;
  final String artist;
  final int trackCount;
  final String? artworkPath;
  final int? year;
}

@immutable
final class GenreGroup {
  const GenreGroup({required this.name, required this.trackCount});

  final String name;
  final int trackCount;
}

@immutable
final class FolderGroup {
  const FolderGroup({
    required this.id,
    required this.path,
    required this.trackCount,
  });

  final int id;
  final String path;
  final int trackCount;
}
