import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:path/path.dart' as path;

/// Formato 1: playlist.json, audios en audio/ e imágenes opcionales en images/.
final class SmartPackageService {
  SmartPackageService(this._playlists, this._tracks, this._libraryDirectory);

  final PlaylistRepository _playlists;
  final SyncTrackRepository _tracks;
  final Directory _libraryDirectory;

  Future<void> export(int playlistId, File target) async {
    final playlist = await _playlists.watchById(playlistId).first;
    if (playlist == null) throw StateError('La playlist no existe.');
    final tracks = await _playlists.watchTracks(playlistId).first;
    final staging = await Directory.systemTemp.createTemp(
      'astramusic-package-',
    );
    try {
      final audio = Directory(path.join(staging.path, 'audio'));
      await audio.create();
      final images = Directory(path.join(staging.path, 'images'));
      String? coverImage;
      final coverPath = playlist.customArtworkPath?.trim();
      if (coverPath != null && coverPath.isNotEmpty) {
        coverImage = await _copyArtwork(coverPath, images, 'playlist_cover');
      }
      final entries = <Map<String, Object?>>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final localPath = localFilePathFromLocation(track.uri);
        if (localPath == null) {
          throw FileSystemException(
            'La canción no es un archivo local exportable',
            track.uri,
          );
        }
        final source = File(localPath);
        if (!await source.exists()) {
          throw FileSystemException('Falta el audio', source.path);
        }
        final filename =
            '${index.toString().padLeft(5, '0')}${path.extension(source.path)}';
        await source.copy(path.join(audio.path, filename));
        String? artUri;
        final artworkPath = track.artworkPath?.trim();
        if (artworkPath != null && artworkPath.isNotEmpty) {
          artUri = await _copyArtwork(
            artworkPath,
            images,
            'track_${index.toString().padLeft(5, '0')}',
          );
        }
        final entry = <String, Object?>{
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'durationMs': track.duration?.inMilliseconds,
          'file': 'audio/$filename',
        };
        if (artUri != null) entry['artUri'] = artUri;
        entries.add(entry);
      }
      final manifest = <String, Object?>{
        'version': 1,
        'name': playlist.name,
        'description': '',
        'tracks': entries,
      };
      if (coverImage != null) manifest['coverImage'] = coverImage;
      await File(path.join(staging.path, 'playlist.json'))
          .writeAsString(jsonEncode(manifest));
      await ZipFileEncoder().zipDirectory(staging, filename: target.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<String> _copyArtwork(
    String sourcePath,
    Directory images,
    String stem,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Falta la carátula', sourcePath);
    }
    final extension = path.extension(source.path).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]+$').hasMatch(extension)) {
      throw const FormatException('La carátula no tiene una extensión válida.');
    }
    await images.create(recursive: true);
    final filename = '$stem$extension';
    await source.copy(path.join(images.path, filename));
    return 'images/$filename';
  }

  Future<({int playlistId, int added})> import(File source) async {
    final staging = await Directory.systemTemp.createTemp('astramusic-import-');
    Directory? destination;
    InputFileStream? input;
    int? playlistId;
    final importedUris = <String>{};
    try {
      input = InputFileStream(source.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final files = <String, ArchiveFile>{};
      for (final entry in archive) {
        if (entry.isDirectory &&
            (entry.name == 'audio/' || entry.name == 'images/')) {
          continue;
        }
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            (entry.name != 'playlist.json' && !_isPackageFile(entry.name)) ||
            files.containsKey(entry.name)) {
          throw const FormatException(
            'El paquete contiene entradas inválidas.',
          );
        }
        files[entry.name] = entry;
      }
      final manifestFile = files['playlist.json'];
      if (manifestFile == null) {
        throw const FormatException('Falta playlist.json.');
      }
      final manifest = jsonDecode(utf8.decode(manifestFile.content));
      if (manifest is! Map<String, dynamic> ||
          manifest['version'] != 1 ||
          manifest['name'] is! String ||
          (manifest['name'] as String).trim().isEmpty ||
          manifest['description'] is! String ||
          (manifest['coverImage'] != null &&
              !_isArtworkReference(manifest['coverImage'], files)) ||
          manifest['tracks'] is! List) {
        throw const FormatException('El manifiesto no es válido.');
      }
      final rows = manifest['tracks'] as List;
      final names = <String>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic> ||
            row['title'] is! String ||
            row['artist'] != null && row['artist'] is! String ||
            row['album'] != null && row['album'] is! String ||
            row['durationMs'] != null &&
                (row['durationMs'] is! int || (row['durationMs'] as int) < 0) ||
            row['file'] is! String ||
            !_isAudioFile(row['file'] as String) ||
            !names.add(row['file'] as String) ||
            !files.containsKey(row['file']) ||
            (row['artUri'] != null &&
                !_isArtworkReference(row['artUri'], files))) {
          throw const FormatException(
            'Las pistas del manifiesto no son válidas.',
          );
        }
      }
      await _libraryDirectory.create(recursive: true);
      destination = await _libraryDirectory.createTemp('package-');
      String? importedCover;
      if (manifest['coverImage'] case final String coverName) {
        importedCover = await _extractArtwork(
          files[coverName]!,
          staging,
          destination,
        );
      }
      final now = DateTime.now();
      final tracks = <Track>[];
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final filename = path.basename(row['file'] as String);
        final staged = File(path.join(staging.path, filename));
        await staged.writeAsBytes(files[row['file']]!.content, flush: true);
        final stored = await staged.copy(path.join(destination.path, filename));
        String? importedArtwork;
        if (row['artUri'] case final String artworkName) {
          importedArtwork = await _extractArtwork(
            files[artworkName]!,
            staging,
            destination,
          );
        }
        tracks.add(
          Track(
            uri: stored.uri.toString(),
            title: row['title'] as String,
            artist: row['artist'] as String?,
            album: row['album'] as String?,
            duration: row['durationMs'] == null
                ? null
                : Duration(milliseconds: row['durationMs'] as int),
            folderPath: destination.path,
            fileSize: await stored.length(),
            dateAdded: now,
            artworkPath: importedArtwork,
          ),
        );
        importedUris.add(stored.uri.toString());
      }
      await _tracks.upsertAll(tracks);
      final found = await _tracks.findByUris(
        tracks.map((track) => track.uri).toSet(),
      );
      final ids = {for (final track in found) track.uri: track.id};
      if (found.length != tracks.length || ids.values.any((id) => id == null)) {
        throw StateError('No se pudieron registrar todas las canciones.');
      }
      final playlist = await _playlists.create(manifest['name'] as String);
      playlistId = playlist.id;
      if (importedCover != null) {
        await _playlists.setCustomArtwork(playlist.id, importedCover);
      }
      final result = await _playlists.addTracks(playlist.id, [
        for (final track in tracks) ids[track.uri]!,
      ]);
      if (result.added != tracks.length) {
        throw StateError('La playlist quedó incompleta.');
      }
      return (playlistId: playlist.id, added: result.added);
    } catch (_) {
      if (playlistId != null) await _playlists.delete(playlistId);
      if (importedUris.isNotEmpty) await _tracks.deleteByUris(importedUris);
      if (destination != null && await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    } finally {
      await input?.close();
      await staging.delete(recursive: true);
    }
  }

  bool _isAudioFile(String name) =>
      RegExp(r'^audio/[0-9]{5}\.[a-zA-Z0-9]+$').hasMatch(name);

  bool _isPackageFile(String name) =>
      _isAudioFile(name) ||
      RegExp(r'^images/(playlist_cover|track_[0-9]{5})\.[a-zA-Z0-9]+$')
          .hasMatch(name);

  bool _isArtworkReference(Object? name, Map<String, ArchiveFile> files) =>
      name is String &&
      name.startsWith('images/') &&
      _isPackageFile(name) &&
      files.containsKey(name);

  Future<String> _extractArtwork(
    ArchiveFile entry,
    Directory staging,
    Directory destination,
  ) async {
    final filename = path.basename(entry.name);
    final staged = File(path.join(staging.path, filename));
    await staged.writeAsBytes(entry.content, flush: true);
    final images = Directory(path.join(destination.path, 'images'));
    await images.create(recursive: true);
    return (await staged.copy(path.join(images.path, filename))).path;
  }
}
