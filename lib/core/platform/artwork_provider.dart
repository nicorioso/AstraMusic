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

enum ArtworkUsage { dynamicColor, list, miniPlayer, player }

enum ArtworkSource { file, mediaStore, none }

ArtworkSource artworkSourceFor(Track track) {
  final artworkPath = track.artworkPath?.trim();
  if (artworkPath != null && artworkPath.isNotEmpty) return ArtworkSource.file;
  return Uri.tryParse(track.uri)?.scheme.toLowerCase() == 'content'
      ? ArtworkSource.mediaStore
      : ArtworkSource.none;
}

int artworkThumbnailBucket(ArtworkUsage usage) => switch (usage) {
  ArtworkUsage.dynamicColor => 128,
  ArtworkUsage.list || ArtworkUsage.miniPlayer => 256,
  ArtworkUsage.player => 640,
};

int normalizeArtworkThumbnailBucket(int requestedSize) => requestedSize <= 128
    ? 128
    : requestedSize <= 256
    ? 256
    : 640;

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

String artworkBucketCacheKey({
  String? artist,
  String? album,
  required String uri,
  required int bucket,
}) => '${artworkCacheKey(artist: artist, album: album, uri: uri)}-$bucket';

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
  CachedArtworkProvider({
    MethodChannel? channel,
    this.cacheDirectory,
    this.thumbnailLoader,
    this.memoryCapacityBytes = 8 * 1024 * 1024,
    this.maxConcurrentLoads = 3,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       assert(maxConcurrentLoads > 0);

  static const _channelName = 'com.nicorioso.astramusic/artwork';
  final MethodChannel _channel;
  final Future<Directory> Function()? cacheDirectory;
  final Future<Uint8List?> Function(String uri, int size)? thumbnailLoader;
  final int memoryCapacityBytes;
  final int maxConcurrentLoads;
  final LinkedHashMap<String, _MemoryArtwork> _memory = LinkedHashMap();
  final Map<String, Future<String?>> _pending = {};
  final Queue<Completer<void>> _loadWaiters = Queue();
  var _memoryBytes = 0;
  var _activeLoads = 0;

  @override
  Future<String?> artworkFor(Track track, {required int size}) {
    final bucket = normalizeArtworkThumbnailBucket(size);
    final source = artworkSourceFor(track);
    final sourceValue = switch (source) {
      ArtworkSource.file => track.artworkPath!.trim(),
      ArtworkSource.mediaStore => track.uri,
      ArtworkSource.none => '',
    };
    if (source == ArtworkSource.none) return Future.value(null);
    final key = '${source.name}:$sourceValue@$bucket';
    final cached = _memory.remove(key);
    if (cached != null) {
      _memory[key] = cached;
      return Future.value(cached.path);
    }
    return _pending.putIfAbsent(
      key,
      () => _load(track, bucket, key, source, sourceValue),
    );
  }

  Future<String?> _load(
    Track track,
    int size,
    String memoryKey,
    ArtworkSource source,
    String sourceValue,
  ) async {
    await _acquireLoadSlot();
    String? result;
    var byteSize = 0;
    try {
      if (source == ArtworkSource.file) {
        final file = File(sourceValue);
        if (await file.exists()) {
          byteSize = await file.length();
          result = file.path;
        }
      } else {
        final cache =
            await (cacheDirectory?.call() ?? getApplicationCacheDirectory());
        final directory = Directory(path.join(cache.path, 'artwork'));
        await directory.create(recursive: true);
        final file = File(
          path.join(
            directory.path,
            '${artworkBucketCacheKey(artist: track.artist, album: track.album, uri: track.uri, bucket: size)}.jpg',
          ),
        );
        if (await file.exists()) {
          byteSize = await file.length();
          result = file.path;
        } else {
          final bytes =
              await (thumbnailLoader?.call(track.uri, size) ??
                  _channel.invokeMethod<Uint8List>('loadThumbnail', {
                    'uri': track.uri,
                    'size': size,
                  }));
          if (bytes != null && bytes.isNotEmpty) {
            await file.writeAsBytes(bytes, flush: true);
            byteSize = bytes.lengthInBytes;
            result = file.path;
          }
        }
      }
    } on Object {
      result = null;
    } finally {
      _pending.remove(memoryKey)?.ignore();
      _releaseLoadSlot();
    }
    if (result != null && byteSize > 0) {
      _memory[memoryKey] = _MemoryArtwork(result, byteSize);
      _memoryBytes += byteSize;
      while (_memoryBytes > memoryCapacityBytes && _memory.length > 1) {
        final removed = _memory.remove(_memory.keys.first)!;
        _memoryBytes -= removed.byteSize;
      }
    }
    return result;
  }

  Future<void> _acquireLoadSlot() async {
    if (_activeLoads < maxConcurrentLoads) {
      _activeLoads++;
      return;
    }
    final waiter = Completer<void>();
    _loadWaiters.add(waiter);
    await waiter.future;
    _activeLoads++;
  }

  void _releaseLoadSlot() {
    _activeLoads--;
    if (_loadWaiters.isNotEmpty) _loadWaiters.removeFirst().complete();
  }
}

final class _MemoryArtwork {
  const _MemoryArtwork(this.path, this.byteSize);

  final String path;
  final int byteSize;
}
