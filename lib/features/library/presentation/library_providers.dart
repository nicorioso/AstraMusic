import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
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
import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/library_grouping_repository.dart';
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

const libraryTrackWindowSize = 100;

final libraryTrackLimitProvider = NotifierProvider<LibraryTrackLimit, int>(
  LibraryTrackLimit.new,
);

final libraryTracksProvider = StreamProvider<LibraryTrackWindow>((ref) {
  final repository = ref.watch(trackRepositoryProvider);
  final query = ref.watch(librarySearchQueryProvider).trim();
  final limit = ref.watch(libraryTrackLimitProvider);
  final tracks = repository is PaginatedTrackRepository
      ? repository.watchPage(limit: limit + 1, query: query)
      : query.isEmpty
      ? repository.watchAll()
      : repository.watchSearch(query);
  return tracks.map((items) {
    final hasMore =
        repository is PaginatedTrackRepository && items.length > limit;
    final visible = hasMore ? items.take(limit).toList(growable: false) : items;
    PerformanceDiagnostics.instance.recordLibraryLoaded(visible.length);
    return LibraryTrackWindow(items: visible, hasMore: hasMore);
  });
});

final allLibraryTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).watchAll().map((items) {
    PerformanceDiagnostics.instance.recordLibraryLoaded(items.length);
    return items;
  });
});

final favoriteTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).watchFavorites();
});

final libraryGroupingRepositoryProvider = Provider<LibraryGroupingRepository>((ref) {
  final repository = ref.watch(trackRepositoryProvider);
  if (repository is! LibraryGroupingRepository) {
    throw UnsupportedError('El repositorio no expone agrupaciones de biblioteca.');
  }
  return repository as LibraryGroupingRepository;
});

final artistsProvider = StreamProvider<List<ArtistGroup>>((ref) =>
    ref.watch(libraryGroupingRepositoryProvider).watchArtists());
final albumsProvider = StreamProvider<List<AlbumGroup>>((ref) =>
    ref.watch(libraryGroupingRepositoryProvider).watchAlbums());
final genresProvider = StreamProvider<List<GenreGroup>>((ref) =>
    ref.watch(libraryGroupingRepositoryProvider).watchGenres());
final folderGroupsProvider = StreamProvider<List<FolderGroup>>((ref) =>
    ref.watch(libraryGroupingRepositoryProvider).watchFolders());

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
      ref.read(libraryTrackLimitProvider.notifier).reset();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      state = query;
      ref.read(libraryTrackLimitProvider.notifier).reset();
    });
  }
}

final class LibraryTrackLimit extends Notifier<int> {
  @override
  int build() => libraryTrackWindowSize;

  void loadMore() => state += libraryTrackWindowSize;

  void reset() => state = libraryTrackWindowSize;
}

final class LibraryTrackWindow {
  const LibraryTrackWindow({required this.items, required this.hasMore});

  final List<Track> items;
  final bool hasMore;
}
