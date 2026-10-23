import 'dart:async';

import 'package:astramusic/features/player/data/serial_command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ejecuta comandos de audio en el orden en que llegan', () async {
    final queue = SerialCommandQueue();
    final firstGate = Completer<void>();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('primero-inicio');
      await firstGate.future;
      events.add('primero-fin');
    });
    final second = queue.run(() async {
      events.add('segundo');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['primero-inicio']);

    firstGate.complete();
    await Future.wait([first, second]);
    expect(events, ['primero-inicio', 'primero-fin', 'segundo']);
  });

  test('un comando fallido no bloquea los siguientes', () async {
    final queue = SerialCommandQueue();

    final failed = queue.run<void>(() async => throw StateError('falló'));
    final next = queue.run(() async => 42);

    await expectLater(failed, throwsStateError);
    await expectLater(next, completion(42));
  });
}
