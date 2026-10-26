import 'package:flutter/foundation.dart';

@immutable
class PerformanceSnapshot {
  const PerformanceSnapshot({
    this.songCount = 0,
    this.firstFrame,
    this.libraryLoad,
    this.lastQueueLoad,
    this.listBuilds = 0,
    this.trackRowBuilds = 0,
  });

  final int songCount;
  final Duration? firstFrame;
  final Duration? libraryLoad;
  final Duration? lastQueueLoad;
  final int listBuilds;
  final int trackRowBuilds;

  PerformanceSnapshot copyWith({
    int? songCount,
    Duration? firstFrame,
    Duration? libraryLoad,
    Duration? lastQueueLoad,
    int? listBuilds,
    int? trackRowBuilds,
  }) => PerformanceSnapshot(
    songCount: songCount ?? this.songCount,
    firstFrame: firstFrame ?? this.firstFrame,
    libraryLoad: libraryLoad ?? this.libraryLoad,
    lastQueueLoad: lastQueueLoad ?? this.lastQueueLoad,
    listBuilds: listBuilds ?? this.listBuilds,
    trackRowBuilds: trackRowBuilds ?? this.trackRowBuilds,
  );
}

final class PerformanceDiagnostics extends ValueNotifier<PerformanceSnapshot> {
  PerformanceDiagnostics._() : super(const PerformanceSnapshot());

  static final instance = PerformanceDiagnostics._();

  Stopwatch _startup = Stopwatch();

  void startStartup() {
    if (!kDebugMode) return;
    value = const PerformanceSnapshot();
    _startup = Stopwatch()..start();
  }

  void recordFirstFrame() {
    if (!kDebugMode || value.firstFrame != null) return;
    value = value.copyWith(firstFrame: _startup.elapsed);
  }

  void recordLibraryLoaded(int songCount) {
    if (!kDebugMode) return;
    value = value.copyWith(
      songCount: songCount,
      libraryLoad: value.libraryLoad ?? _startup.elapsed,
    );
  }

  void recordQueueLoad(Duration elapsed) {
    if (!kDebugMode) return;
    value = value.copyWith(lastQueueLoad: elapsed);
  }

  void recordListBuild() {
    if (!kDebugMode) return;
    value = value.copyWith(listBuilds: value.listBuilds + 1);
  }

  void recordTrackRowBuild() {
    if (!kDebugMode) return;
    value = value.copyWith(trackRowBuilds: value.trackRowBuilds + 1);
  }

  @visibleForTesting
  void resetForTesting() {
    value = const PerformanceSnapshot();
    _startup = Stopwatch()..start();
  }
}
