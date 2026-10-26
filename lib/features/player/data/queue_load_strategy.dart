import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

abstract interface class QueueLoadStrategy {
  Future<Duration?> load(
    AudioPlayer player,
    List<AudioSource> sources, {
    required int startIndex,
    required Duration initialPosition,
  });
}

final class SetAudioSourcesQueueLoadStrategy implements QueueLoadStrategy {
  const SetAudioSourcesQueueLoadStrategy();

  @override
  Future<Duration?> load(
    AudioPlayer player,
    List<AudioSource> sources, {
    required int startIndex,
    required Duration initialPosition,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await player.setAudioSources(
        sources,
        initialIndex: startIndex,
        initialPosition: initialPosition,
      );
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        PerformanceDiagnostics.instance.recordQueueLoad(stopwatch.elapsed);
        debugPrint(
          'AstraMusic: setAudioSources cargó ${sources.length} elementos '
          'en ${stopwatch.elapsedMilliseconds} ms.',
        );
      }
    }
  }
}
