import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:astramusic/features/library/application/artwork_backfill_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rellena artworkPath ausente en lotes y solo una vez', () async {
    final repository = _Repository([
      for (var index = 0; index < 5; index++)
        Track(
          uri: '/music/$index.mp3',
          title: '$index',
          dateAdded: DateTime(2026),
        ),
      Track(
        uri: 'content://media/audio/8',
        title: 'MediaStore',
        dateAdded: DateTime(2026),
      ),
    ]);
    var extractions = 0;
    final service = ArtworkBackfillService(
      repository,
      cacheDirectory: () async => '/cache',
      batchSize: 2,
      useIsolate: false,
      extractor: (filePath, cacheDirectory) {
        extractions++;
        return LocalAudioFileInfo(
          tags: AudioTags(title: filePath),
          fileSize: 1,
          dateModified: DateTime(2026),
          hadTagError: false,
          artworkPath: '$cacheDirectory/${filePath.split('/').last}.jpg',
        );
      },
    );

    await service.runOnce();
    await service.runOnce();

    expect(extractions, 5);
    expect(repository.batchSizes, [2, 2, 1]);
    expect(
      repository.tracks
          .where((track) => track.uri.startsWith('/'))
          .every((track) => track.artworkPath != null),
      isTrue,
    );
    expect(repository.tracks.last.artworkPath, isNull);
  });
}

final class _Repository implements TrackRepository {
  _Repository(this.tracks);

  final List<Track> tracks;
  final List<int> batchSizes = [];

  @override
  Stream<List<Track>> watchAll() => Stream.value(List.of(tracks));

  @override
  Future<void> upsertAll(List<Track> values) async {
    batchSizes.add(values.length);
    for (final value in values) {
      final index = tracks.indexWhere((track) => track.uri == value.uri);
      tracks[index] = value;
    }
  }

  @override
  Stream<List<Track>> watchSearch(String query) => watchAll();
  @override
  Stream<List<Track>> watchFavorites() => const Stream.empty();
  @override
  Future<int> count() async => tracks.length;
  @override
  Future<void> clearLibrary() async => tracks.clear();
  @override
  Future<void> deleteAll() async => tracks.clear();
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
}
