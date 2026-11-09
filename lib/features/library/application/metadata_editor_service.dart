import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:astramusic/core/platform/artwork_cache.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/core/platform/media_store_metadata_access.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const writableAudioExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.mp4',
  '.wav',
  '.ape',
};

bool canEditTrackMetadata(Track track) {
  final filePath = localFilePathFromLocation(track.uri);
  if (track.uri.startsWith('content://media/')) return true;
  return filePath != null &&
      writableAudioExtensions.contains(path.extension(filePath).toLowerCase());
}

class MetadataEdit {
  const MetadataEdit({
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.genre,
    this.imagePath,
  });

  final String title;
  final String? artist;
  final String? album;
  final int? year;
  final String? genre;
  final String? imagePath;
}

abstract interface class MetadataEditorService {
  Future<void> save(Track track, MetadataEdit edit);
}

final class LocalMetadataEditorService implements MetadataEditorService {
  LocalMetadataEditorService(
    this._repository, {
    Future<Directory> Function()? cacheDirectory,
    MediaStoreMetadataAccess? mediaStoreAccess,
  }) : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
       _mediaStoreAccess =
           mediaStoreAccess ?? AndroidMediaStoreMetadataAccess();

  final TrackRepository _repository;
  final Future<Directory> Function() _cacheDirectory;
  final MediaStoreMetadataAccess _mediaStoreAccess;

  @override
  Future<void> save(Track track, MetadataEdit edit) async {
    if (track.id == null || !canEditTrackMetadata(track)) {
      throw UnsupportedError('Este archivo no admite edición de etiquetas.');
    }
    if (edit.title.trim().isEmpty) {
      throw ArgumentError('El título es obligatorio.');
    }
    final mediaStore = track.uri.startsWith('content://media/');
    final filePath = mediaStore
        ? await _mediaStoreAccess.prepare(track.uri)
        : localFilePathFromLocation(track.uri)!;
    _WriteResult? result;
    try {
      final cache = await _cacheDirectory();
      result = await Isolate.run(
        () => _writeAndRead((filePath, cache.path, edit)),
      );
      if (mediaStore) await _mediaStoreAccess.commit(track.uri);
    } catch (_) {
      if (result?.artworkPath case final artworkPath?) {
        await File(artworkPath).delete();
      }
      rethrow;
    } finally {
      if (mediaStore) await _mediaStoreAccess.cleanup();
    }
    final current = await _repository.getById(track.id!);
    if (current == null || current.uri != track.uri) {
      throw StateError('La canción ya no está en la biblioteca.');
    }
    final saved = result!;
    await _repository.upsertAll([
      Track(
        id: current.id,
        uri: current.uri,
        title: saved.tags.title,
        artist: saved.tags.artist,
        album: saved.tags.album,
        genre: saved.tags.genre,
        folderPath: current.folderPath,
        duration: current.duration,
        trackNumber: current.trackNumber,
        year: saved.tags.year,
        fileSize: saved.fileSize,
        dateAdded: current.dateAdded,
        dateModified: saved.modified,
        isAvailable: current.isAvailable,
        favoritedAt: current.favoritedAt,
        artworkPath: saved.artworkPath ?? current.artworkPath,
      ),
    ]);
  }
}

class _WriteResult {
  const _WriteResult(this.tags, this.fileSize, this.modified, this.artworkPath);
  final AudioTags tags;
  final int fileSize;
  final DateTime modified;
  final String? artworkPath;
}

_WriteResult _writeAndRead((String, String, MetadataEdit) request) {
  final (filePath, cachePath, edit) = request;
  final file = File(filePath);
  Uint8List? coverBytes;
  if (edit.imagePath case final selected?) {
    final imageFile = File(selected);
    final decoded = image.decodeImage(imageFile.readAsBytesSync());
    if (decoded == null) throw const FormatException('La imagen no es válida.');
    final resized = decoded.width > 1200 || decoded.height > 1200
        ? image.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1200 : null,
            height: decoded.height > decoded.width ? 1200 : null,
          )
        : decoded;
    coverBytes = Uint8List.fromList(image.encodeJpg(resized, quality: 88));
  }
  updateMetadata(file, (metadata) {
    metadata.setTitle(edit.title.trim());
    final artist = _trimOrNull(edit.artist);
    if (metadata case VorbisMetadata vorbis when artist == null) {
      vorbis.artist = [];
    } else {
      metadata.setArtist(artist);
    }
    metadata.setAlbum(_trimOrNull(edit.album));
    metadata.setYear(edit.year == null ? null : DateTime(edit.year!));
    metadata.setGenres([?_trimOrNull(edit.genre)]);
    if (coverBytes != null) {
      metadata.setPictures([
        Picture(coverBytes, 'image/jpeg', PictureType.coverFront),
      ]);
    }
  });
  final metadata = readMetadata(file, getImage: false);
  final tags = normalizeAudioTags(
    fallbackTitle: path.basenameWithoutExtension(filePath),
    title: metadata.title,
    artists: [metadata.artist],
    album: metadata.album,
    genres: metadata.genres,
    year: metadata.year?.year,
  );
  String? artworkPath;
  if (coverBytes != null) {
    final artworkDir = Directory(path.join(cachePath, 'artwork'))
      ..createSync(recursive: true);
    final unique =
        '${filePath.hashCode}-${DateTime.now().microsecondsSinceEpoch}.jpg';
    final target = File(path.join(artworkDir.path, unique));
    target.writeAsBytesSync(coverBytes, flush: true);
    enforceArtworkCacheQuotaSync(artworkDir, preserve: target);
    artworkPath = target.path;
  }
  final stat = file.statSync();
  return _WriteResult(tags, stat.size, stat.modified, artworkPath);
}

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
