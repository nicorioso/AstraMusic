import 'package:astramusic/features/library/domain/track.dart';

abstract interface class TrackRepository {
  Stream<List<Track>> watchAll();
  Stream<List<Track>> watchSearch(String query);
  Future<void> upsertAll(List<Track> tracks);
  Future<void> markUnavailable(Set<String> uris);
  Future<Track?> getById(int id);
  Future<int> count();
  Future<void> deleteByUris(Set<String> uris);
  Future<void> deleteAll();
}
