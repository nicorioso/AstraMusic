import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:path/path.dart' as path;

abstract class DownloadProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill();
}

abstract class DownloadProcessRunner {
  Future<DownloadProcess> start(String executable, List<String> arguments);
}

class LocalDownloadProcessRunner implements DownloadProcessRunner {
  const LocalDownloadProcessRunner();

  @override
  Future<DownloadProcess> start(
    String executable,
    List<String> arguments,
  ) async => _LocalDownloadProcess(
    await Process.start(executable, arguments, runInShell: false),
  );
}

class _LocalDownloadProcess implements DownloadProcess {
  const _LocalDownloadProcess(this.process);
  final Process process;
  @override
  Stream<List<int>> get stdout => process.stdout;
  @override
  Stream<List<int>> get stderr => process.stderr;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  bool kill() => process.kill();
}

/// La carpeta devuelta pertenece al llamador
/// después del evento [DownloadStatus.completed].
class DesktopYtDlpBackend implements AudioDownloadBackend {
  DesktopYtDlpBackend({
    DownloadProcessRunner? runner,
    this.ytDlpExecutable = 'yt-dlp',
    this.ffmpegExecutable = 'ffmpeg',
    this.maxPlaylistEntries = 150,
  }) : _runner = runner ?? const LocalDownloadProcessRunner();

  final DownloadProcessRunner _runner;
  final String ytDlpExecutable;
  final String ffmpegExecutable;
  final int maxPlaylistEntries;
  final _activeJobs = <Completer<void>>{};
  final _downloadProcesses = <DownloadProcess>{};
  bool _canceled = false;

  @override
  Future<DownloadAvailability> checkAvailability() async {
    if (_activeJobs.isEmpty) _canceled = false;
    try {
      final yt = await _version(ytDlpExecutable, ['--version']);
      final ffmpeg = await _version(ffmpegExecutable, ['-version']);
      return DownloadAvailability(
        available: true,
        ytDlpVersion: yt,
        ffmpegVersion: ffmpeg,
      );
    } on ProcessException {
      return const DownloadAvailability(
        available: false,
        error: 'No se encontraron yt-dlp o FFmpeg en el sistema.',
      );
    } catch (error) {
      return DownloadAvailability(
        available: false,
        error: friendlyDownloadError('$error'),
      );
    }
  }

  Future<String> _version(String executable, List<String> args) async {
    final process = await _runner.start(executable, args);
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final code = await process.exitCode;
    final output = await stdoutFuture;
    final diagnostic = await stderrFuture;
    if (_canceled) throw const _Canceled();
    if (code != 0 || output.trim().isEmpty) {
      throw StateError('$executable: $diagnostic');
    }
    return output.trim().split('\n').first;
  }

