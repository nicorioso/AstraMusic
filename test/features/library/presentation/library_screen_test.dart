import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/library/presentation/library_screen.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el estado vacío de la biblioteca', (tester) async {
    await tester.pumpWidget(_testApp(const FakeTrackRepository([])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty-library-message')), findsOneWidget);
    expect(find.byKey(const Key('add-files-button')), findsOneWidget);
  });

  testWidgets('muestra canciones del repositorio sin tipos de drift', (
    tester,
  ) async {
    final tracks = [
      Track(
        id: 1,
        uri: 'file:///primera.mp3',
        title: 'Primera canción',
        artist: 'Artista local',
        duration: const Duration(minutes: 3, seconds: 5),
        dateAdded: DateTime(2026),
      ),
      Track(
        id: 2,
        uri: 'file:///segunda.mp3',
        title: 'Segunda canción',
        dateAdded: DateTime(2026),
      ),
    ];

    await tester.pumpWidget(_testApp(FakeTrackRepository(tracks)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-track-list')), findsOneWidget);
    expect(find.text('Primera canción'), findsOneWidget);
    expect(find.text('Artista local'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
    expect(find.text('Segunda canción'), findsOneWidget);
  });
}

Widget _testApp(TrackRepository repository) {
  return ProviderScope(
    overrides: [
      trackRepositoryProvider.overrideWithValue(repository),
      audioPlayerServiceProvider.overrideWithValue(
        const FakeAudioPlayerService(),
      ),
      audioFilePickerProvider.overrideWithValue(const FakeAudioFilePicker()),
    ],
    child: const MaterialApp(home: LibraryScreen()),
  );
}

final class FakeTrackRepository implements TrackRepository {
  const FakeTrackRepository(this.tracks);

  final List<Track> tracks;

  @override
  Future<int> count() async => tracks.length;

  @override
  Future<void> deleteAll() async {}

  @override
  Future<Track?> getById(int id) async {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  Future<void> markUnavailable(Set<String> uris) async {}

  @override
  Future<void> upsertAll(List<Track> tracks) async {}

  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);

  @override
  Stream<List<Track>> watchSearch(String query) => Stream.value(
    tracks
        .where(
          (track) =>
              [track.title, track.artist, track.album].whereType<String>().any(
                (value) => value.toLowerCase().contains(query.toLowerCase()),
              ),
        )
        .toList(growable: false),
  );
}

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker();

  @override
  Future<PickedAudioFile?> pickAudioFile() async => null;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => const [];
}

final class FakeAudioPlayerService implements AudioPlayerService {
  const FakeAudioPlayerService();

  @override
  Stream<AudioItem?> get currentItemStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<AudioPlaybackState> get playbackStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Future<void> loadFile({required String path, required String title}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}
