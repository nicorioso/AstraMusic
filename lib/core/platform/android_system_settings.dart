import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

abstract interface class AndroidSystemSettings {
  Future<bool> openAppNotificationSettings();
  Future<void> openBatteryOptimizationSettings();
}

final class SystemAndroidSettings implements AndroidSystemSettings {
  const SystemAndroidSettings();

  static const _channel = MethodChannel('astramusic/system_settings');

  @override
  Future<bool> openAppNotificationSettings() => openAppSettings();

  @override
  Future<void> openBatteryOptimizationSettings() =>
      _channel.invokeMethod<void>('openBatteryOptimizationSettings');
}
