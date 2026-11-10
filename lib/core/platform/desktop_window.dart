import 'package:window_manager/window_manager.dart';

abstract interface class DesktopWindowController {
  Future<void> initialize();
  Future<void> startDragging();
  Future<void> minimize();
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<void> close();
}

final class SystemDesktopWindowController implements DesktopWindowController {
  const SystemDesktopWindowController();

  @override
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setAsFrameless();
  }

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> close() => windowManager.close();
}
