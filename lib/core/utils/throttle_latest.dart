import 'dart:async';

Stream<T> throttleLatest<T>(Stream<T> source, Duration interval) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  T? pending;
  var hasPending = false;

  void startWindow() {
    timer = Timer(interval, () {
      timer = null;
      if (!hasPending) return;
      final value = pending as T;
      pending = null;
      hasPending = false;
      controller.add(value);
      startWindow();
    });
  }

  controller = StreamController<T>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        (value) {
          if (timer == null) {
            controller.add(value);
            startWindow();
          } else {
            pending = value;
            hasPending = true;
          }
        },
        onError: controller.addError,
        onDone: () {
          if (hasPending) controller.add(pending as T);
          timer?.cancel();
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
