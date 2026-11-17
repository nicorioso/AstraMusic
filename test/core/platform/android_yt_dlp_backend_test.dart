import 'package:astramusic/core/platform/android_yt_dlp_backend.dart';
import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Events extends EventChannel {
  const _Events(this.value) : super('test/fake-events');
  final Map<String, Object?> value;
  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) =>
      Stream.value(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/yt_dlp');
  const events = EventChannel('test/yt_dlp/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'checkAvailability') return {'available': true};
      if (call.method == 'updateEngine') return {'version': '2026.11.17'};
      if (call.method == 'analyzeUrl') {
        return {'json': '{"id":"abc","title":"Canción","uploader":"Autor"}'};
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test('disponibilidad y análisis', () async {
    final backend = AndroidYtDlpBackend(methods: methods, events: events);
    expect((await backend.checkAvailability()).available, isTrue);
    expect(await backend.updateEngine(), '2026.11.17');
    expect((await backend.analyzeUrl('https://youtu.be/abc')).title, 'Canción');
  });

  test('error de red en análisis', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      throw PlatformException(code: 'network', message: 'Sin conexión');
    });
    final backend = AndroidYtDlpBackend(methods: methods, events: events);
    expect((await backend.checkAvailability()).error, 'Sin conexión');
    await expectLater(
      backend.analyzeUrl('https://youtu.be/abc'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('conserva el diagnóstico nativo al actualizar y analizar', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      throw PlatformException(
        code: 'download_error',
        message: 'YoutubeDLException: st; causa: IOException: no se pudo extraer libpython.zip.so',
      );
    });
    final backend = AndroidYtDlpBackend(methods: methods, events: events);
    for (final operation in [
      backend.updateEngine,
      () => backend.analyzeUrl('https://youtu.be/abc'),
    ]) {
      await expectLater(
        operation(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.message,
            'mensaje',
            contains('IOException: no se pudo extraer libpython.zip.so'),
          ),
        ),
      );
    }
  });

  test('conserva el diagnóstico nativo en eventos de descarga', () async {
    final backend = AndroidYtDlpBackend(
      methods: methods,
      events: const _Events({
        'status': 'failed',
        'error': 'YoutubeDLException: st; causa: IOException: falta libffmpeg.zip.so',
      }),
    );
    final event = await backend
        .downloadAudio(
          const DownloadRequest(
            url: 'https://youtu.be/abc',
            temporaryDirectory: '/cache/job',
          ),
        )
        .last;
    expect(event.status, DownloadStatus.failed);
    expect(event.error, contains('IOException: falta libffmpeg.zip.so'));
  });

  test('envía el directorio temporal al canal nativo', () async {
    Map<Object?, Object?>? arguments;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'analyzeUrl') {
        return {'json': '{"id":"abc","title":"Canción","uploader":"Autor"}'};
      }
      if (call.method == 'downloadAudio') {
        arguments = Map<Object?, Object?>.from(call.arguments as Map);
      }
      return null;
    });
    final backend = AndroidYtDlpBackend(
      methods: methods,
      events: const _Events({
        'status': 'completed',
        'path': '/cache/job/abc.m4a',
      }),
    );
    await backend
        .downloadAudio(
          const DownloadRequest(
            url: 'https://youtu.be/abc',
            temporaryDirectory: '/cache/job',
          ),
        )
        .last;
    expect(arguments?['temporaryDirectory'], '/cache/job');
  });

  for (final extension in ['m4a', 'mp3', 'opus', 'webm']) {
    test('mapea audio .$extension y carátula auxiliar', () async {
      final backend = AndroidYtDlpBackend(
        methods: methods,
        events: _Events({
          'status': 'completed',
          'path': '/cache/job/abc.$extension',
          'thumbnailPath': '/cache/job/abc.webp',
        }),
      );
      final result = await backend
          .downloadAudio(
            const DownloadRequest(
              url: 'https://youtu.be/abc',
              temporaryDirectory: '/cache/job',
            ),
          )
          .last;
      expect(result.audio?.temporaryPath, '/cache/job/abc.$extension');
      expect(result.audio?.thumbnailPath, '/cache/job/abc.webp');
    });
  }

  test('cancelación invoca el canal nativo', () async {
    var called = false;
    messenger.setMockMethodCallHandler(methods, (call) async {
      called = call.method == 'cancel';
      return null;
    });
    await AndroidYtDlpBackend(methods: methods, events: events).cancel();
    expect(called, isTrue);
  });
}
