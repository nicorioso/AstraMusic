
import 'package:astramusic/core/platform/android_yt_dlp_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/yt_dlp');
  const events = EventChannel('test/yt_dlp/events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'checkAvailability') return {'available': true};
      if (call.method == 'analyzeUrl') return {'json': '{"id":"abc","title":"Canción","uploader":"Autor"}'};
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test('disponibilidad y análisis', () async {
    final backend = AndroidYtDlpBackend(methods: methods, events: events);
    expect((await backend.checkAvailability()).available, isTrue);
    expect((await backend.analyzeUrl('https://youtu.be/abc')).title, 'Canción');
  });

  test('error de red en análisis', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      throw PlatformException(code: 'network', message: 'Sin conexión');
    });
    final backend = AndroidYtDlpBackend(methods: methods, events: events);
    expect((await backend.checkAvailability()).error, 'Sin conexión');
    await expectLater(backend.analyzeUrl('https://youtu.be/abc'), throwsA(isA<PlatformException>()));
  });

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
