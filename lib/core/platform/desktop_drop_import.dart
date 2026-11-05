import 'dart:io';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/desktop_library_scanner.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as path;

/// Traduce una entrega nativa a las rutas que ya acepta la importación local.
Future<List<PickedAudioFile>> audioFilesFromDrop(List<DropItem> items) async {
  final result = <PickedAudioFile>[];
  final seen = <String>{};
  for (final item in items) {
    if (item is DropItemDirectory) {
      final directory = Directory(item.path);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) _include(entity.path, result, seen);
      }
    } else if (item is DropItemFile) {
      _include(item.path, result, seen);
    }
  }
  return result;
}

void _include(String filePath, List<PickedAudioFile> result, Set<String> seen) {
  final normalized = path.normalize(path.absolute(filePath));
  if (!supportedAudioExtensions.contains(
        path.extension(normalized).toLowerCase(),
      ) ||
      !seen.add(normalized)) {
    return;
  }
  result.add(
    PickedAudioFile(
      path: normalized,
      title: path.basenameWithoutExtension(normalized),
    ),
  );
}
