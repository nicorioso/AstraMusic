import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/desktop_yt_dlp_backend.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class FakeProcess implements DownloadProcess {
  FakeProcess({required this.out, this.err = '', this.code = 0, this.onKill});
  final String out;
  final String err;
  final int code;
  final void Function()? onKill;
  final Completer<int> _exit = Completer<int>();
  bool killed = false;
  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(out));
  @override
  Stream<List<int>> get stderr => Stream.value(utf8.encode(err));
  @override
  Future<int> get exitCode => _exit.future;
  void finish() {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  bool kill() {
    killed = true;
    onKill?.call();
    finish();
    return true;
  }
}

class FakeRunner implements DownloadProcessRunner {
  FakeRunner(this.startProcess);
  final FutureOr<FakeProcess> Function(String, List<String>) startProcess;
  final calls = <List<String>>[];
  @override
  Future<DownloadProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    calls.add([executable, ...arguments]);
    final process = await startProcess(executable, arguments);
    return process;
  }
}

FakeProcess instant(String out, {String err = '', int code = 0}) {
  final process = FakeProcess(out: out, err: err, code: code);
  scheduleMicrotask(process.finish);
  return process;
}

void main() {
  test('el resultado por lote protege sus colecciones', () {
    final successes = <DownloadedAudio>[];
    final errors = <String, String>{};
    final result = DownloadBatchResult(
      successes: successes,
      errors: errors,
      canceled: false,
    );
    successes.add(
      const DownloadedAudio(id: 'a', temporaryPath: '/tmp/a', title: 'a'),
    );
    errors['a'] = 'error';
    expect(result.successes, isEmpty);
    expect(result.errors, isEmpty);
    expect(() => result.errors['b'] = 'error', throwsUnsupportedError);
  });

  test('valida hosts, esquema y query list sin aceptar imitaciones', () {
    expect(
      YoutubeUrl.parse('https://www.youtube.com/watch?v=abc')?.isPlaylist,
      false,
    );
    expect(
      YoutubeUrl.parse('https://youtu.be/abc?list=PL123')?.isPlaylist,
      true,
    );
    expect(
      YoutubeUrl.parse('https://youtube.com/playlist?list=PL123')?.isPlaylist,
      true,
    );
    for (final url in [
      'https://youtube.com.evil.test/watch?v=abc',
      'ftp://youtube.com/watch?v=abc',
      'https://youtube.com/watch',
      'https://youtube.com/playlist',
      'https://user@youtube.com/watch?v=abc',
    ]) {
      expect(YoutubeUrl.parse(url), isNull);
    }
  });

  test('traduce errores frecuentes y acota diagnósticos', () {
    expect(friendlyDownloadError('Connection timed out'), contains('conexión'));
    expect(
      friendlyDownloadError('Private video'),
      contains('no está disponible'),
    );
    expect(friendlyDownloadError('No space left'), contains('espacio'));
    expect(friendlyDownloadError('x' * 300).length, 180);
  });

  test('interpreta progreso con total real o estimado', () {
    expect(
      DesktopYtDlpBackend.parseProgress('ASTRA_PROGRESS:12:100:NA')?.totalBytes,
      100,
    );
    expect(
      DesktopYtDlpBackend.parseProgress('ASTRA_PROGRESS:12:NA:200')?.totalBytes,
      200,
    );
    expect(DesktopYtDlpBackend.parseProgress('otro'), isNull);
  });

  test('comprueba herramientas y analiza metadatos', () async {
    final runner = FakeRunner((exe, args) {
      if (args.contains('--version')) return instant('2026.01.01\n');
      if (args.contains('-version')) return instant('ffmpeg version 8\n');
      return instant(
        '{"id":"abc_123","title":"Canción","uploader":"Autor","duration":42}',
      );
    });
    final backend = DesktopYtDlpBackend(runner: runner);
    expect((await backend.checkAvailability()).available, true);
    final preview = await backend.analyzeUrl('https://youtu.be/abc_123');
    expect(preview.id, 'abc_123');
    expect(preview.duration, const Duration(seconds: 42));
  });

  test('falla si el motor no existe', () async {
    final backend = DesktopYtDlpBackend(
      runner: FakeRunner(
        (_, _) => throw const ProcessException('yt-dlp', [], 'not found'),
      ),
    );
    expect((await backend.checkAvailability()).available, false);
  });

  test(
    'descarga solo si archivo final es comprobable y limpia al fallar',
    () async {
      final parent = await Directory.systemTemp.createTemp('astra-test-');
      addTearDown(() => parent.delete(recursive: true));
      final runner = FakeRunner((exe, args) async {
        if (args.contains('--version')) return instant('2026.01.01\n');
        if (args.contains('-version')) return instant('ffmpeg version 8\n');
        if (args.contains('--dump-single-json')) {
          return instant('{"id":"abc123","title":"Tema"}');
        }
        final template = args[args.indexOf('-o') + 1];
        final file = File(template.replaceFirst('%(ext)s', 'mp3'));
        await file.writeAsBytes([1, 2, 3]);
        await File(path.join(file.parent.path, 'abc123.jpg'))
            .writeAsBytes([1, 2, 3]);
        return instant('ASTRA_PROGRESS:3:3:NA\nASTRA_FILE:${file.path}\n');
      });
      final backend = DesktopYtDlpBackend(runner: runner);
      final events = await backend
          .downloadAudio(
            DownloadRequest(
              url: 'https://youtu.be/abc123',
              temporaryDirectory: parent.path,
            ),
          )
          .toList();
      expect(
        events.map((e) => e.status),
        containsAllInOrder([
          DownloadStatus.analyzing,
          DownloadStatus.downloading,
          DownloadStatus.processing,
          DownloadStatus.completed,
        ]),
      );
      expect(await File(events.last.audio!.temporaryPath).length(), 3);
      expect(runner.calls.last, contains('--no-overwrites'));
      expect(runner.calls.last, contains('--write-thumbnail'));
      expect(runner.calls.last, contains('--embed-thumbnail'));
      final conversion = runner.calls.last.indexOf('--convert-thumbnails');
      expect(runner.calls.last[conversion + 1], 'jpg');
      expect(path.basename(events.last.audio!.temporaryPath), 'abc123.mp3');
      expect(path.basename(events.last.audio!.thumbnailPath!), 'abc123.jpg');
    },
  );

  test('rechaza archivo vacío y elimina carpeta de trabajo', () async {
    final parent = await Directory.systemTemp.createTemp('astra-test-');
    addTearDown(() => parent.delete(recursive: true));
    final runner = FakeRunner((exe, args) async {
      if (args.contains('--version')) return instant('v\n');
      if (args.contains('-version')) return instant('ffmpeg\n');
      if (args.contains('--dump-single-json')) {
        return instant('{"id":"abc123","title":"Tema"}');
      }
      final file = File(
        args[args.indexOf('-o') + 1].replaceFirst('%(ext)s', 'mp3'),
      );
      await file.create();
      return instant('ASTRA_FILE:${file.path}\n');
    });
    final events = await DesktopYtDlpBackend(runner: runner)
        .downloadAudio(
          DownloadRequest(
            url: 'https://youtu.be/abc123',
            temporaryDirectory: parent.path,
          ),
        )
        .toList();
    expect(events.last.status, DownloadStatus.failed);
    expect(await parent.list().toList(), isEmpty);
  });

  test('reporta fallo de yt-dlp y limpia el trabajo', () async {
    final parent = await Directory.systemTemp.createTemp('astra-test-');
    addTearDown(() => parent.delete(recursive: true));
    final runner = FakeRunner((exe, args) {
      if (args.contains('--version')) return instant('v\n');
      if (args.contains('-version')) return instant('ffmpeg\n');
      if (args.contains('--dump-single-json')) {
        return instant('{"id":"abc123","title":"Tema"}');
      }
      return instant('', err: 'Private video', code: 1);
    });
    final events = await DesktopYtDlpBackend(runner: runner)
        .downloadAudio(
          DownloadRequest(
            url: 'https://youtu.be/abc123',
            temporaryDirectory: parent.path,
          ),
        )
        .toList();
    expect(events.last.status, DownloadStatus.failed);
    expect(events.last.error, contains('no está disponible'));
    expect(await parent.list().toList(), isEmpty);
  });

  test('cancelar mata proceso y limpia carpeta', () async {
    final parent = await Directory.systemTemp.createTemp('astra-test-');
    addTearDown(() => parent.delete(recursive: true));
    final started = Completer<FakeProcess>();
    final runner = FakeRunner((exe, args) async {
      if (args.contains('--version')) return instant('v\n');
      if (args.contains('-version')) return instant('ffmpeg\n');
      if (args.contains('--dump-single-json')) {
        return instant('{"id":"abc123","title":"Tema"}');
      }
      final file = File(
        args[args.indexOf('-o') + 1].replaceFirst('%(ext)s', 'mp3'),
      );
      await file.writeAsBytes([1]);
      final process = FakeProcess(out: 'ASTRA_PROGRESS:1:2:NA\n');
      started.complete(process);
      return process;
    });
    final backend = DesktopYtDlpBackend(runner: runner);
    final eventsFuture = backend
        .downloadAudio(
          DownloadRequest(
            url: 'https://youtu.be/abc123',
            temporaryDirectory: parent.path,
          ),
        )
        .toList();
    final process = await started.future;
    await backend.cancel();
    final events = await eventsFuture;
    expect(process.killed, true);
    expect(events.last.status, DownloadStatus.canceled);
    expect(await parent.list().toList(), isEmpty);
  });
}
