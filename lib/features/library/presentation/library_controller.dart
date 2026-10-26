import 'dart:async';
import 'dart:isolate';

import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/platform/media_library_permission.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/application/library_sync_service.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/scan_state_machine.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryViewState>(
      LibraryController.new,
    );

class LibraryViewState {
  const LibraryViewState({
    this.isBusy = false,
    this.scanPhase = ScanPhase.idle,
    this.foundCount = 0,
    this.unchangedCount = 0,
    this.scanErrorCount = 0,
    this.message,
    this.offerSettings = false,
  });

  final bool isBusy;
  final ScanPhase scanPhase;
  final int foundCount;
  final int unchangedCount;
  final int scanErrorCount;
  final String? message;
  final bool offerSettings;

  bool get isScanning => scanPhase == ScanPhase.scanning;
  bool get isCancelling => scanPhase == ScanPhase.cancelling;
  bool get scanActive => scanPhase != ScanPhase.idle;
  bool get actionsDisabled => isBusy || scanActive;

  LibraryViewState copyWith({
    bool? isBusy,
    ScanPhase? scanPhase,
    int? foundCount,
    int? unchangedCount,
    int? scanErrorCount,
    Object? message = _notProvided,
    bool? offerSettings,
  }) {
    return LibraryViewState(
      isBusy: isBusy ?? this.isBusy,
      scanPhase: scanPhase ?? this.scanPhase,
      foundCount: foundCount ?? this.foundCount,
      unchangedCount: unchangedCount ?? this.unchangedCount,
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
  final ScanStateMachine _scanStateMachine = ScanStateMachine();

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
        var unchangedOffset = 0;
        var errorOffset = 0;
        for (final folder in folders) {
          if (_cancelRequested) throw const _ScanWasCancelled();
          final summary = await _scanOne(
            rootPath: folder.path,
            scope: DesktopFolderScanScope(folder.path),
            foundOffset: foundOffset,
            unchangedOffset: unchangedOffset,
            errorOffset: errorOffset,
          );
          total += summary;
          foundOffset = state.foundCount;
          unchangedOffset = state.unchangedCount;
          errorOffset = state.scanErrorCount;
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
    if (!_scanStateMachine.requestCancellation()) return;
    _cancelRequested = true;
    state = state.copyWith(scanPhase: ScanPhase.cancelling);
    final scan = _activeScan;
    if (scan == null) return;
    try {
      await scan.cancel();
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    }
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
      final hasLocalFiles = files.any(
        (file) => localFilePathFromLocation(file.path) != null,
      );
      final cacheDirectory = hasLocalFiles
          ? await getApplicationCacheDirectory()
          : null;
      final tracks = <Track>[];
      var tagErrors = 0;
      for (final file in files) {
        final localPath = localFilePathFromLocation(file.path);
        LocalAudioFileInfo? info;
        if (localPath != null) {
          try {
            final readInfo = await Isolate.run(
              () => readLocalAudioFileWithArtwork(
                localPath,
                cacheDirectory!.path,
              ),
            );
            info = readInfo;
            if (readInfo.hadTagError) tagErrors++;
          } catch (_) {
            tagErrors++;
          }
        }
        tracks.add(
          Track(
            uri: file.path,
            title: info?.tags.title ?? file.title,
            artist: info?.tags.artist,
            album: info?.tags.album,
            duration: switch (info?.tags.durationMs) {
              final int milliseconds => Duration(milliseconds: milliseconds),
              null => null,
            },
            trackNumber: info?.tags.trackNumber,
            year: info?.tags.year,
            fileSize: info?.fileSize,
            dateAdded: addedAt,
            dateModified: info?.dateModified,
            artworkPath: info?.artworkPath,
          ),
        );
      }
      final repository = ref.read(trackRepositoryProvider);
      await repository.restoreExcluded(
        tracks.map((track) => track.uri).toSet(),
      );
      await repository.upsertAll(tracks);
      if (tagErrors > 0 && ref.mounted) {
        state = state.copyWith(
          message:
              '$tagErrors archivos se añadieron usando su nombre porque '
              'no fue posible leer sus etiquetas.',
        );
      }
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

  Future<void> playPlaylist(
    int playlistId,
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    await playVisibleQueue(tracks, startIndex: startIndex, shuffle: shuffle);
    await ref.read(playlistRepositoryProvider).markPlayed(playlistId);
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

  Future<void> deleteTrack(Track track) async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      final repository = ref.read(trackRepositoryProvider);
      final tracks = await repository.watchAll().first;
      final key = artworkCacheKey(
        artist: track.artist,
        album: track.album,
        uri: track.uri,
      );
      final artworkIsShared = tracks.any(
        (candidate) =>
            candidate.uri != track.uri &&
            artworkCacheKey(
                  artist: candidate.artist,
                  album: candidate.album,
                  uri: candidate.uri,
                ) ==
                key,
      );
      await ref
          .read(playerControllerProvider.notifier)
          .removeTrackFromQueue(track.uri);
      await repository.excludeAndDelete(track);
      if (!artworkIsShared) {
        await ref.read(artworkCacheProvider).deleteByKey(key);
      }
      if (ref.mounted) {
        state = state.copyWith(message: 'Eliminada de la biblioteca');
      }
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
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

  Future<void> clearLibrary() async {
    if (state.actionsDisabled) return;
    state = state.copyWith(isBusy: true, message: null, offerSettings: false);
    try {
      final player = ref.read(playerControllerProvider.notifier);
      await player.stopAndClearQueue();
      await ref.read(trackRepositoryProvider).clearLibrary();
      await ref.read(artworkCacheProvider).clear();
      if (ref.mounted) state = state.copyWith(message: 'Biblioteca vaciada');
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

  void showUnavailableMessage() {
    state = state.copyWith(message: 'No disponible');
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
    if (!_scanStateMachine.start()) return;
    _cancelRequested = false;
    state = state.copyWith(
      isBusy: false,
      scanPhase: ScanPhase.scanning,
      foundCount: 0,
      unchangedCount: 0,
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
      _scanStateMachine.finish();
      if (ref.mounted) {
        state = state.copyWith(scanPhase: ScanPhase.idle, isBusy: false);
      }
    }
  }

  Future<LibrarySyncSummary> _scanOne({
    required LibraryScanScope scope,
    String? rootPath,
    int foundOffset = 0,
    int unchangedOffset = 0,
    int errorOffset = 0,
  }) async {
    final knownFiles = <String, KnownFileStats>{};
    if (scope is DesktopFolderScanScope) {
      final existing = await ref.read(trackRepositoryProvider).watchAll().first;
      for (final track in existing) {
        if (track.fileSize != null && track.dateModified != null) {
          knownFiles[track.uri] = KnownFileStats(
            fileSize: track.fileSize,
            dateModified: track.dateModified,
          );
        }
      }
    }
    final task = await ref
        .read(libraryScannerProvider)
        .startScan(rootPath: rootPath, knownFiles: knownFiles);
    final syncSession = await ref
        .read(librarySyncServiceProvider)
        .startIncremental(scope: scope);
    _activeScan = task;
    if (_cancelRequested) unawaited(task.cancel());
    ScanCompleted? completed;
    var scannedCount = 0;
    var scanWasCancelled = false;

    await for (final event in task.events) {
      switch (event) {
        case ScanProgress(
          :final foundCount,
          :final errorCount,
          :final unchangedCount,
        ):
          if (ref.mounted) {
            state = state.copyWith(
              foundCount: foundOffset + foundCount,
              unchangedCount: unchangedOffset + unchangedCount,
              scanErrorCount: errorOffset + errorCount,
            );
          }
        case ScanBatch(:final tracks):
          scannedCount += tracks.length;
          await syncSession.addBatch(tracks);
        case ScanCompleted():
          completed = event;
          if (event.tracks.isNotEmpty) {
            scannedCount += event.tracks.length;
            await syncSession.addBatch(event.tracks);
          }
          if (ref.mounted) {
            state = state.copyWith(
              foundCount: foundOffset + scannedCount,
              unchangedCount: unchangedOffset + event.unchangedCount,
              scanErrorCount: errorOffset + event.errorCount,
            );
          }
        case ScanCancelled():
          scanWasCancelled = true;
      }
    }

    _activeScan = null;
    if (_cancelRequested || scanWasCancelled || completed == null) {
      throw const _ScanWasCancelled();
    }
    return syncSession.finish(scanErrorCount: completed.errorCount);
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.isEmpty ? 'Ocurrió un error inesperado.' : message;
  }
}

final class _ScanWasCancelled implements Exception {
  const _ScanWasCancelled();
}
