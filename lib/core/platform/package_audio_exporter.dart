import 'dart:io';

import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

abstract interface class PackageAudioExporter {
  Future<String> copy(String uri, Directory destination, String stem);
}

final class SystemPackageAudioExporter implements PackageAudioExporter {
  const SystemPackageAudioExporter();

  static const _channel = MethodChannel(
    'com.nicorioso.astramusic/package_audio',
  );

  @override
  Future<String> copy(String uri, Directory destination, String stem) async {
    final localPath = localFilePathFromLocation(uri);
    if (localPath != null) {
      final source = File(localPath);
      if (!await source.exists()) {
        throw FileSystemException('Falta el audio', source.path);
      }
      final filename = '$stem${path.extension(source.path)}';
      await source.copy(path.join(destination.path, filename));
      return filename;
    }
    if (Uri.tryParse(uri)?.scheme != 'content' || !Platform.isAndroid) {
      throw FileSystemException(
        'La canción no es un archivo local exportable',
        uri,
      );
    }
    final filename = await _channel.invokeMethod<String>('copyAudio', {
      'uri': uri,
      'destination': destination.path,
      'stem': stem,
    });
    if (filename == null ||
        !RegExp(r'^[0-9]{5}\.[a-zA-Z0-9]+$').hasMatch(filename) ||
        !await File(path.join(destination.path, filename)).exists()) {
      throw const FormatException('No se pudo copiar el audio de MediaStore.');
    }
    return filename;
  }
}
