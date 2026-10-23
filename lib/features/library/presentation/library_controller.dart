import 'dart:async';

import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/media_library_permission.dart';
import 'package:astramusic/features/library/application/library_sync_service.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryViewState>(
      LibraryController.new,
    );

class LibraryViewState {
  const LibraryViewState({
    this.isBusy = false,
    this.isScanning = false,
    this.foundCount = 0,
    this.scanErrorCount = 0,
    this.message,
    this.offerSettings = false,
  });

  final bool isBusy;
  final bool isScanning;
  final int foundCount;
  final int scanErrorCount;
  final String? message;
  final bool offerSettings;

  bool get actionsDisabled => isBusy || isScanning;

  LibraryViewState copyWith({
    bool? isBusy,
    bool? isScanning,
    int? foundCount,
    int? scanErrorCount,
    Object? message = _notProvided,
    bool? offerSettings,
  }) {
    return LibraryViewState(
      isBusy: isBusy ?? this.isBusy,
      isScanning: isScanning ?? this.isScanning,
      foundCount: foundCount ?? this.foundCount,
      scanErrorCount: scanErrorCount ?? this.scanErrorCount,
      message: message == _notProvided ? this.message : message as String?,
      offerSettings: offerSettings ?? this.offerSettings,
    );
  }

  static const _notProvided = Object();
}

final class LibraryController extends Notifier<LibraryViewState> {
  LibraryScanTask? _activeScan;
  bool _cancelRequested = false;

  @override
  LibraryViewState build() {
    ref.onDispose(() {
      final scan = _activeScan;
      if (scan != null) unawaited(scan.cancel());
    });
    return const LibraryViewState();
  }

  Future<void> startScan() async {
    if (state.actionsDisabled) return;
    final isAndroid = ref.read(isAndroidPlatformProvider);

    if (isAndroid) {
      if (!await _requestAndroidPermission()) return;
      await _runScanOperation(() async {
        return _scanOne(scope: const AndroidMediaStoreScanScope());
      });
      return;
    }

    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      final path = await ref.read(libraryFolderPickerProvider).pickFolder();
      if (path == null || !ref.mounted) return;
      final folder = await ref.read(libraryFoldersRepositoryProvider).add(path);
      if (!ref.mounted) return;
      state = state.copyWith(isBusy: false);
      await _runScanOperation(() async {
        final summary = await _scanOne(
          rootPath: folder.path,
          scope: DesktopFolderScanScope(folder.path),
        );
        await ref
            .read(libraryFoldersRepositoryProvider)
            .markScanned(folder.id, DateTime.now());
        return summary;
      });
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted && !state.isScanning) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  Future<void> updateLibrary() async {
    if (state.actionsDisabled) return;
    final isAndroid = ref.read(isAndroidPlatformProvider);

    if (isAndroid) {
      if (!await _requestAndroidPermission()) return;
      await _runScanOperation(() async {
        return _scanOne(scope: const AndroidMediaStoreScanScope());
      });
      return;
    }

    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      final folders = await ref
          .read(libraryFoldersRepositoryProvider)
          .watchAll()
          .first;
      if (!ref.mounted) return;
      if (folders.isEmpty) {
        state = state.copyWith(message: 'No hay carpetas de música guardadas.');
        return;
      }

      state = state.copyWith(isBusy: false);
      await _runScanOperation(() async {
        var total = const LibrarySyncSummary();
        var foundOffset = 0;
        for (final folder in folders) {
          if (_cancelRequested) throw const _ScanWasCancelled();
          final summary = await _scanOne(
            rootPath: folder.path,
            scope: DesktopFolderScanScope(folder.path),
            foundOffset: foundOffset,
          );
          total += summary;
          foundOffset = state.foundCount;
          await ref
              .read(libraryFoldersRepositoryProvider)
              .markScanned(folder.id, DateTime.now());
        }
        return total;
      });
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted && !state.isScanning) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  Future<void> cancelScan() async {
    if (!state.isScanning) return;
    _cancelRequested = true;
    await _activeScan?.cancel();
  }

  Future<void> removeFolder(LibraryFolder folder) async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      await ref
          .read(librarySyncServiceProvider)
          .deleteFolderTracks(folder.path);
      await ref.read(libraryFoldersRepositoryProvider).remove(folder.id);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> openAppSettings() async {
    await ref.read(mediaLibraryPermissionProvider).openSettings();
  }

