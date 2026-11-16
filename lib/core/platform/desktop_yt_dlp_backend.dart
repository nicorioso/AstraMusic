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

/// Un trabajo activo por adaptador. La carpeta devuelta pertenece al llamador
/// después del evento [DownloadStatus.completed].
class DesktopYtDlpBackend implements AudioDownloadBackend {
  DesktopYtDlpBackend({
    DownloadProcessRunner? runner,
    this.ytDlpExecutable = 'yt-dlp',
    this.ffmpegExecutable = 'ffmpeg',
  }) : _runner = runner ?? const LocalDownloadProcessRunner();

  final DownloadProcessRunner _runner;
  final String ytDlpExecutable;
  final String ffmpegExecutable;
  DownloadProcess? _activeProcess;
  Completer<void>? _activeJob;
  bool _canceled = false;

  @override
  Future<DownloadAvailability> checkAvailability() async {
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
    _activeProcess = process;
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final code = await process.exitCode;
    final output = await stdoutFuture;
    final diagnostic = await stderrFuture;
    _activeProcess = null;
    if (_canceled) throw const _Canceled();
    if (code != 0 || output.trim().isEmpty) {
      throw StateError('$executable: $diagnostic');
    }
    return output.trim().split('\n').first;
  }

  @override
  Future<SourcePreview> analyzeUrl(String url) async {
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
    _activeProcess = process;
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final code = await process.exitCode;
    final output = await stdoutFuture;
    final diagnostic = await stderrFuture;
    _activeProcess = null;
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
    if (_activeJob != null) {
      yield const DownloadEvent(
        status: DownloadStatus.failed,
        error: 'Ya hay una descarga activa.',
      );
      return;
    }
    final job = Completer<void>();
    _activeJob = job;
    _canceled = false;
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
        '--extract-audio',
        '--audio-format',
        request.format.name,
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
      _activeProcess = process;
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
      _activeProcess = null;
      if (_canceled) throw const _Canceled();
      if (code != 0) throw StateError(friendlyDownloadError(stderr.toString()));
      if (finalPath == null ||
          path.normalize(path.dirname(finalPath!)) !=
              path.normalize(workDir.path) ||
          path.basename(finalPath!) != '${preview.id}.${request.format.name}') {
        throw StateError('yt-dlp no informó un archivo final válido.');
      }
      final file = File(finalPath!);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('El archivo descargado está vacío o no existe.');
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
      _activeProcess = null;
      if (!completed && workDir != null && await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
      _activeJob = null;
      job.complete();
    }
  }

  @override
  Future<void> cancel() async {
    final job = _activeJob;
    if (job == null) return;
    _canceled = true;
    _activeProcess?.kill();
    await job.future;
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
