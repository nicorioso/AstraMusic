import 'dart:math';

import 'package:astramusic/features/player/data/queue_load_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mantiene la inserción solicitada dentro del orden aleatorio', () {
    final order = QueueShuffleOrder(random: Random(7));
    order.insert(0, 4);
    order.shuffle(initialIndex: 2);

    expect(order.indices.first, 2);

    order.scheduleInsertionAt(1);
    order.insert(4, 1);

    expect(order.indices[1], 4);
    expect(order.indices.toSet(), {0, 1, 2, 3, 4});
  });

  test('al mover conserva un orden efectivo válido', () {
    final order = QueueShuffleOrder(random: Random(11));
    order.insert(0, 4);
    order.shuffle(initialIndex: 1);

    order.removeRange(3, 4);
    order.scheduleInsertionAt(1);
    order.insert(0, 1);

    expect(order.indices.length, 4);
    expect(order.indices.toSet(), {0, 1, 2, 3});
    expect(order.indices[1], 0);
  });
}
