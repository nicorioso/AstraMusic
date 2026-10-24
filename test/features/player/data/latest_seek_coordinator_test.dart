import 'dart:async';

import 'package:astramusic/features/player/data/latest_seek_coordinator.dart';
import 'package:astramusic/features/player/data/serial_command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una ráfaga ejecuta solo el último seek pendiente', () async {
    final executed = <Duration>[];
    final coordinator = LatestSeekCoordinator((position) async {
      executed.add(position);
    });

    final requests = [
      for (var second = 1; second <= 20; second++)
        coordinator.request(Duration(seconds: second)),
    ];
    await Future.wait(requests);

    expect(executed, [const Duration(seconds: 20)]);
    expect(coordinator.discardedCount, 19);
  });

  test(
    'coalesce pendientes durante una ejecución y no bloquea pausa',
    () async {
      final firstGate = Completer<void>();
      final executed = <Duration>[];
      var playing = true;
      final coordinator = LatestSeekCoordinator((position) async {
        executed.add(position);
        if (executed.length == 1) await firstGate.future;
      });
      final commands = SerialCommandQueue();

      final first = coordinator.request(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      final pending = [
        for (var second = 2; second <= 20; second++)
          coordinator.request(Duration(seconds: second)),
      ];
      await commands.run(() async => playing = false);

      expect(playing, isFalse);
      expect(executed, [const Duration(seconds: 1)]);
      firstGate.complete();
      await Future.wait([first, ...pending]);
      expect(playing, isFalse);
      expect(executed, [
        const Duration(seconds: 1),
        const Duration(seconds: 20),
      ]);
    },
  );

  test('puede ignorar seek cuando no hay canción cargada', () async {
    var executions = 0;
    var hasItem = false;
    final coordinator = LatestSeekCoordinator(
      (position) async => executions++,
      canExecute: () => hasItem,
    );

    await coordinator.request(const Duration(seconds: 30));
    expect(executions, 0);

    hasItem = true;
    await coordinator.request(const Duration(seconds: 40));
    expect(executions, 1);
  });
}
