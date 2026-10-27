import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract interface class ArtworkCache {
  Future<int> sizeBytes();
  Future<void> deleteByKey(String key);
  Future<void> clear();
}

const artworkCacheQuotaBytes = 160 * 1024 * 1024;

void enforceArtworkCacheQuotaSync(
  Directory directory, {
  int quotaBytes = artworkCacheQuotaBytes,
  File? preserve,
}) {
  if (!directory.existsSync()) return;
  final files =
      directory.listSync(followLinks: false).whereType<File>().toList()..sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
  var total = files.fold<int>(0, (sum, file) => sum + file.lengthSync());
  for (final file in files) {
    if (total <= quotaBytes) break;
    if (preserve != null && path.equals(file.path, preserve.path)) continue;
    final length = file.lengthSync();
    file.deleteSync();
    total -= length;
  }
  if (total > quotaBytes && preserve != null && preserve.existsSync()) {
    preserve.deleteSync();
  }
}

Future<void> enforceArtworkCacheQuota(
  Directory directory, {
  int quotaBytes = artworkCacheQuotaBytes,
  File? preserve,
}) async {
  if (!await directory.exists()) return;
  final files = <(File, DateTime, int)>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      files.add((entity, stat.modified, stat.size));
    } on FileSystemException {
      // Archivos que desaparecen durante el recorrido no detienen la cuota.
    }
  }
  files.sort((a, b) => a.$2.compareTo(b.$2));
  var total = files.fold<int>(0, (sum, entry) => sum + entry.$3);
  for (final (file, _, length) in files) {
    if (total <= quotaBytes) break;
    if (preserve != null && path.equals(file.path, preserve.path)) continue;
    try {
      await file.delete();
      total -= length;
    } on FileSystemException {
      // Continúa con el resto si otro proceso elimina o bloquea un archivo.
    }
  }
  if (total > quotaBytes && preserve != null) {
    try {
      await preserve.delete();
    } on FileSystemException {
      // Una caché que no se puede limpiar no debe interrumpir la reproducción.
    }
  }
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
    await enforceArtworkCacheQuota(directory);
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
