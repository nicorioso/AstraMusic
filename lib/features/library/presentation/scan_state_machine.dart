enum ScanPhase { idle, scanning, cancelling }

final class ScanStateMachine {
  ScanPhase _phase = ScanPhase.idle;

  ScanPhase get phase => _phase;

  bool start() {
    if (_phase != ScanPhase.idle) return false;
    _phase = ScanPhase.scanning;
    return true;
  }

  bool requestCancellation() {
    if (_phase != ScanPhase.scanning) return false;
    _phase = ScanPhase.cancelling;
    return true;
  }

  void finish() {
    _phase = ScanPhase.idle;
  }
}