  Future<void> addFiles() async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);

    try {
      final files = await ref.read(audioFilePickerProvider).pickAudioFiles();
      if (files.isEmpty || !ref.mounted) return;

      final addedAt = DateTime.now();
      final tracks = files
          .map(
            (file) =>
                Track(uri: file.path, title: file.title, dateAdded: addedAt),
          )
          .toList(growable: false);
      await ref.read(trackRepositoryProvider).upsertAll(tracks);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> playVisibleQueue(
    List<Track> tracks, {
    required int startIndex,
    bool shuffle = false,
  }) async {
    if (state.actionsDisabled) return;
    await ref
        .read(playerControllerProvider.notifier)
        .playQueue(tracks, startIndex: startIndex, shuffle: shuffle);
  }

  Future<void> playAll(List<Track> tracks, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    await playVisibleQueue(tracks, startIndex: 0, shuffle: shuffle);
  }

  Future<void> playNext(Track track) async {
    await ref.read(playerControllerProvider.notifier).playNext(track);
    if (ref.mounted) {
      state = state.copyWith(message: 'Se reproducirá a continuación.');
    }
  }

  Future<void> addToQueue(Track track) async {
    await ref.read(playerControllerProvider.notifier).addToQueue(track);
    if (ref.mounted) {
      state = state.copyWith(message: 'Canción añadida a la cola.');
    }
  }

  Future<void> loadDebugTracks() async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);

    try {
      final addedAt = DateTime.now();
      final tracks = List.generate(
        50,
        (index) => Track(
          uri: 'file:///astramusic-debug/track-${index + 1}.mp3',
          title: 'Canción de prueba ${index + 1}',
          artist: 'Artista ${(index % 10) + 1}',
          album: 'Álbum ${(index % 5) + 1}',
          duration: Duration(seconds: 120 + index),
          dateAdded: addedAt,
        ),
      );
      await ref.read(trackRepositoryProvider).upsertAll(tracks);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> deleteAll() async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);

    try {
      await ref.read(trackRepositoryProvider).deleteAll();
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  void clearMessage() {
    if (state.message != null || state.offerSettings) {
      state = state.copyWith(message: null, offerSettings: false);
    }
  }

  Future<bool> _requestAndroidPermission() async {
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      final permission = await ref
          .read(mediaLibraryPermissionProvider)
          .request();
      if (!ref.mounted) return false;
      switch (permission) {
        case MediaLibraryPermissionStatus.granted:
          return true;
        case MediaLibraryPermissionStatus.denied:
          state = state.copyWith(
            message: 'Se necesita acceso al audio para escanear la música del dispositivo.',
            offerSettings: true,
          );
        case MediaLibraryPermissionStatus.permanentlyDenied:
          state = state.copyWith(
            message: 'El permiso de audio está bloqueado. Habilítalo en los ajustes de la app.',
            offerSettings: true,
          );
      }
      return false;
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
      return false;
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> _runScanOperation(
    Future<LibrarySyncSummary> Function() operation,
  ) async {
    _cancelRequested = false;
    state = state.copyWith(
      isBusy: false,
      isScanning: true,
      foundCount: 0,
      scanErrorCount: 0,
      message: null,
      offerSettings: false,
    );

    try {
      final summary = await operation();
      if (ref.mounted) state = state.copyWith(message: summary.message);
    } on _ScanWasCancelled {
      if (ref.mounted) state = state.copyWith(message: 'Escaneo cancelado.');
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      _activeScan = null;
      _cancelRequested = false;
      if (ref.mounted) {
        state = state.copyWith(isScanning: false, isBusy: false);
      }
    }
  }

  Future<LibrarySyncSummary> _scanOne({
    required LibraryScanScope scope,
    String? rootPath,
    int foundOffset = 0,
  }) async {
    final task = await ref
        .read(libraryScannerProvider)
        .startScan(rootPath: rootPath);
    _activeScan = task;
    ScanCompleted? completed;

    await for (final event in task.events) {
      switch (event) {
        case ScanProgress(:final foundCount, :final errorCount):
          if (ref.mounted) {
            state = state.copyWith(
              foundCount: foundOffset + foundCount,
              scanErrorCount: errorCount,
            );
          }
        case ScanCompleted():
          completed = event;
          if (ref.mounted) {
            state = state.copyWith(
              foundCount: foundOffset + event.tracks.length,
              scanErrorCount: event.errorCount,
            );
          }
        case ScanCancelled():
          throw const _ScanWasCancelled();
      }
    }

    _activeScan = null;
    if (_cancelRequested || completed == null) {
      throw const _ScanWasCancelled();
    }
    return ref
        .read(librarySyncServiceProvider)
        .synchronize(
          scannedTracks: completed.tracks,
          scope: scope,
          scanErrorCount: completed.errorCount,
        );
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.isEmpty ? 'Ocurrió un error inesperado.' : message;
  }
}

final class _ScanWasCancelled implements Exception {
  const _ScanWasCancelled();
}
