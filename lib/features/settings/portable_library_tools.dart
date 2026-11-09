import 'dart:io';

import 'package:astramusic/core/db/library_backup_service.dart';
import 'package:astramusic/core/platform/portable_file_picker.dart';
import 'package:astramusic/features/library/application/missing_tracks_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/playlists/application/smart_package_service.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final portableFilePickerProvider = Provider<PortableFilePicker>(
  (ref) => const SystemPortableFilePicker(),
);
final smartPackageServiceProvider = FutureProvider<SmartPackageService>(
  (ref) async => SmartPackageService(
    ref.watch(playlistRepositoryProvider),
    DriftTrackRepository(ref.watch(appDatabaseProvider)),
    Directory(
      '${(await getApplicationSupportDirectory()).path}/imported_audio',
    ),
  ),
);
final backupServiceProvider = Provider<LibraryBackupService>(
  (ref) => LibraryBackupService(ref.watch(appDatabaseProvider)),
);
final missingTracksServiceProvider = Provider<MissingTracksService>(
  (ref) => MissingTracksService(ref.watch(appDatabaseProvider)),
);

/// Invalida vistas y controladores sin cerrar la conexión Drift activa.
void reloadAfterRestore(WidgetRef ref) {
  ref.invalidate(trackRepositoryProvider);
  ref.invalidate(smartPlaylistRepositoryProvider);
  ref.invalidate(libraryFoldersRepositoryProvider);
  ref.invalidate(playlistRepositoryProvider);
  ref.invalidate(libraryTracksProvider);
  ref.invalidate(homeRecentTracksProvider);
  ref.invalidate(favoriteTracksProvider);
  ref.invalidate(libraryFoldersProvider);
  ref.invalidate(playlistsProvider);
  ref.invalidate(recentPlaylistsProvider);
  ref.invalidate(playerControllerProvider);
}

final class PortableLibraryActions {
  PortableLibraryActions(this.ref);
  final WidgetRef ref;

  Future<bool> exportPlaylist(int id, String name) async {
    final temp = File(
      '${(await getTemporaryDirectory()).path}/astramusic-${DateTime.now().microsecondsSinceEpoch}.amplaylist',
    );
    try {
      await (await ref.read(smartPackageServiceProvider.future))
          .export(id, temp);
      return await ref
          .read(portableFilePickerProvider)
          .save(
            '$name.amplaylist',
            await temp.readAsBytes(),
            'application/zip',
          );
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<int?> importPlaylist() async {
    final selected = await ref.read(portableFilePickerProvider).pickFile([
      'amplaylist',
    ]);
    if (selected == null) return null;
    final result = await (await ref.read(smartPackageServiceProvider.future))
        .import(File(selected));
    ref.invalidate(playlistsProvider);
    ref.invalidate(libraryTracksProvider);
    return result.added;
  }

  Future<bool> createBackup() async {
    final temp = File(
      '${(await getTemporaryDirectory()).path}/astramusic-backup-${DateTime.now().microsecondsSinceEpoch}.gz',
    );
    try {
      await ref.read(backupServiceProvider).export(temp);
      return await ref
          .read(portableFilePickerProvider)
          .save(
            'astramusic-backup.gz',
            await temp.readAsBytes(),
            'application/gzip',
          );
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<bool> restoreBackup() async {
    final selected = await ref.read(portableFilePickerProvider).pickFile([
      'gz',
    ]);
    if (selected == null) return false;
    await ref.read(playerControllerProvider.notifier).stopAndClearQueue();
    await ref.read(backupServiceProvider).restore(File(selected));
    reloadAfterRestore(ref);
    return true;
  }

  Future<RepairResult?> repair() async {
    final selected = await ref.read(portableFilePickerProvider).pickFolder();
    if (selected == null) return null;
    final result = await ref
        .read(missingTracksServiceProvider)
        .repair(Directory(selected));
    ref.invalidate(libraryTracksProvider);
    return result;
  }
}
