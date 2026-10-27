import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_list_query.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inicio solicita una ventana reciente acotada al repositorio', () async {
    final repository = _RecordingRepository();
    final container = ProviderContainer(
      overrides: [trackRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(homeRecentTracksProvider);

    expect(repository.requestedLimit, homeRecentTrackLimit);
    expect(repository.requestedQuery?.sort, TrackSort.dateAdded);
    expect(repository.watchAllCalls, 0);
  });
}

final class _RecordingRepository implements FilteredTrackRepository {
  int? requestedLimit;
  TrackListQuery? requestedQuery;
  int watchAllCalls = 0;

  @override
  Stream<List<Track>> watchFilteredPage({
    required int limit,
    int offset = 0,
    TrackListQuery query = const TrackListQuery(),
  }) {
    requestedLimit = limit;
    requestedQuery = query;
    return Stream.value(const []);
  }

  @override
  Stream<List<Track>> watchAll() {
    watchAllCalls++;
    return Stream.value(const []);
  }

  @override
  Stream<List<Track>> watchSearch(String query) => Stream.value(const []);

  @override
  Stream<List<Track>> watchFavorites() => Stream.value(const []);

  @override
  Future<int> count() async => 0;

  @override
  Future<void> clearLibrary() async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<void> deleteByUris(Set<String> uris) async {}

  @override
  Future<Set<String>> excludedUris() async => const {};

  @override
  Future<void> excludeAndDelete(Track track) async {}

  @override
  Future<Track?> getById(int id) async => null;

  @override
  Future<void> markUnavailable(Set<String> uris) async {}

  @override
  Future<void> restoreExcluded(Set<String> uris) async {}

  @override
  Future<void> setAvailability(Map<String, bool> availability) async {}

  @override
  Future<void> setFavorite(int id, bool favorite) async {}

  @override
  Future<void> upsertAll(List<Track> tracks) async {}
}
