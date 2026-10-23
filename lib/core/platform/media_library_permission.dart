import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum MediaLibraryPermissionStatus { granted, denied, permanentlyDenied }

abstract interface class MediaLibraryPermission {
  Future<MediaLibraryPermissionStatus> request();
  Future<bool> openSettings();
}

final class SystemMediaLibraryPermission implements MediaLibraryPermission {
  const SystemMediaLibraryPermission();

  @override
  Future<MediaLibraryPermissionStatus> request() async {
    if (!Platform.isAndroid) return MediaLibraryPermissionStatus.granted;

    final status = await Permission.audio.request();
    if (status.isGranted) return MediaLibraryPermissionStatus.granted;
    if (status.isPermanentlyDenied) {
      return MediaLibraryPermissionStatus.permanentlyDenied;
    }
    return MediaLibraryPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
