import 'dart:async';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return DriftTrackRepository(ref.watch(appDatabaseProvider));
});

final librarySearchQueryProvider = NotifierProvider<LibrarySearchQuery, String>(
  LibrarySearchQuery.new,
);

final libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  final repository = ref.watch(trackRepositoryProvider);
  final query = ref.watch(librarySearchQueryProvider).trim();
  return query.isEmpty ? repository.watchAll() : repository.watchSearch(query);
});

final class LibrarySearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }
}
