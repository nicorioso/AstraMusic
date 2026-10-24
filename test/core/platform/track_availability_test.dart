import 'package:astramusic/core/platform/track_availability.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marca archivos ausentes y los reactiva cuando reaparecen', () async {
    final repository = _AvailabilityRepository([
      Track(
        id: 1,
        uri: 'file:///music/song.mp3',
        title: 'Canción',
        dateAdded: DateTime(2026),
      ),
      Track(
        id: 2,
        uri: 'content://media/audio/2',
        title: 'Android',
        dateAdded: DateTime(2026),
      ),
    ]);
    final checker = _MutableChecker(false);
    final service = TrackAvailabilityService(repository, checker: checker);

    await service.refresh();
    checker.available = true;
    await service.refresh();

    expect(repository.updates, [
      {'file:///music/song.mp3': false},
      {'file:///music/song.mp3': true},
    ]);
    expect(checker.checkedUris, isNot(contains('content://media/audio/2')));
  });
}

final class _MutableChecker implements TrackAvailabilityChecker {
  _MutableChecker(this.available);

  bool available;
  final List<String> checkedUris = [];

  @override
  Future<Map<String, bool>> checkAll(Iterable<String> uris) async {
    checkedUris.addAll(uris);
    return {for (final uri in uris) uri: available};
  }

  @override
  Future<bool> exists(String uri) async => available;
}

final class _AvailabilityRepository implements TrackRepository {
  _AvailabilityRepository(this.tracks);

  final List<Track> tracks;
  final List<Map<String, bool>> updates = [];

  @override
  Future<void> setAvailability(Map<String, bool> availability) async {
    updates.add(Map.of(availability));
  }

  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);

  @override
  Stream<List<Track>> watchSearch(String query) => watchAll();

  @override
  Future<void> clearLibrary() async {}

  @override
  Future<int> count() async => tracks.length;

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
  Future<void> upsertAll(List<Track> tracks) async {}
}
