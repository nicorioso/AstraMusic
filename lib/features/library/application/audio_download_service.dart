import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dart:typed_data';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

enum AudioImportStatus { downloaded, duplicate, canceled }

class AudioImportResult {
  const AudioImportResult(this.status, {this.track});
  final AudioImportStatus status;
  final Track? track;
}

class BatchProgress {
  const BatchProgress({
    required this.index,
    required this.total,
    required this.title,
    required this.event,
  });
  final int index;
  final int total;
  final String title;
  final DownloadEvent event;
}

/// Registra una sola pista por operación; conserva archivos y filas previas.
class AudioDownloadService {
  static const _audioExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.opus',
    '.ogg',
    '.webm',
    '.wav',
    '.flac',
  };
  AudioDownloadService({
    required AudioDownloadBackend backend,
    required TrackRepository tracks,
    PlaylistRepository? playlists,
    required Future<Directory> Function() supportDirectory,
    required Future<Directory> Function() temporaryDirectory,
    TagReader tagReader = const AudioMetadataTagReader(),
    Future<List<int>?> Function(Uri)? fetchThumbnail,
  }) : this._internal(
         backend,
         tracks,
         playlists,
         supportDirectory,
         temporaryDirectory,
         tagReader,
         fetchThumbnail ?? _fetchThumbnail,
       );

  AudioDownloadService._internal(
    this._backend,
    this._tracks,
    this._playlists,
    this._supportDirectory,
    this._temporaryDirectory,
    this._tagReader,
    this._fetchThumbnailBytes,
  );

  final AudioDownloadBackend _backend;
  final TrackRepository _tracks;
  final PlaylistRepository? _playlists;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final TagReader _tagReader;
  final Future<List<int>?> Function(Uri) _fetchThumbnailBytes;
  bool _busy = false;
  bool _cancelRequested = false;
  String? _analyzedUrl;
  SourcePreview? _analyzedPreview;

  Future<DownloadAvailability> checkAvailability() =>
      _backend.checkAvailability();
  Future<SourcePreview> analyzeUrl(String url) async {
    final preview = await _backend.analyzeUrl(url);
    _analyzedUrl = url;
    _analyzedPreview = preview;
    return preview;
  }

  Future<PlaylistPreview> analyzePlaylist(String url) =>
      _backend.analyzePlaylist(url);

  Future<DownloadBatchResult> downloadPlaylist(
    PlaylistPreview playlist, {
    void Function(BatchProgress progress)? onProgress,
  }) async {
    if (_busy) throw StateError('Ya hay una descarga activa.');
    if (_playlists == null) {
      throw StateError('No hay repositorio de playlists.');
    }
    _busy = true;
    _cancelRequested = false;
    final successes = <DownloadBatchItem>[];
    final errors = <String, String>{};
    int? playlistId;
    try {
      final results = List<DownloadBatchItem?>.filled(
        playlist.entries.length,
        null,
      );
      var next = 0;
      Future<void> worker() async {
        while (!_cancelRequested && next < playlist.entries.length) {
          final i = next++;
          final entry = playlist.entries[i];
          try {
            final result = await _downloadOne(
              entry.url,
              withinBatch: true,
              onProgress: (event) => onProgress?.call(
                BatchProgress(
                  index: i + 1,
                  total: playlist.entries.length,
                  title: entry.title,
                  event: event,
                ),
              ),
            );
            if (result.status == AudioImportStatus.canceled) continue;
            final track = result.track;
            if (track == null || track.id == null) {
              throw StateError(
                'La pista no quedó registrada en la biblioteca.',
              );
            }
            results[i] = DownloadBatchItem(
              sourceId: entry.id,
              title: entry.title,
              trackId: track.id!,
              alreadyPresent: result.status == AudioImportStatus.duplicate,
            );
          } catch (error) {
            if (!_cancelRequested) {
              errors[entry.id] = friendlyDownloadError('$error');
            }
          }
        }
      }

      await Future.wait(
        List.generate(Platform.isAndroid ? 1 : 2, (_) => worker()),
      );
      successes.addAll(results.whereType<DownloadBatchItem>());
      if (successes.isNotEmpty) {
        final created = await _playlists.create(playlist.title);
        try {
          await _playlists.addTracks(
            created.id,
            successes.map((item) => item.trackId).toList(),
          );
          playlistId = created.id;
        } catch (error) {
          await _playlists.delete(created.id);
          errors['playlist'] = friendlyDownloadError('$error');
        }
      }
      return DownloadBatchResult(
        successes: successes,
        errors: errors,
        canceled: _cancelRequested,
        playlistId: playlistId,
      );
    } finally {
      _busy = false;
      _cancelRequested = false;
    }
  }

  Future<AudioImportResult> download(
    String url, {
    void Function(DownloadEvent event)? onProgress,
  }) => _downloadOne(url, onProgress: onProgress);

  Future<AudioImportResult> _downloadOne(
    String url, {
    void Function(DownloadEvent event)? onProgress,
    bool withinBatch = false,
  }) async {
    if (_busy && !withinBatch) throw StateError('Ya hay una descarga activa.');
    if (!withinBatch) {
      _busy = true;
      _cancelRequested = false;
    }
    Directory? jobDirectory;
    File? movedFile;
    File? createdArtwork;
    final stopwatch = Stopwatch()..start();
    void timing(String stage, int startedAt) {
      if (Platform.isAndroid) {
        debugPrint(
          'AstraDownload stage=$stage ms=${stopwatch.elapsedMilliseconds - startedAt}',
        );
      }
    }

    try {
      onProgress?.call(const DownloadEvent(status: DownloadStatus.analyzing));
      var stageStarted = stopwatch.elapsedMilliseconds;
      final preview = _analyzedUrl == url && _analyzedPreview != null
          ? _analyzedPreview!
          : await _backend.analyzeUrl(url);
      timing('analyze', stageStarted);
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
      final possibleDestinations = _audioExtensions
          .map(
            (extension) => File(
              path.join(destinationDirectory.path, '${preview.id}$extension'),
            ),
          )
          .toList();
      final existing = await _findByUris({
        for (final file in possibleDestinations) ...{
          file.uri.toString(),
          file.path,
        },
      });
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      for (final track in existing) {
        final file = File.fromUri(Uri.parse(track.uri));
        if (await _validFile(file)) {
          return AudioImportResult(AudioImportStatus.duplicate, track: track);
        }
      }
      if (await Future.wait(possibleDestinations.map((file) => file.exists()))
          .then((values) => values.any((exists) => exists))) {
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
      timing('preflight', stageStarted);
      final thumbnailUrl = Uri.tryParse(preview.thumbnailUrl ?? '');
      final thumbnailFuture =
          Platform.isAndroid &&
              thumbnailUrl != null &&
              thumbnailUrl.scheme == 'https' &&
              _trustedThumbnailHost(thumbnailUrl.host)
          ? _fetchThumbnailBytes(thumbnailUrl).catchError((Object _) => null)
          : Future<List<int>?>.value(null);
      DownloadedAudio? downloaded;
      stageStarted = stopwatch.elapsedMilliseconds;
      await for (final event in _backend.downloadAudio(
        DownloadRequest(
          url: url,
          temporaryDirectory: jobDirectory.path,
          preview: preview,
        ),
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
      timing('native_download', stageStarted);
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      if (downloaded == null || downloaded.id != preview.id) {
        throw StateError('La descarga no produjo el video esperado.');
      }
      final source = File(downloaded.temporaryPath);
      final jobPath = await jobDirectory.resolveSymbolicLinks();
      final sourcePath = await source.resolveSymbolicLinks();
      final extension = path.extension(sourcePath).toLowerCase();
      if (!path.isWithin(jobPath, sourcePath) ||
          !_audioExtensions.contains(extension) ||
          !await _validFile(source)) {
        final files = await jobDirectory.list(recursive: true).toList();
        for (final file in files) {
          final stat = await file.stat();
          debugPrint(
            'AstraMusic descarga temporal: ${file.path} (${stat.size} bytes)',
          );
        }
        throw StateError('El archivo temporal no es válido.');
      }
      final destination = File(
        path.join(destinationDirectory.path, '${preview.id}$extension'),
      );
      final uri = destination.uri.toString();
      await destinationDirectory.create(recursive: true);
      // Se vuelve a comprobar la colisión justo antes de mover.
      if (await destination.exists()) {
        throw StateError(
          'Ya existe un archivo para este video; no se sobrescribió.',
        );
      }
      stageStarted = stopwatch.elapsedMilliseconds;
      movedFile = await _moveFile(source, destination, destinationDirectory);
      timing('move', stageStarted);
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      onProgress?.call(const DownloadEvent(status: DownloadStatus.registering));
      stageStarted = stopwatch.elapsedMilliseconds;
      final tags = _tagReader.read(movedFile);
      timing('tags', stageStarted);
      if (_cancelRequested) {
        return const AudioImportResult(AudioImportStatus.canceled);
      }
      stageStarted = stopwatch.elapsedMilliseconds;
      final artwork = await _persistArtwork(
        preview: preview,
        downloaded: downloaded,
        audio: movedFile,
        jobDirectory: jobDirectory,
        supportDirectory: support,
        prefetchedThumbnail: thumbnailFuture,
      );
      timing('artwork', stageStarted);
      createdArtwork = artwork.$2;
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
        artworkPath: artwork.$1,
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
      stageStarted = stopwatch.elapsedMilliseconds;
      await _tracks.upsertAll([track]);
      movedFile = null;
      createdArtwork = null;
      final registered = await _findByUris({uri});
      timing('drift', stageStarted);
      return AudioImportResult(
        AudioImportStatus.downloaded,
        track: registered.single,
      );
    } finally {
      timing('total', 0);
      if (movedFile != null && await movedFile.exists()) {
        await movedFile.delete();
      }
      if (createdArtwork != null && await createdArtwork.exists()) {
        await createdArtwork.delete();
      }
      if (jobDirectory != null && await jobDirectory.exists()) {
        await jobDirectory.delete(recursive: true);
      }
      if (!withinBatch) {
        _busy = false;
        _cancelRequested = false;
      }
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

  Future<(String?, File?)> _persistArtwork({
    required SourcePreview preview,
    required DownloadedAudio downloaded,
    required File audio,
    required Directory jobDirectory,
    required Directory supportDirectory,
    required Future<List<int>?> prefetchedThumbnail,
  }) async {
    Uint8List? jpg;
    final url = Uri.tryParse(
      downloaded.thumbnailUrl ?? preview.thumbnailUrl ?? '',
    );
    final validUrl =
        url != null && url.scheme == 'https' && _trustedThumbnailHost(url.host);
    Future<Uint8List?> fromUrl() async {
      if (!validUrl) return null;
      try {
        final bytes =
            Platform.isAndroid && url.toString() == preview.thumbnailUrl
            ? await prefetchedThumbnail
            : await _fetchThumbnailBytes(url);
        return bytes == null || bytes.length > _maxThumbnailBytes
            ? null
            : _toJpeg(bytes);
      } catch (_) {
        return null;
      }
    }

    final preferUrl =
        Platform.isAndroid &&
        path.extension(audio.path).toLowerCase() == '.m4a' &&
        validUrl;
    if (preferUrl) jpg = await fromUrl();
    if (jpg == null) {
      if (_tagReader case final ArtworkTagReader reader) {
        try {
          final embedded = reader.readArtwork(audio);
          if (embedded != null) jpg = _toJpeg(embedded);
        } catch (_) {
          // Una miniatura defectuosa en el MP3 no impide usar la auxiliar.
        }
      }
    }
    final thumbnailPath = downloaded.thumbnailPath;
    if (jpg == null && thumbnailPath != null) {
      try {
        final auxiliary = File(thumbnailPath);
        final jobPath = await jobDirectory.resolveSymbolicLinks();
        final imagePath = await auxiliary.resolveSymbolicLinks();
        if (path.isWithin(jobPath, imagePath) &&
            await auxiliary.length() <= _maxThumbnailBytes) {
          jpg = _toJpeg(await auxiliary.readAsBytes());
        }
      } on FileSystemException {
        // Puede faltar la imagen auxiliar tras el posprocesamiento.
      }
    }
    if (jpg == null && !preferUrl) jpg = await fromUrl();
    if (jpg == null) return (null, null);

    final directory = Directory(
      path.join(supportDirectory.path, 'downloaded_artwork'),
    );
    await directory.create(recursive: true);
    var target = File(path.join(directory.path, '${preview.id}.jpg'));
    if (await target.exists()) {
      if (await target.length() > 0) return (target.path, null);
      target = File(
        path.join(
          directory.path,
          '${preview.id}-${DateTime.now().microsecondsSinceEpoch}.jpg',
        ),
      );
    }
    try {
      await target.writeAsBytes(jpg, flush: true);
      return (target.path, target);
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

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

const _maxThumbnailBytes = 5 * 1024 * 1024;

bool _trustedThumbnailHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'ytimg.com' ||
      lower.endsWith('.ytimg.com') ||
      lower == 'img.youtube.com' ||
      lower.endsWith('.googleusercontent.com');
}

Uint8List? _toJpeg(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > _maxThumbnailBytes) return null;
  try {
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = longest <= 640
        ? decoded
        : image.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 640 : null,
            height: decoded.height > decoded.width ? 640 : null,
          );
    return Uint8List.fromList(image.encodeJpg(resized, quality: 82));
  } on Exception {
    return null;
  }
}

Future<List<int>?> _fetchThumbnail(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > _maxThumbnailBytes) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 8))) {
      bytes.add(chunk);
      if (bytes.length > _maxThumbnailBytes) return null;
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}