  @override
  Future<SourcePreview> analyzeUrl(String url) async {
    if (_activeJobs.isEmpty) _canceled = false;
    final parsed = YoutubeUrl.parse(url);
    if (parsed == null) {
      throw const FormatException('Ingresa una URL válida de YouTube.');
    }
    final args = <String>[
      '--ignore-config',
      '--no-playlist',
      '--skip-download',
      '--dump-single-json',
      '--',
      url.trim(),
    ];
    final process = await _runner.start(ytDlpExecutable, args);
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final code = await process.exitCode;
    final output = await stdoutFuture;
    final diagnostic = await stderrFuture;
    if (_canceled) throw const _Canceled();
    if (code != 0) throw StateError(friendlyDownloadError(diagnostic));
    final json = jsonDecode(output) as Map<String, dynamic>;
    final id = json['id'] as String?;
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('El video no tiene un ID válido.');
    }
    final seconds = (json['duration'] as num?)?.round();
    return SourcePreview(
      id: id,
      title: (json['title'] as String?) ?? id,
      author:
          (json['uploader'] as String?) ?? (json['channel'] as String?) ?? '',
      type: parsed.isPlaylist ? SourceType.playlist : SourceType.video,
      duration: seconds == null ? null : Duration(seconds: seconds),
      thumbnailUrl: json['thumbnail'] as String?,
    );
  }

  @override
  Future<PlaylistPreview> analyzePlaylist(String url) async {
    if (_activeJobs.isEmpty) _canceled = false;
    final parsed = YoutubeUrl.parse(url);
    if (parsed == null || !parsed.isPlaylist) {
      throw const FormatException('Ingresa una URL de playlist de YouTube.');
    }
    if (maxPlaylistEntries < 1 || maxPlaylistEntries > 500) {
      throw RangeError('El límite de playlist debe estar entre 1 y 500.');
    }
    final process = await _runner.start(ytDlpExecutable, [
      '--ignore-config',
      '--yes-playlist',
      '--flat-playlist',
      '--skip-download',
      '--dump-single-json',
      '--playlist-end',
      '${maxPlaylistEntries + 1}',
      '--',
      url.trim(),
    ]);
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final code = await process.exitCode;
    final output = await stdoutFuture;
    final diagnostic = await stderrFuture;
    if (_canceled) throw const _Canceled();
    if (code != 0) throw StateError(friendlyDownloadError(diagnostic));
    return parsePlaylistJson(output, maxEntries: maxPlaylistEntries);
  }

  static PlaylistPreview parsePlaylistJson(
    String output, {
    int maxEntries = 150,
  }) {
    final json = jsonDecode(output) as Map<String, dynamic>;
    if (json['_type'] != 'playlist' || json['entries'] is! List) {
      throw const FormatException('La URL no contiene una playlist válida.');
    }
    final rawEntries = json['entries'] as List;
    final entries = <PlaylistEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      final title = raw['title'] as String?;
      final availability = (raw['availability'] as String?)?.toLowerCase();
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
          title == null ||
          title.trim().isEmpty ||
          title.toLowerCase().contains('private video') ||
          title.toLowerCase().contains('deleted video') ||
          {
            'private',
            'needs_auth',
            'subscriber_only',
            'premium_only',
          }.contains(availability)) {
        continue;
      }
      final seconds = (raw['duration'] as num?)?.round();
      entries.add(
        PlaylistEntry(
          id: id,
          title: title,
          duration: seconds == null ? null : Duration(seconds: seconds),
        ),
      );
      if (entries.length == maxEntries) break;
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('La playlist no tiene ID.');
    }
    return PlaylistPreview(
      id: id,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : id,
      author:
          (json['uploader'] as String?) ?? (json['channel'] as String?) ?? '',
      thumbnailUrl: json['thumbnail'] as String?,
      entries: entries,
      truncated: rawEntries.length > maxEntries,
    );
  }

  /// Formato propio basado en --progress-template de yt-dlp.
  static DownloadEvent? parseProgress(String line) {
    if (!line.startsWith('ASTRA_PROGRESS:')) return null;
    final fields = line.substring('ASTRA_PROGRESS:'.length).split(':');
    if (fields.length != 3) return null;
    final bytes = int.tryParse(fields[0]);
    final total = int.tryParse(fields[1]) ?? int.tryParse(fields[2]);
    return DownloadEvent(
      status: DownloadStatus.downloading,
      downloadedBytes: bytes,
      totalBytes: total,
    );
  }

  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) async* {
    final job = Completer<void>();
    _activeJobs.add(job);
    if (_activeJobs.length == 1) _canceled = false;
    Directory? workDir;
    var completed = false;
    try {
      if (YoutubeUrl.parse(request.url) == null) {
        throw const FormatException('Ingresa una URL válida de YouTube.');
      }
      yield const DownloadEvent(status: DownloadStatus.analyzing);
      final availability = await checkAvailability();
      if (!availability.available) {
        throw StateError(availability.error ?? 'Faltan yt-dlp o FFmpeg.');
      }
      final preview = await analyzeUrl(request.url);
      if (preview.type == SourceType.playlist &&
          Uri.parse(request.url).path == '/playlist') {
        throw const FormatException(
          'La descarga de playlists aún no está disponible.',
        );
      }
      if (_canceled) throw const _Canceled();
      final parent = Directory(request.temporaryDirectory);
      await parent.create(recursive: true);
      if (_canceled) throw const _Canceled();
      workDir = await parent.createTemp('astra-download-');
      if (_canceled) throw const _Canceled();
      final output = path.join(workDir.path, '${preview.id}.%(ext)s');
      final ffmpegArgs = ffmpegExecutable == 'ffmpeg'
          ? <String>[]
          : <String>['--ffmpeg-location', ffmpegExecutable];
      final process = await _runner.start(ytDlpExecutable, [
        '--ignore-config',
        '--no-playlist',
        '--no-overwrites',
        '--no-continue',
        '-f',
        'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio',
        '--concurrent-fragments',
        '4',
        '--buffer-size',
        '16K',
        '--write-thumbnail',
        '--embed-thumbnail',
        ...ffmpegArgs,
        '--newline',
        '--progress',
        '--progress-template',
        'download:ASTRA_PROGRESS:%(progress.downloaded_bytes)s:%(progress.total_bytes)s:%(progress.total_bytes_estimate)s',
        '--print',
        'after_move:ASTRA_FILE:%(filepath)s',
        '-o',
        output,
        '--',
        request.url.trim(),
      ]);
      _downloadProcesses.add(process);
      if (_canceled) process.kill();
      final events = StreamController<DownloadEvent>();
      String? finalPath;
      final stderr = StringBuffer();
      final outDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('ASTRA_FILE:')) {
              finalPath = line.substring('ASTRA_FILE:'.length).trim();
              events.add(
                const DownloadEvent(status: DownloadStatus.processing),
              );
            } else {
              final progress = parseProgress(line);
              if (progress != null) events.add(progress);
            }
          })
          .asFuture<void>();
      final errDone = process.stderr.transform(utf8.decoder).listen((chunk) {
        if (stderr.length < 8192) {
          stderr.write(
            chunk.substring(0, (8192 - stderr.length).clamp(0, chunk.length)),
          );
        }
      }).asFuture<void>();
      final exit = process.exitCode;
      unawaited(
        Future.wait([outDone, errDone, exit]).then(
          (_) => events.close(),
          onError: (Object error, StackTrace stack) => events.close(),
        ),
      );
      yield* events.stream;
      final code = await exit;
      _downloadProcesses.remove(process);
      if (_canceled) throw const _Canceled();
      if (code != 0) throw StateError(friendlyDownloadError(stderr.toString()));
      if (finalPath == null ||
          path.normalize(path.dirname(finalPath!)) !=
              path.normalize(workDir.path) ||
          path.basenameWithoutExtension(finalPath!) != preview.id ||
          !{
            '.m4a',
            '.mp3',
            '.opus',
            '.webm',
            '.ogg',
            '.aac',
            '.flac',
            '.wav',
          }.contains(path.extension(finalPath!).toLowerCase())) {
        throw StateError('yt-dlp no informó un archivo final válido.');
      }
      final file = File(finalPath!);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('El archivo descargado está vacío o no existe.');
      }
      String? thumbnailPath;
      for (final ext in ['webp', 'jpg', 'jpeg', 'png']) {
        final thumbnail = File(path.join(workDir.path, '${preview.id}.$ext'));
        if (await thumbnail.exists() && await thumbnail.length() > 0) {
          thumbnailPath = thumbnail.path;
          break;
        }
      }
      completed = true;
      yield DownloadEvent(
        status: DownloadStatus.completed,
        audio: DownloadedAudio(
          id: preview.id,
          temporaryPath: file.path,
          title: preview.title,
          author: preview.author,
          duration: preview.duration,
          thumbnailUrl: preview.thumbnailUrl,
          thumbnailPath: thumbnailPath,
        ),
      );
    } on _Canceled {
      yield const DownloadEvent(status: DownloadStatus.canceled);
    } catch (error) {
      if (_canceled) {
        yield const DownloadEvent(status: DownloadStatus.canceled);
      } else {
        yield DownloadEvent(
          status: DownloadStatus.failed,
          error: friendlyDownloadError('$error'),
        );
      }
    } finally {
      if (!completed && workDir != null && await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
      _activeJobs.remove(job);
      job.complete();
    }
  }

  @override
  Future<void> cancel() async {
    _canceled = true;
    for (final process in _downloadProcesses.toList()) {
      process.kill();
    }
    await Future.wait(_activeJobs.map((job) => job.future).toList());
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
