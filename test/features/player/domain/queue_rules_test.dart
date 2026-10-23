import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/player/domain/queue_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('regla de anterior', () {
    test('reinicia la canción después de tres segundos', () {
      final decision = decidePrevious(
        position: const Duration(seconds: 4),
        previousIndex: 0,
      );

      expect(decision.action, PreviousAction.restartCurrent);
      expect(decision.targetIndex, isNull);
    });

    test('va a la anterior durante los primeros tres segundos', () {
      final decision = decidePrevious(
        position: const Duration(seconds: 3),
        previousIndex: 1,
      );

      expect(decision.action, PreviousAction.goToPrevious);
      expect(decision.targetIndex, 1);
    });
  });

  group('ajuste del índice al quitar', () {
    test('quitar antes de la actual desplaza el índice', () {
      expect(
        indexAfterRemoval(currentIndex: 3, removedIndex: 1, newLength: 4),
        2,
      );
    });

    test('quitar la actual selecciona la siguiente posición disponible', () {
      expect(
        indexAfterRemoval(currentIndex: 2, removedIndex: 2, newLength: 3),
        2,
      );
      expect(
        indexAfterRemoval(currentIndex: 2, removedIndex: 2, newLength: 2),
        1,
      );
    });

    test('una cola vacía no tiene índice actual', () {
      expect(
        indexAfterRemoval(currentIndex: 0, removedIndex: 0, newLength: 0),
        isNull,
      );
    });
  });

  group('ajuste del índice al mover', () {
    test('mover la actual conserva su identidad', () {
      expect(indexAfterMove(currentIndex: 1, oldIndex: 1, newIndex: 3), 3);
    });

    test('mover un elemento pasando sobre la actual ajusta el índice', () {
      expect(indexAfterMove(currentIndex: 2, oldIndex: 0, newIndex: 3), 1);
      expect(indexAfterMove(currentIndex: 2, oldIndex: 4, newIndex: 1), 3);
    });
  });

  group('límites y repetición', () {
    test('off se detiene en ambos extremos', () {
      expect(
        relativeIndex(
          currentIndex: 0,
          queueLength: 3,
          offset: -1,
          repeatMode: RepeatMode.off,
        ),
        isNull,
      );
      expect(
        relativeIndex(
          currentIndex: 2,
          queueLength: 3,
          offset: 1,
          repeatMode: RepeatMode.off,
        ),
        isNull,
      );
    });

    test('all envuelve ambos extremos', () {
      expect(
        relativeIndex(
          currentIndex: 0,
          queueLength: 3,
          offset: -1,
          repeatMode: RepeatMode.all,
        ),
        2,
      );
      expect(
        relativeIndex(
          currentIndex: 2,
          queueLength: 3,
          offset: 1,
          repeatMode: RepeatMode.all,
        ),
        0,
      );
    });

    test('one conserva el índice actual', () {
      expect(
        relativeIndex(
          currentIndex: 1,
          queueLength: 3,
          offset: 1,
          repeatMode: RepeatMode.one,
        ),
        1,
      );
    });
  });

  test('el salto por error evita canciones ya fallidas', () {
    expect(
      nextUnfailedIndex(
        currentIndex: 1,
        effectiveIndices: const [2, 1, 0],
        failedIndices: const {1, 0},
      ),
      2,
    );
    expect(
      nextUnfailedIndex(
        currentIndex: 1,
        effectiveIndices: const [2, 1, 0],
        failedIndices: const {0, 1, 2},
      ),
      isNull,
    );
  });
}
