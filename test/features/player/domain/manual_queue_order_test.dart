import 'dart:math';

import 'package:astramusic/features/player/domain/manual_queue_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la mezcla conserva la actual primero sin perder ni duplicar', () {
    final order = ManualQueueOrder<int>([1, 2, 3, 4, 5], random: Random(7));

    order.setShuffle(enabled: true, currentIndex: 2);

    expect(order.playback, hasLength(5));
    expect(order.playback.first, 3);
    expect(order.playback.toSet(), {1, 2, 3, 4, 5});
  });

  test('desactivar aleatorio restaura el orden original desde la actual', () {
    final order = ManualQueueOrder<int>([1, 2, 3, 4, 5], random: Random(11));
    order.setShuffle(enabled: true, currentIndex: 1);
    final current = order.playback.first;

    final restoredIndex = order.setShuffle(enabled: false, currentIndex: 0);

    expect(order.playback, [1, 2, 3, 4, 5]);
    expect(order.playback[restoredIndex], current);
  });

  test('las ediciones activas mantienen ambos órdenes coherentes', () {
    final order = ManualQueueOrder<String>([
      'a',
      'b',
      'c',
      'd',
    ], random: Random(5));
    order.setShuffle(enabled: true, currentIndex: 1);

    order.add('e');
    expect(order.playback.last, 'e');
    expect(order.original.last, 'e');

    order.insertNext(currentIndex: 0, item: 'x');
    expect(order.playback[1], 'x');
    expect(order.original[order.original.indexOf('b') + 1], 'x');

    final moved = order.playback.last;
    order.move(order.playback.length - 1, 1);
    expect(order.playback[1], moved);
    expect(order.original.last, 'e');

    final removed = order.playback[2];
    order.removeAt(2);
    expect(order.playback, isNot(contains(removed)));
    expect(order.original, isNot(contains(removed)));
  });
}
