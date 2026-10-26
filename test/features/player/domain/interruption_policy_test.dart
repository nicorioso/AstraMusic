import 'package:astramusic/features/player/domain/interruption_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InterruptionPolicy', () {
    test('llamada pausa y reanuda solo si estaba sonando', () {
      final policy = InterruptionPolicy();
      expect(
        policy
            .begin(InterruptionKind.transient, isPlaying: true, volume: 1)
            .pause,
        isTrue,
      );
      expect(policy.end(InterruptionKind.transient).resume, isTrue);

      expect(
        policy
            .begin(InterruptionKind.transient, isPlaying: false, volume: 1)
            .pause,
        isFalse,
      );
      expect(policy.end(InterruptionKind.transient).resume, isFalse);
    });

    test('pérdida permanente nunca reanuda', () {
      final policy = InterruptionPolicy();
      expect(
        policy
            .begin(InterruptionKind.permanent, isPlaying: true, volume: 1)
            .pause,
        isTrue,
      );
      expect(policy.end(InterruptionKind.permanent).resume, isFalse);
    });

    test('ducking solapado restaura exactamente el volumen original', () {
      final policy = InterruptionPolicy();
      expect(
        policy
            .begin(InterruptionKind.duck, isPlaying: true, volume: 0.8)
            .volume,
        closeTo(0.16, 0.000001),
      );
      expect(
        policy
            .begin(InterruptionKind.duck, isPlaying: true, volume: 0.16)
            .volume,
        isNull,
      );
      expect(policy.end(InterruptionKind.duck).volume, isNull);
      expect(policy.end(InterruptionKind.duck).volume, 0.8);
    });

    test('interrupciones de pausa solapadas reanudan una sola vez', () {
      final policy = InterruptionPolicy();
      policy.begin(InterruptionKind.transient, isPlaying: true, volume: 1);
      policy.begin(InterruptionKind.transient, isPlaying: false, volume: 1);
      expect(policy.end(InterruptionKind.transient).resume, isFalse);
      expect(policy.end(InterruptionKind.transient).resume, isTrue);
      expect(policy.end(InterruptionKind.transient).resume, isFalse);
    });

    test('pausa manual durante llamada cancela reanudación', () {
      final policy = InterruptionPolicy();
      policy.begin(InterruptionKind.transient, isPlaying: true, volume: 1);
      policy.userPaused();
      expect(policy.end(InterruptionKind.transient).resume, isFalse);
    });
  });

  test('becoming noisy pausa solo si estaba sonando', () {
    expect(shouldPauseForBecomingNoisy(isPlaying: true), isTrue);
    expect(shouldPauseForBecomingNoisy(isPlaying: false), isFalse);
  });
}
