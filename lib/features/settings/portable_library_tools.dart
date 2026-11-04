import 'dart:convert';
import 'dart:io';

import 'package:astramusic/core/db/library_backup_service.dart';
import 'package:astramusic/core/platform/portable_file_picker.dart';
import 'package:astramusic/features/library/application/missing_tracks_service.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/playlists/application/m3u_service.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final portableFilePickerProvider = Provider<PortableFilePicker>((ref) => const SystemPortableFilePicker());
final m3uServiceProvider = Provider<M3uService>((ref) => M3uService(
  ref.watch(playlistRepositoryProvider), DriftTrackRepository(ref.watch(appDatabaseProvider)),
));
final backupServiceProvider = Provider<LibraryBackupService>((ref) => LibraryBackupService(ref.watch(appDatabaseProvider)));
final missingTracksServiceProvider = Provider<MissingTracksService>((ref) => MissingTracksService(ref.watch(appDatabaseProvider)));

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
    final picker = ref.read(portableFilePickerProvider);
    final tracks = await ref.read(playlistRepositoryProvider).watchTracks(id).first;
    final content = M3uService.encode(tracks);
    await picker.save('$name.m3u8', utf8.encode(content), 'audio/x-mpegurl');
    return true;
  }

  Future<({int added, int missing})?> importPlaylist(String name) async {
    final selected = await ref.read(portableFilePickerProvider).pickFile(['m3u', 'm3u8']);
    if (selected == null) return null;
    final result = await ref.read(m3uServiceProvider).import(File(selected), name: name);
    ref.invalidate(playlistsProvider);
    return (added: result.added, missing: result.missing);
  }

  Future<bool> createBackup() async {
    final temp = File('${(await getTemporaryDirectory()).path}/astramusic-backup-${DateTime.now().microsecondsSinceEpoch}.gz');
    try {
      await ref.read(backupServiceProvider).export(temp);
      await ref.read(portableFilePickerProvider).save('astramusic-backup.gz', await temp.readAsBytes(), 'application/gzip');
      return true;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<bool> restoreBackup() async {
    final selected = await ref.read(portableFilePickerProvider).pickFile(['gz']);
    if (selected == null) return false;
    await ref.read(playerControllerProvider.notifier).stopAndClearQueue();
    await ref.read(backupServiceProvider).restore(File(selected));
    reloadAfterRestore(ref);
    return true;
  }

  Future<RepairResult?> repair() async {
    final selected = await ref.read(portableFilePickerProvider).pickFolder();
    if (selected == null) return null;
    final result = await ref.read(missingTracksServiceProvider).repair(Directory(selected));
    ref.invalidate(libraryTracksProvider);
    return result;
  }
}
