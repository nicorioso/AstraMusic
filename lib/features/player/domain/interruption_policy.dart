enum InterruptionKind { permanent, transient, duck }

class InterruptionDecision {
  const InterruptionDecision({
    this.pause = false,
    this.resume = false,
    this.volume,
  });

  final bool pause;
  final bool resume;
  final double? volume;
}

class InterruptionPolicy {
  InterruptionPolicy({this.duckFactor = 0.2});

  final double duckFactor;
  int _pauseInterruptions = 0;
  int _duckInterruptions = 0;
  bool _resumeAfterInterruption = false;
  double? _volumeBeforeDuck;

  InterruptionDecision begin(
    InterruptionKind kind, {
    required bool isPlaying,
    required double volume,
  }) {
    switch (kind) {
      case InterruptionKind.permanent:
        _pauseInterruptions++;
        _resumeAfterInterruption = false;
        return InterruptionDecision(pause: isPlaying);
      case InterruptionKind.transient:
        if (_pauseInterruptions == 0 && isPlaying) {
          _resumeAfterInterruption = true;
        }
        _pauseInterruptions++;
        return InterruptionDecision(pause: isPlaying);
      case InterruptionKind.duck:
        if (_duckInterruptions++ == 0) {
          _volumeBeforeDuck = volume;
          return InterruptionDecision(volume: volume * duckFactor);
        }
        return const InterruptionDecision();
    }
  }

  InterruptionDecision end(InterruptionKind kind) {
    switch (kind) {
      case InterruptionKind.permanent:
      case InterruptionKind.transient:
        if (_pauseInterruptions > 0) _pauseInterruptions--;
        if (_pauseInterruptions != 0) return const InterruptionDecision();
        final resume = _resumeAfterInterruption;
        _resumeAfterInterruption = false;
        return InterruptionDecision(resume: resume);
      case InterruptionKind.duck:
        if (_duckInterruptions > 0) _duckInterruptions--;
        if (_duckInterruptions != 0 || _volumeBeforeDuck == null) {
          return const InterruptionDecision();
        }
        final volume = _volumeBeforeDuck;
        _volumeBeforeDuck = null;
        return InterruptionDecision(volume: volume);
    }
  }

  void userPaused() => _resumeAfterInterruption = false;
}

bool shouldPauseForBecomingNoisy({required bool isPlaying}) => isPlaying;
