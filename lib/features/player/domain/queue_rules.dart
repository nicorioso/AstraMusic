import 'package:astramusic/core/platform/audio_player_service.dart';

enum PreviousAction { restartCurrent, goToPrevious }

class PreviousDecision {
  const PreviousDecision(this.action, {this.targetIndex});

  final PreviousAction action;
  final int? targetIndex;
}

PreviousDecision decidePrevious({
  required Duration position,
  required int? previousIndex,
}) {
  if (position > const Duration(seconds: 3) || previousIndex == null) {
    return const PreviousDecision(PreviousAction.restartCurrent);
  }
  return PreviousDecision(
    PreviousAction.goToPrevious,
    targetIndex: previousIndex,
  );
}

int? indexAfterRemoval({
  required int? currentIndex,
  required int removedIndex,
  required int newLength,
}) {
  if (currentIndex == null || newLength == 0) return null;
  if (removedIndex < currentIndex) return currentIndex - 1;
  if (removedIndex == currentIndex) {
    return currentIndex.clamp(0, newLength - 1);
  }
  return currentIndex;
}

int? indexAfterMove({
  required int? currentIndex,
  required int oldIndex,
  required int newIndex,
}) {
  if (currentIndex == null) return null;
  if (oldIndex == currentIndex) return newIndex;
  if (oldIndex < currentIndex && newIndex >= currentIndex) {
    return currentIndex - 1;
  }
  if (oldIndex > currentIndex && newIndex <= currentIndex) {
    return currentIndex + 1;
  }
  return currentIndex;
}

int? relativeIndex({
  required int? currentIndex,
  required int queueLength,
  required int offset,
  required RepeatMode repeatMode,
}) {
  if (currentIndex == null || queueLength == 0) return null;
  if (repeatMode == RepeatMode.one) return currentIndex;

  final target = currentIndex + offset;
  if (target >= 0 && target < queueLength) return target;
  if (repeatMode == RepeatMode.all) return target % queueLength;
  return null;
}

int? nextUnfailedIndex({
  required int currentIndex,
  required List<int> effectiveIndices,
  required Set<int> failedIndices,
}) {
  if (effectiveIndices.isEmpty ||
      failedIndices.length >= effectiveIndices.length) {
    return null;
  }
  final currentPosition = effectiveIndices.indexOf(currentIndex);
  if (currentPosition == -1) return null;

  for (var offset = 1; offset < effectiveIndices.length; offset++) {
    final candidate =
        effectiveIndices[(currentPosition + offset) % effectiveIndices.length];
    if (!failedIndices.contains(candidate)) return candidate;
  }
  return null;
}
