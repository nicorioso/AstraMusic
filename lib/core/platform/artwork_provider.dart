import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:astramusic/features/library/domain/track.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract interface class ArtworkProvider {
  Future<String?> artworkFor(Track track, {required int size});
}

String artworkCacheKey({String? artist, String? album, required String uri}) {
  final normalizedArtist = artist?.trim().toLowerCase();
  final normalizedAlbum = album?.trim().toLowerCase();
  final source =
      normalizedArtist != null &&
          normalizedArtist.isNotEmpty &&
          normalizedAlbum != null &&
          normalizedAlbum.isNotEmpty
      ? '$normalizedArtist\u0000$normalizedAlbum'
      : uri;
  var hash = 0xcbf29ce484222325;
  for (final byte in source.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

File? selectFolderArtwork(Directory directory) {
  if (!directory.existsSync()) return null;
  final candidates = <String, File>{};
  try {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final extension = path.extension(entity.path).toLowerCase();
      if (extension != '.jpg' && extension != '.png') continue;
      candidates[path.basenameWithoutExtension(entity.path).toLowerCase()] =
          entity;
    }
  } on FileSystemException {
    return null;
  }
  for (final name in const ['cover', 'folder', 'front']) {
    final match = candidates[name];
    if (match != null) return match;
  }
  return null;
}

final class CachedArtworkProvider implements ArtworkProvider {
  CachedArtworkProvider({MethodChannel? channel, this.memoryCapacity = 64})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.nicorioso.astramusic/artwork';
  final MethodChannel _channel;
  final int memoryCapacity;
  final LinkedHashMap<String, String?> _memory = LinkedHashMap();
  final Map<String, Future<String?>> _pending = {};

  @override
  Future<String?> artworkFor(Track track, {required int size}) {
    final existing = track.artworkPath;
    if (existing != null && File(existing).existsSync()) {
      return Future.value(existing);
    }
    if (!Platform.isAndroid) return Future.value(null);
    final key = '${track.uri}@$size';
    if (_memory.containsKey(key)) {
      final value = _memory.remove(key);
      _memory[key] = value;
      return Future.value(value);
    }
    return _pending.putIfAbsent(key, () => _loadAndroid(track, size, key));
  }

  Future<String?> _loadAndroid(Track track, int size, String memoryKey) async {
    String? result;
    try {
      final cache = await getApplicationCacheDirectory();
      final directory = Directory(path.join(cache.path, 'artwork'));
      await directory.create(recursive: true);
      final file = File(
        path.join(
          directory.path,
          '${artworkCacheKey(artist: track.artist, album: track.album, uri: track.uri)}-$size.jpg',
        ),
      );
      if (await file.exists()) {
        result = file.path;
      } else {
        final bytes = await _channel.invokeMethod<Uint8List>('loadThumbnail', {
          'uri': track.uri,
          'size': size,
        });
        if (bytes != null && bytes.isNotEmpty) {
          await file.writeAsBytes(bytes, flush: true);
          result = file.path;
        }
      }
    } on Object {
      result = null;
    } finally {
      unawaited(_pending.remove(memoryKey)!);
    }
    _memory[memoryKey] = result;
    while (_memory.length > memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
    return result;
  }
}
