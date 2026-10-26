import 'dart:async';

import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:flutter/services.dart';

final class AndroidMediaStoreLibraryScanner implements LibraryScanner {
  AndroidMediaStoreLibraryScanner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.nicorioso.astramusic/library_scanner';

  final MethodChannel _channel;
  StreamController<ScanEvent>? _activeController;
  Completer<void>? _cancellationCompletion;

  @override
  Future<LibraryScanTask> startScan({
    String? rootPath,
    Map<String, KnownFileStats> knownFiles = const {},
  }) async {
    if (_activeController != null) {
      throw StateError('Ya hay un escaneo de MediaStore en curso.');
    }

    // Se cierra en _finish cuando el canal reporta fin, cancelación o error.
    // ignore: close_sinks
    final controller = StreamController<ScanEvent>();
    _activeController = controller;
    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      await _channel.invokeMethod<void>('startScan');
    } catch (_) {
      await _finish();
      rethrow;
    }

    return LibraryScanTask(controller.stream, () async {
      if (_activeController != controller) return;
      final completion = Completer<void>();
      _cancellationCompletion = completion;
      try {
        await _channel.invokeMethod<void>('cancelScan');
        await completion.future;
      } catch (_) {
        await _finish();
        rethrow;
      }
    });
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final controller = _activeController;
    if (controller == null || controller.isClosed) return;
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};

    switch (call.method) {
      case 'scanProgress':
        controller.add(
          ScanProgress(
            foundCount: arguments['foundCount'] as int? ?? 0,
            errorCount: arguments['errorCount'] as int? ?? 0,
            unchangedCount: arguments['unchangedCount'] as int? ?? 0,
          ),
        );
      case 'scanBatch':
        final rawTracks = arguments['tracks'] as List<Object?>? ?? const [];
        controller.add(
          ScanBatch(
            rawTracks
                .cast<Map<Object?, Object?>>()
                .map(_trackFromNative)
                .toList(growable: false),
          ),
        );
      case 'scanCompleted':
        controller.add(
          ScanCompleted(
            tracks: const [],
            errorCount: arguments['errorCount'] as int? ?? 0,
            unchangedCount: arguments['unchangedCount'] as int? ?? 0,
          ),
        );
        await _finish();
      case 'scanCancelled':
        controller.add(const ScanCancelled());
        await _finish();
      case 'scanFailed':
        controller.addError(
          PlatformException(
            code: 'media_store_scan_failed',
            message:
                arguments['message'] as String? ??
                'No fue posible consultar la música del dispositivo.',
          ),
        );
        await _finish();
    }
  }

  Future<void> _finish() async {
    final controller = _activeController;
    _activeController = null;
    _channel.setMethodCallHandler(null);
    if (controller != null && !controller.isClosed) await controller.close();
    final cancellation = _cancellationCompletion;
    _cancellationCompletion = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  ScannedTrack _trackFromNative(Map<Object?, Object?> values) => ScannedTrack(
    uri: values['uri']! as String,
    title: values['title']! as String,
    artist: values['artist'] as String?,
    album: values['album'] as String?,
    genre: values['genre'] as String?,
    durationMs: values['durationMs'] as int?,
    trackNumber: values['trackNumber'] as int?,
    year: values['year'] as int?,
    fileSize: values['fileSize'] as int?,
    dateAdded: switch (values['dateAddedMs']) {
      final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
      ),
      _ => null,
    },
    dateModified: switch (values['dateModifiedMs']) {
      final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
      ),
      _ => null,
    },
  );
}
