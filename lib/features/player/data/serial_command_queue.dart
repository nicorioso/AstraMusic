import 'dart:async';

final class SerialCommandQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() command) {
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
