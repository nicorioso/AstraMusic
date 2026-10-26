import 'dart:async';

import 'package:astramusic/core/utils/throttle_latest.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emite como máximo una posición cada 250 ms y conserva la última', () {
    fakeAsync((async) {
      final source = StreamController<int>(sync: true);
      final values = <int>[];
      throttleLatest(
        source.stream,
        const Duration(milliseconds: 250),
      ).listen(values.add);

      source.add(1);
      async.elapse(const Duration(milliseconds: 50));
      source
        ..add(2)
        ..add(3);
      expect(values, [1]);

      async.elapse(const Duration(milliseconds: 199));
      expect(values, [1]);
      async.elapse(const Duration(milliseconds: 1));
      expect(values, [1, 3]);

      async.elapse(const Duration(milliseconds: 100));
      source.add(4);
      async.elapse(const Duration(milliseconds: 150));
      expect(values, [1, 3, 4]);
      source.close();
      async.flushMicrotasks();
    });
  });
}
