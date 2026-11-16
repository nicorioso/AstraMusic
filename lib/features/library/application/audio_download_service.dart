import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:path/path.dart' as path;

enum AudioImportStatus { downloaded, duplicate, canceled }

class AudioImportResult {
  const AudioImportResult(this.status, {this.track});
  final AudioImportStatus status;
  final Track? track;
}

/// Registra una sola pista por operación; conserva archivos y filas previas.
class AudioDownloadService {
  AudioDownloadService({
    required AudioDownloadBackend backend,
    required TrackRepository tracks,
    required Future<Directory> Function() supportDirectory,
    required Future<Directory> Function() temporaryDirectory,
    TagReader tagReader = const AudioMetadataTagReader(),
  }) : this._internal(
         backend,
         tracks,
         supportDirectory,
         temporaryDirectory,
         tagReader,
       );

  AudioDownloadService._internal(
    this._backend,
    this._tracks,
    this._supportDirectory,
    this._temporaryDirectory,
    this._tagReader,
  );

  final AudioDownloadBackend _backend;
  final TrackRepository _tracks;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final TagReader _tagReader;
  bool _busy = false;
  bool _cancelRequested = false;

  Future<DownloadAvailability> checkAvailability() =>
      _backend.checkAvailability();
  Future<SourcePreview> analyzeUrl(String url) => _backend.analyzeUrl(url);

  Future<AudioImportResult> download(
    String url, {
    void Function(DownloadEvent event)? onProgress,
  }) async {
    if (_busy) throw StateError('Ya hay una descarga activa.');
    _busy = true;
    _cancelRequested = false;
    Directory? jobDirectory;
    File? movedFile;
    try {
      onProgress?.call(const DownloadEvent(status: DownloadStatus.analyzing));
      final preview = await _backend.analyzeUrl(url);
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(preview.id)) {
        throw const FormatException('El video no tiene un ID seguro.');
      }
      if (preview.type == SourceType.playlist &&
          Uri.parse(url).path == '/playlist') {
        throw const FormatException('Las playlists aún no están disponibles.');
      }
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }

      final support = await _supportDirectory();
      final destinationDirectory = Directory(
        path.join(support.path, 'downloaded_audio'),
      );
      final destination = File(
        path.join(destinationDirectory.path, '${preview.id}.mp3'),
      );
      final uri = destination.uri.toString();
      final existing = await _findByUris({uri, destination.path});
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      if (existing.isNotEmpty && await _validFile(destination)) {
        return AudioImportResult(
          AudioImportStatus.duplicate,
          track: existing.first,
        );
      }
      if (await destination.exists()) {
        throw StateError(
          'Ya existe un archivo para este video; no se sobrescribió.',
        );
      }

      final temporary = await _temporaryDirectory();
      await temporary.create(recursive: true);
      jobDirectory = await temporary.createTemp('astra-import-');
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      DownloadedAudio? downloaded;
      await for (final event in _backend.downloadAudio(
        DownloadRequest(url: url, temporaryDirectory: jobDirectory.path),
      )) {
        onProgress?.call(event);
        if (event.status == DownloadStatus.completed) downloaded = event.audio;
        if (event.status == DownloadStatus.failed) {
          throw StateError(event.error ?? 'No se pudo descargar el audio.');
        }
        if (event.status == DownloadStatus.canceled) {
          return const AudioImportResult(AudioImportStatus.canceled);
        }
      }
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      if (downloaded == null || downloaded.id != preview.id) {
        throw StateError('La descarga no produjo el video esperado.');
      }
      final source = File(downloaded.temporaryPath);
      final jobPath = await jobDirectory.resolveSymbolicLinks();
      final sourcePath = await source.resolveSymbolicLinks();
      if (!path.isWithin(jobPath, sourcePath) ||
          path.extension(sourcePath).toLowerCase() != '.mp3' ||
          !await _validFile(source)) {
        throw StateError('El archivo temporal no es válido.');
      }
      await destinationDirectory.create(recursive: true);
      // Se vuelve a comprobar la colisión justo antes de mover.
      if (await destination.exists()) {
        throw StateError(
          'Ya existe un archivo para este video; no se sobrescribió.',
        );
      }
      movedFile = await _moveFile(source, destination, destinationDirectory);
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      onProgress?.call(const DownloadEvent(status: DownloadStatus.registering));
      final tags = _tagReader.read(movedFile);
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      final stat = await movedFile.stat();
      if (stat.size <= 0) throw StateError('El archivo descargado está vacío.');
      final now = DateTime.now();
      final track = Track(
        uri: uri,
        title: _tagOrFallback(
          tags.title == preview.id ? null : tags.title,
          preview.title,
          preview.id,
        )!,
        artist: _tagOrFallback(tags.artist, preview.author, null),
        album: tags.album,
        genre: tags.genre,
        folderPath: destinationDirectory.path,
        duration: tags.durationMs == null
            ? preview.duration
            : Duration(milliseconds: tags.durationMs!),
        trackNumber: tags.trackNumber,
        year: tags.year,
        fileSize: stat.size,
        dateAdded: now,
        dateModified: stat.modified,
      );
      // Una segunda consulta protege los metadatos de una fila creada en paralelo.
      final concurrent = await _findByUris({uri, destination.path});
      if (concurrent.isNotEmpty) {
        movedFile = null;
        return AudioImportResult(
          AudioImportStatus.duplicate,
          track: concurrent.first,
        );
      }
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      await _tracks.upsertAll([track]);
      movedFile = null;
      return AudioImportResult(AudioImportStatus.downloaded, track: track);
    } finally {
      if (movedFile != null && await movedFile.exists()) {
        await movedFile.delete();
      }
      if (jobDirectory != null && await jobDirectory.exists()) {
        await jobDirectory.delete(recursive: true);
      }
      _busy = false;
      _cancelRequested = false;
    }
  }

  Future<void> cancel() async {
    if (!_busy) return;
    _cancelRequested = true;
    await _backend.cancel();
  }

  Future<List<Track>> _findByUris(Set<String> uris) async {
    if (_tracks is SyncTrackRepository) {
      return _tracks.findByUris(uris);
    }
    return (await _tracks.watchAll().first)
        .where((track) => uris.contains(track.uri))
        .toList();
  }

  Future<bool> _validFile(File file) async =>
      await file.exists() && await file.length() > 0;

  Future<File> _moveFile(
    File source,
    File destination,
    Directory directory,
  ) async {
    try {
      return await source.rename(destination.path);
    } on FileSystemException {
      // /tmp y el soporte de la app pueden residir en sistemas de archivos distintos.
      final staging = await directory.createTemp('.astra-stage-');
      try {
        final copy = await source.copy(
          path.join(staging.path, path.basename(destination.path)),
        );
        if (await destination.exists()) {
          throw StateError(
            'Ya existe un archivo para este video; no se sobrescribió.',
          );
        }
        return await copy.rename(destination.path);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    }
  }
}

String? _tagOrFallback(String? tag, String? fallback, String? lastResort) {
  final value = tag?.trim();
  if (value != null && value.isNotEmpty) return value;
  final backup = fallback?.trim();
  if (backup != null && backup.isNotEmpty) return backup;
  return lastResort;
}
