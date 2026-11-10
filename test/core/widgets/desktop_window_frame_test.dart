import 'package:astramusic/core/platform/desktop_window.dart';
import 'package:astramusic/core/widgets/desktop_window_frame.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var maximized = false;

  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('configura el marco y ejecuta los controles de la barra real', (
    tester,
  ) async {
    const window = SystemDesktopWindowController();
    await window.initialize();
    expect(calls, ['ensureInitialized', 'setAsFrameless']);
    calls.clear();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAstraTheme(),
        home: const DesktopWindowFrame(
          window: window,
          child: Scaffold(body: Text('Contenido')),
        ),
      ),
    );

    expect(find.text('AstraMusic'), findsOneWidget);
    expect(find.text('Contenido'), findsOneWidget);

    await tester.tap(find.byKey(const Key('window-minimize')));
    await tester.pump();
    expect(calls, contains('minimize'));

    await tester.tap(find.byKey(const Key('window-maximize')));
    await tester.pump();
    expect(maximized, isTrue);
    await tester.tap(find.byKey(const Key('window-maximize')));
    await tester.pump();
    expect(maximized, isFalse);

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('desktop-title-drag-area'))),
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    await drag.up();
    expect(calls, contains('startDragging'));

    await tester.tap(find.byKey(const Key('window-close')));
    await tester.pump();
    expect(calls, contains('close'));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
