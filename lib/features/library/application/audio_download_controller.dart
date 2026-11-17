import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/android_yt_dlp_backend.dart';
import 'package:astramusic/core/platform/desktop_yt_dlp_backend.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:astramusic/features/library/application/audio_download_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final audioDownloadBackendProvider = Provider<AudioDownloadBackend>((ref) {
  if (Platform.isLinux || Platform.isWindows) return DesktopYtDlpBackend();
  if (Platform.isAndroid) return AndroidYtDlpBackend();
  return const _UnavailableAudioDownloadBackend();
});

final audioDownloadServiceProvider = Provider<AudioDownloadService>((ref) {
  return AudioDownloadService(
    backend: ref.watch(audioDownloadBackendProvider),
    tracks: ref.watch(trackRepositoryProvider),
    playlists: ref.watch(playlistRepositoryProvider),
    supportDirectory: getApplicationSupportDirectory,
    temporaryDirectory: getTemporaryDirectory,
  );
});

final audioDownloadControllerProvider =
    NotifierProvider<AudioDownloadController, AudioDownloadState>(
      AudioDownloadController.new,
    );

class AudioDownloadState {
  const AudioDownloadState({
    this.availability,
    this.preview,
    this.playlistPreview,
    this.status,
    this.downloadedBytes,
    this.totalBytes,
    this.error,
    this.result,
    this.batchProgress,
    this.batchResult,
    this.isBusy = false,
  });

  final DownloadAvailability? availability;
  final SourcePreview? preview;
  final PlaylistPreview? playlistPreview;
  final DownloadStatus? status;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? error;
  final AudioImportResult? result;
  final BatchProgress? batchProgress;
  final DownloadBatchResult? batchResult;
  final bool isBusy;
  Track? get track => result?.track;
}

class AudioDownloadController extends Notifier<AudioDownloadState> {
  @override
  AudioDownloadState build() {
    final service = ref.read(audioDownloadServiceProvider);
    ref.onDispose(() => unawaited(service.cancel()));
    return const AudioDownloadState();
  }

  Future<void> refreshAvailability() async {
    try {
      final availability = await ref
          .read(audioDownloadServiceProvider)
          .checkAvailability();
      if (!ref.mounted) return;
      state = AudioDownloadState(
        availability: availability,
        preview: state.preview,
        playlistPreview: state.playlistPreview,
        status: state.status,
        error: availability.error,
        result: state.result,
        batchProgress: state.batchProgress,
        batchResult: state.batchResult,
        isBusy: state.isBusy,
      );
    } catch (error) {
      if (ref.mounted) {
        state = AudioDownloadState(error: '$error');
      }
    }
  }

  Future<void> analyze(String url) async {
    if (state.isBusy) return;
    state = AudioDownloadState(
      availability: state.availability,
      status: DownloadStatus.analyzing,
      isBusy: true,
    );
    try {
      final service = ref.read(audioDownloadServiceProvider);
      final parsed = YoutubeUrl.parse(url);
      final playlistPreview = parsed?.isPlaylist == true
          ? await service.analyzePlaylist(url)
          : null;
      SourcePreview? preview;
      if (parsed?.uri.path != '/playlist') {
        try {
          preview = await service.analyzeUrl(url);
        } catch (_) {
          if (playlistPreview == null) rethrow;
        }
      }
      if (!ref.mounted) return;
      state = AudioDownloadState(
        availability: state.availability,
        preview: preview,
        playlistPreview: playlistPreview,
      );
    } catch (error) {
      if (ref.mounted) {
        state = AudioDownloadState(
          availability: state.availability,
          status: DownloadStatus.failed,
          error: friendlyDownloadError('$error'),
        );
      }
    }
  }

