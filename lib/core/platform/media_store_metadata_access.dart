import 'package:flutter/services.dart';

abstract interface class MediaStoreMetadataAccess {
  Future<String> prepare(String uri);
  Future<void> commit(String uri);
  Future<void> cleanup();
}

final class AndroidMediaStoreMetadataAccess
    implements MediaStoreMetadataAccess {
  AndroidMediaStoreMetadataAccess({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.nicorioso.astramusic/metadata_write');

  final MethodChannel _channel;

  @override
  Future<String> prepare(String uri) async =>
      (await _channel.invokeMethod<String>('prepare', {'uri': uri}))!;

  @override
  Future<void> commit(String uri) =>
      _channel.invokeMethod<void>('commit', {'uri': uri});

  @override
  Future<void> cleanup() => _channel.invokeMethod<void>('cleanup');
}
