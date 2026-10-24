import 'package:astramusic/features/player/presentation/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('durante el arrastre busca una sola vez al soltar', (
    tester,
  ) async {
    var position = const Duration(seconds: 10);
    final seeks = <Duration>[];
    late StateSetter updateHost;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return SeekBar(
              position: position,
              duration: const Duration(seconds: 100),
              onSeek: seeks.add,
            );
          },
        ),
      ),
    );

    final slider = find.byKey(const Key('seek-slider'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(seeks, isEmpty);
    final draggedValue = tester.widget<Slider>(slider).value;
    updateHost(() => position = const Duration(seconds: 2));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, draggedValue);

    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(draggedValue / 1000, 1));

    updateHost(() => position = const Duration(seconds: 3));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, draggedValue);

    updateHost(
      () => position = Duration(milliseconds: draggedValue.round() - 500),
    );
    await tester.pump();
    expect(
      tester.widget<Slider>(slider).value,
      closeTo(position.inMilliseconds, 1),
    );
  });

  testWidgets('un tap hace un seek y el objetivo vence tras el tiempo máximo', (
    tester,
  ) async {
    var position = Duration.zero;
    final seeks = <Duration>[];
    late StateSetter updateHost;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return SeekBar(
              position: position,
              duration: const Duration(seconds: 100),
              onSeek: seeks.add,
            );
          },
        ),
      ),
    );

    final slider = find.byKey(const Key('seek-slider'));
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(240, 20));
    await tester.pump();
    expect(seeks, hasLength(1));
    final target = tester.widget<Slider>(slider).value;

    updateHost(() => position = const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Slider>(slider).value, target);

    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<Slider>(slider).value, 1000);
  });

  testWidgets('duración cero deshabilita y la posición queda acotada', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SeekBar(
          position: Duration(seconds: 40),
          duration: Duration.zero,
          onSeek: _unusedSeek,
        ),
      ),
    );

    var slider = tester.widget<Slider>(find.byKey(const Key('seek-slider')));
    expect(slider.onChanged, isNull);
    expect(slider.value, 0);

    await tester.pumpWidget(
      _host(
        const SeekBar(
          position: Duration(seconds: 200),
          duration: Duration(seconds: 100),
          onSeek: _unusedSeek,
        ),
      ),
    );
    slider = tester.widget<Slider>(find.byKey(const Key('seek-slider')));
    expect(slider.value, 100000);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 400, child: child)),
  ),
);

void _unusedSeek(Duration position) {}
