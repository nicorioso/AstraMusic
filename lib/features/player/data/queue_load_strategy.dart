import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

abstract interface class QueueLoadStrategy {
  Future<Duration?> load(
    AudioPlayer player,
    List<AudioSource> sources, {
    required int startIndex,
    required ShuffleOrder shuffleOrder,
  });
}

final class SetAudioSourcesQueueLoadStrategy implements QueueLoadStrategy {
  const SetAudioSourcesQueueLoadStrategy();

  @override
  Future<Duration?> load(
    AudioPlayer player,
    List<AudioSource> sources, {
    required int startIndex,
    required ShuffleOrder shuffleOrder,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await player.setAudioSources(
        sources,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
        shuffleOrder: shuffleOrder,
      );
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'AstraMusic: setAudioSources cargó ${sources.length} elementos '
          'en ${stopwatch.elapsedMilliseconds} ms.',
        );
      }
    }
  }
}

final class QueueShuffleOrder extends ShuffleOrder {
  QueueShuffleOrder({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  final List<int> indices = [];

  int? _scheduledEffectiveIndex;

  void scheduleInsertionAt(int effectiveIndex) {
    _scheduledEffectiveIndex = effectiveIndex;
  }

  @override
  void shuffle({int? initialIndex}) {
    if (indices.length <= 1) return;
    indices.shuffle(_random);
    if (initialIndex == null) return;
    final currentPosition = indices.indexOf(initialIndex);
    if (currentPosition <= 0) return;
    final first = indices.first;
    indices[0] = initialIndex;
    indices[currentPosition] = first;
  }

  @override
  void insert(int index, int count) {
    for (var position = 0; position < indices.length; position++) {
      if (indices[position] >= index) indices[position] += count;
    }
    final insertionPosition = (_scheduledEffectiveIndex ?? indices.length)
        .clamp(0, indices.length);
    _scheduledEffectiveIndex = null;
    indices.insertAll(
      insertionPosition,
      List.generate(count, (offset) => index + offset),
    );
  }

  @override
  void removeRange(int start, int end) {
    final removed = {for (var index = start; index < end; index++) index};
    indices.removeWhere(removed.contains);
    final count = end - start;
    for (var position = 0; position < indices.length; position++) {
      if (indices[position] >= end) indices[position] -= count;
    }
  }

  @override
  void clear() {
    indices.clear();
    _scheduledEffectiveIndex = null;
  }
}
