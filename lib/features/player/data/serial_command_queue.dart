import 'dart:async';

final class SerialCommandQueue {
  Future<void> _tail = Future.value();
  Future<void>? _closeFuture;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<T> run<T>(Future<T> Function() command) {
    if (_closed) {
      return Future.error(StateError('La cola de comandos está cerrada.'));
    }
    return _enqueue(command);
  }

  Future<void> close(Future<void> Function() cleanup) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    return _closeFuture = _enqueue(cleanup);
  }

  Future<T> _enqueue<T>(Future<T> Function() command) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await command());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
