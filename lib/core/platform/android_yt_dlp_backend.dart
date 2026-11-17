import 'dart:async';
import 'dart:convert';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/desktop_yt_dlp_backend.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:flutter/services.dart';

class AndroidYtDlpBackend
    implements AudioDownloadBackend, UpdatableAudioDownloadBackend {
  AndroidYtDlpBackend({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('astramusic/yt_dlp'),
      _events = events ?? const EventChannel('astramusic/yt_dlp/events');

  final MethodChannel _methods;
  final EventChannel _events;
  bool _canceled = false;

  /// Actualiza el extractor empaquetado sin bloquear el hilo principal.
  @override
  Future<String?> updateEngine() async {
    final response = await _methods.invokeMapMethod<String, dynamic>(
      'updateEngine',
    );
    return response?['version'] as String?;
  }

  @override
  Future<DownloadAvailability> checkAvailability() async {
    try {
      final value = await _methods.invokeMapMethod<String, dynamic>(
        'checkAvailability',
      );
      return DownloadAvailability(available: value?['available'] == true);
    } on PlatformException catch (error) {
      return DownloadAvailability(available: false, error: error.message);
    }
  }

  @override
  Future<SourcePreview> analyzeUrl(String url) async {
    final parsed = YoutubeUrl.parse(url);
    if (parsed == null) {
      throw const FormatException('Ingresa una URL válida de YouTube.');
    }
    final response = await _methods.invokeMapMethod<String, dynamic>(
      'analyzeUrl',
      {'url': url},
    );
    final json =
        jsonDecode(response!['json'] as String) as Map<String, dynamic>;
    final id = json['id'] as String;
    final seconds = (json['duration'] as num?)?.round();
    return SourcePreview(
      id: id,
      title: (json['title'] as String?) ?? id,
      author:
          (json['uploader'] as String?) ?? (json['channel'] as String?) ?? '',
      type: parsed.isPlaylist ? SourceType.playlist : SourceType.video,
      duration: seconds == null ? null : Duration(seconds: seconds),
      thumbnailUrl: json['thumbnail'] as String?,
    );
  }

  @override
  Future<PlaylistPreview> analyzePlaylist(String url) async {
    final parsed = YoutubeUrl.parse(url);
    if (parsed == null || !parsed.isPlaylist) {
      throw const FormatException('Ingresa una URL de playlist de YouTube.');
    }
    final response = await _methods.invokeMapMethod<String, dynamic>(
      'analyzePlaylist',
      {'url': url},
    );
    return DesktopYtDlpBackend.parsePlaylistJson(response!['json'] as String);
  }

  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) async* {
    _canceled = false;
    try {
      final preview = await analyzeUrl(request.url);
      final subscription = _events.receiveBroadcastStream().map(
        (event) => Map<String, dynamic>.from(event as Map),
      );
      final controller = StreamController<DownloadEvent>();
      final listener = subscription.listen(
        (event) {
          final status = DownloadStatus.values.byName(
            event['status'] as String,
          );
          controller.add(
            DownloadEvent(
              status: status,
              error: event['error'] as String?,
              downloadedBytes: (event['percent'] as num?)?.round(),
              totalBytes: event['percent'] == null ? null : 100,
              audio: status == DownloadStatus.completed
                  ? DownloadedAudio(
                      id: preview.id,
                      temporaryPath: event['path'] as String,
                      title: preview.title,
                      author: preview.author,
                      duration: preview.duration,
                      thumbnailUrl: preview.thumbnailUrl,
                      thumbnailPath: event['thumbnailPath'] as String?,
                    )
                  : null,
            ),
          );
          if (status == DownloadStatus.completed ||
              status == DownloadStatus.failed ||
              status == DownloadStatus.canceled) {
            unawaited(controller.close());
          }
        },
        onError: (Object error) {
          controller.add(
            DownloadEvent(status: DownloadStatus.failed, error: '$error'),
          );
          unawaited(controller.close());
        },
      );
      try {
        await _methods.invokeMethod<void>('downloadAudio', {
          'url': request.url,
          'id': preview.id,
          'temporaryDirectory': request.temporaryDirectory,
        });
        yield* controller.stream;
      } finally {
        await listener.cancel();
        await controller.close();
      }
    } catch (error) {
      yield DownloadEvent(
        status: _canceled ? DownloadStatus.canceled : DownloadStatus.failed,
        error: _canceled ? null : friendlyDownloadError('$error'),
      );
    }
  }

  @override
  Future<void> cancel() async {
    _canceled = true;
    await _methods.invokeMethod<void>('cancel');
  }
}
