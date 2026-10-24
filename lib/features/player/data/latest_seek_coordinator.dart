import 'dart:async';

typedef SeekExecutor = Future<void> Function(Duration position);

final class LatestSeekCoordinator {
  LatestSeekCoordinator(
    this._execute, {
    bool Function()? canExecute,
    this.onDiscarded,
  }) : _canExecute = canExecute ?? _alwaysEnabled;

  final SeekExecutor _execute;
  final bool Function() _canExecute;
  final void Function(int discardedCount)? onDiscarded;

  _PendingSeek? _pending;
  bool _scheduled = false;
  bool _running = false;
  int _discardedCount = 0;

  int get discardedCount => _discardedCount;

  Future<void> request(Duration position) {
    if (!_canExecute()) return Future.value();

    final request = _PendingSeek(position);
    final replaced = _pending;
    if (replaced != null) {
      _discardedCount++;
      replaced.completeDiscarded();
      onDiscarded?.call(_discardedCount);
    }
    _pending = request;

    if (!_running && !_scheduled) {
      _scheduled = true;
      scheduleMicrotask(() => unawaited(_drain()));
    }
    return request.future;
  }

  Future<void> _drain() async {
    _scheduled = false;
    if (_running) return;
    _running = true;
    try {
      while (_pending != null) {
        final request = _pending!;
        _pending = null;
        try {
          await _execute(request.position);
          request.complete();
        } catch (error, stackTrace) {
          request.completeError(error, stackTrace);
        }
      }
    } finally {
      _running = false;
      if (_pending != null && !_scheduled) {
        _scheduled = true;
        scheduleMicrotask(() => unawaited(_drain()));
      }
    }
  }

  static bool _alwaysEnabled() => true;
}

final class _PendingSeek {
  _PendingSeek(this.position);

  final Duration position;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void completeDiscarded() => complete();

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}
