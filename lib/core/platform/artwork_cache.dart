import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract interface class ArtworkCache {
  Future<int> sizeBytes();
  Future<void> deleteByKey(String key);
  Future<void> clear();
}

final class FileArtworkCache implements ArtworkCache {
  const FileArtworkCache();

  Future<Directory> _directory() async {
    final cache = await getApplicationCacheDirectory();
    return Directory(path.join(cache.path, 'artwork'));
  }

  @override
  Future<int> sizeBytes() async {
    final directory = await _directory();
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  @override
  Future<void> deleteByKey(String key) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File && path.basename(entity.path).startsWith(key)) {
        await entity.delete();
      }
    }
  }

  @override
  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
