import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as path;

class AudioTags {
  const AudioTags({
    required this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.year,
    this.durationMs,
  });

  final String title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? year;
  final int? durationMs;
}

class TagReadResult {
  const TagReadResult({required this.tags, required this.hadError});

  final AudioTags tags;
  final bool hadError;
}

class LocalAudioFileInfo {
  const LocalAudioFileInfo({
    required this.tags,
    required this.fileSize,
    required this.dateModified,
    required this.hadTagError,
  });

  final AudioTags tags;
  final int fileSize;
  final DateTime dateModified;
  final bool hadTagError;
}

abstract interface class TagReader {
  AudioTags read(File file);
}

final class AudioMetadataTagReader implements TagReader {
  const AudioMetadataTagReader();

  @override
  AudioTags read(File file) {
    final metadata = readMetadata(file, getImage: false);
    return normalizeAudioTags(
      fallbackTitle: path.basenameWithoutExtension(file.path),
      title: metadata.title,
      artists: [metadata.artist, ...metadata.performers],
      album: metadata.album,
      trackNumber: metadata.trackNumber,
      year: metadata.year?.year,
      durationMs: metadata.duration?.inMilliseconds,
    );
  }
}

TagReadResult readTagsSafely(TagReader reader, File file) {
  try {
    return TagReadResult(tags: reader.read(file), hadError: false);
  } catch (_) {
    return TagReadResult(
      tags: normalizeAudioTags(
        fallbackTitle: path.basenameWithoutExtension(file.path),
      ),
      hadError: true,
    );
  }
}

LocalAudioFileInfo readLocalAudioFile(String filePath) {
  final file = File(filePath);
  final stat = file.statSync();
  final result = readTagsSafely(const AudioMetadataTagReader(), file);
  return LocalAudioFileInfo(
    tags: result.tags,
    fileSize: stat.size,
    dateModified: stat.modified,
    hadTagError: result.hadError,
  );
}

String? localFilePathFromLocation(String location) {
  if (path.isAbsolute(location)) return path.normalize(location);
  final uri = Uri.tryParse(location);
  if (uri == null || uri.scheme != 'file') return null;
  try {
    return uri.toFilePath(windows: Platform.isWindows);
  } on UnsupportedError {
    return null;
  }
}

AudioTags normalizeAudioTags({
  required String fallbackTitle,
  String? title,
  Iterable<String?> artists = const [],
  String? album,
  int? trackNumber,
  int? year,
  int? durationMs,
}) {
  final normalizedFallback = _nonEmpty(fallbackTitle) ?? 'Audio sin título';
  final uniqueArtists = <String>{};
  for (final artist in artists) {
    final normalized = _nonEmpty(artist);
    if (normalized != null) uniqueArtists.add(normalized);
  }

  return AudioTags(
    title: _nonEmpty(title) ?? normalizedFallback,
    artist: uniqueArtists.isEmpty ? null : uniqueArtists.join(', '),
    album: _nonEmpty(album),
    trackNumber: trackNumber != null && trackNumber > 0 ? trackNumber : null,
    year: year != null && year > 0 ? year : null,
    durationMs: durationMs != null && durationMs > 0 ? durationMs : null,
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
