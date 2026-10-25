import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/platform/android_media_store_library_scanner.dart';
import 'package:astramusic/core/platform/artwork_cache.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/platform/desktop_library_scanner.dart';
import 'package:astramusic/core/platform/library_folder_picker.dart';
import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/media_library_permission.dart';
import 'package:astramusic/features/library/application/library_sync_service.dart';
import 'package:astramusic/features/library/application/artwork_backfill_service.dart';
import 'package:astramusic/features/library/data/drift_library_folders_repository.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/library_folders_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return DriftTrackRepository(ref.watch(appDatabaseProvider));
});

final libraryFoldersRepositoryProvider = Provider<LibraryFoldersRepository>((
  ref,
) {
  return DriftLibraryFoldersRepository(ref.watch(appDatabaseProvider));
});

final libraryFoldersProvider = StreamProvider<List<LibraryFolder>>((ref) {
  return ref.watch(libraryFoldersRepositoryProvider).watchAll();
});

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  return Platform.isAndroid
      ? AndroidMediaStoreLibraryScanner()
      : const DesktopLibraryScanner();
});

final libraryFolderPickerProvider = Provider<LibraryFolderPicker>((ref) {
  return const SystemLibraryFolderPicker();
});

final mediaLibraryPermissionProvider = Provider<MediaLibraryPermission>((ref) {
  return const SystemMediaLibraryPermission();
});

final librarySyncServiceProvider = Provider<LibrarySyncService>((ref) {
  return LibrarySyncService(ref.watch(trackRepositoryProvider));
});

final isAndroidPlatformProvider = Provider<bool>((ref) => Platform.isAndroid);

final artworkProviderProvider = Provider<ArtworkProvider>((ref) {
  return CachedArtworkProvider();
});

final artworkCacheProvider = Provider<ArtworkCache>((ref) {
  return const FileArtworkCache();
});

final artworkBackfillServiceProvider = Provider<ArtworkBackfill>((ref) {
  return ArtworkBackfillService(
    ref.watch(trackRepositoryProvider),
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
  );
});

final librarySearchQueryProvider = NotifierProvider<LibrarySearchQuery, String>(
  LibrarySearchQuery.new,
);

final libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  final repository = ref.watch(trackRepositoryProvider);
  final query = ref.watch(librarySearchQueryProvider).trim();
  return query.isEmpty ? repository.watchAll() : repository.watchSearch(query);
});

final allLibraryTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).watchAll();
});

final favoriteTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).watchFavorites();
});

final class LibrarySearchQuery extends Notifier<String> {
  Timer? _debounce;

  @override
  String build() {
    ref.onDispose(() => _debounce?.cancel());
    return '';
  }

  void update(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      state = '';
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      state = query;
    });
  }
}