  Future<AudioImportResult?> start(String url) async {
    if (state.isBusy) return null;
    state = AudioDownloadState(
      availability: state.availability,
      preview: state.preview,
      playlistPreview: state.playlistPreview,
      status: DownloadStatus.analyzing,
      isBusy: true,
    );
    try {
      final result = await ref
          .read(audioDownloadServiceProvider)
          .download(
            url,
            onProgress: (event) {
              if (!ref.mounted) return;
              state = AudioDownloadState(
                availability: state.availability,
                preview: state.preview,
                playlistPreview: state.playlistPreview,
                status: event.status == DownloadStatus.completed
                    ? DownloadStatus.processing
                    : event.status,
                downloadedBytes: event.downloadedBytes ?? state.downloadedBytes,
                totalBytes: event.totalBytes ?? state.totalBytes,
                error: event.error,
                isBusy: true,
              );
            },
          );
      if (ref.mounted) {
        state = AudioDownloadState(
          availability: state.availability,
          preview: state.preview,
          playlistPreview: state.playlistPreview,
          status: result.status == AudioImportStatus.canceled
              ? DownloadStatus.canceled
              : DownloadStatus.completed,
          result: result,
        );
      }
      return result;
    } catch (error) {
      if (ref.mounted) {
        state = AudioDownloadState(
          availability: state.availability,
          preview: state.preview,
          playlistPreview: state.playlistPreview,
          status: DownloadStatus.failed,
          error: friendlyDownloadError('$error'),
        );
      }
      return null;
    }
  }

  Future<DownloadBatchResult?> startPlaylist(PlaylistPreview playlist) async {
    if (state.isBusy) return null;
    state = AudioDownloadState(
      availability: state.availability,
      preview: state.preview,
      playlistPreview: playlist,
      status: DownloadStatus.analyzing,
      isBusy: true,
    );
    try {
      final result = await ref
          .read(audioDownloadServiceProvider)
          .downloadPlaylist(
            playlist,
            onProgress: (progress) {
              if (!ref.mounted) return;
              state = AudioDownloadState(
                availability: state.availability,
                preview: state.preview,
                playlistPreview: playlist,
                status: progress.event.status == DownloadStatus.completed
                    ? DownloadStatus.processing
                    : progress.event.status,
                downloadedBytes: progress.event.downloadedBytes,
                totalBytes: progress.event.totalBytes,
                batchProgress: progress,
                isBusy: true,
              );
            },
          );
      if (ref.mounted) {
        state = AudioDownloadState(
          availability: state.availability,
          preview: state.preview,
          playlistPreview: playlist,
          status: result.canceled
              ? DownloadStatus.canceled
              : DownloadStatus.completed,
          batchResult: result,
        );
      }
      return result;
    } catch (error) {
      if (ref.mounted) {
        state = AudioDownloadState(
          availability: state.availability,
          preview: state.preview,
          playlistPreview: playlist,
          status: DownloadStatus.failed,
          error: friendlyDownloadError('$error'),
        );
      }
      return null;
    }
  }

  Future<void> cancel() async {
    if (!state.isBusy) return;
    await ref.read(audioDownloadServiceProvider).cancel();
  }
}

class _UnavailableAudioDownloadBackend implements AudioDownloadBackend {
  const _UnavailableAudioDownloadBackend();
  @override
  Future<DownloadAvailability> checkAvailability() async =>
      const DownloadAvailability(
        available: false,
        error: 'Descargas no disponibles en esta plataforma.',
      );
  @override
  Future<SourcePreview> analyzeUrl(String url) => Future.error(
    UnsupportedError('Descargas no disponibles en esta plataforma.'),
  );
  @override
  Future<PlaylistPreview> analyzePlaylist(String url) => Future.error(
    UnsupportedError('Descargas no disponibles en esta plataforma.'),
  );
  @override
  Stream<DownloadEvent> downloadAudio(DownloadRequest request) => Stream.value(
    const DownloadEvent(
      status: DownloadStatus.failed,
      error: 'Descargas no disponibles en esta plataforma.',
    ),
  );
  @override
  Future<void> cancel() async {}
}
