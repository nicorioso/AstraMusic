import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/core/widgets/responsive_shell.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el diálogo de crear playlist valida el nombre vacío', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.shellApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-playlist-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-playlist-button')));
    await tester.pump();

    expect(find.text('Escribe un nombre.'), findsOneWidget);
    expect(fixture.playlists.createdNames, isEmpty);
  });

  testWidgets('muestra playlists en la barra lateral', (tester) async {
    final fixture = _Fixture();
    await _setSize(tester, const Size(1400, 900));
    await tester.pumpWidget(fixture.shellApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-playlist-list')), findsOneWidget);
    expect(find.text('Viaje'), findsOneWidget);
    expect(find.text('Playlist · 3 canciones'), findsOneWidget);
  });

  testWidgets('añade una canción a una playlist desde su menú', (tester) async {
    final fixture = _Fixture();
    await _setSize(tester, const Size(1400, 900));
    await tester.pumpWidget(fixture.shellApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viaje').last);
    await tester.pumpAndSettle();

    expect(fixture.playlists.addedTrackIds, [1]);
    expect(find.text('Añadida a Viaje'), findsOneWidget);
  });

  testWidgets('el detalle reproduce la cola disponible desde la elegida', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.detailApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Canción 3'));
    await tester.pump();

    expect(fixture.player.loaded.map((track) => track.id), [1, 3]);
    expect(fixture.player.startIndex, 1);
    expect(fixture.player.playCalls, 1);
  });

  testWidgets('eliminar una playlist exige confirmación', (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.detailApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Se eliminará la playlist Viaje. Tus canciones no se borran.'),
      findsOneWidget,
    );
    expect(fixture.playlists.deletedIds, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-delete-playlist-button')));
    await tester.pumpAndSettle();
    expect(fixture.playlists.deletedIds, [7]);
  });

  for (final size in const [Size(360, 800), Size(937, 1029), Size(1400, 900)]) {
    testWidgets(
      'detalle sin overflow a ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        final fixture = _Fixture(trackCount: 30);
        await _setSize(tester, size);
        await tester.pumpWidget(fixture.detailApp());
        await tester.pumpAndSettle();

        final viewport = tester.getSize(
          find.byKey(const Key('playlist-tracks-viewport')),
        );
        expect(
          viewport.height,
          greaterThanOrEqualTo((size.height - 56) * 0.70),
        );
        for (final key in const [
          Key('playlist-play-button'),
          Key('playlist-shuffle-button'),
          Key('playlist-menu-button'),
        ]) {
          expect(find.byKey(key).hitTestable(), findsOneWidget, reason: '$key');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

final class _Fixture {
  _Fixture({int trackCount = 3}) {
    tracks = List.generate(
      trackCount,
      (index) => Track(
        id: index + 1,
        uri: 'file:///track-${index + 1}.mp3',
        title: 'Canción ${index + 1}',
        artist: 'Artista',
        duration: const Duration(minutes: 3),
        dateAdded: DateTime(2026),
        isAvailable: index != 1,
      ),
    );
    playlists = _FakePlaylistRepository(tracks);
  }

  late final List<Track> tracks;
  late final _FakePlaylistRepository playlists;
  final player = _RecordingPlayer();

  Widget shellApp() => ProviderScope(
    overrides: [
      playlistRepositoryProvider.overrideWithValue(playlists),
      trackRepositoryProvider.overrideWithValue(_TrackRepository(tracks)),
      audioPlayerServiceProvider.overrideWithValue(player),
      isAndroidPlatformProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      home: const ResponsiveShell(),
    ),
  );

  Widget detailApp() => ProviderScope(
    overrides: [
      playlistRepositoryProvider.overrideWithValue(playlists),
      trackRepositoryProvider.overrideWithValue(_TrackRepository(tracks)),
      audioPlayerServiceProvider.overrideWithValue(player),
      isAndroidPlatformProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      home: const PlaylistDetailScreen(playlistId: 7),
    ),
  );
}

final class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(this.tracks);

  final List<Track> tracks;
  final List<String> createdNames = [];
  final List<int> addedTrackIds = [];
  final List<int> deletedIds = [];
  late final playlist = Playlist(
    id: 7,
    name: 'Viaje',
    trackCount: tracks.length,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<Playlist> create(String name) async {
    createdNames.add(name);
    return Playlist(
      id: 8,
      name: name,
      trackCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<AddTracksResult> addTracks(int playlistId, List<int> trackIds) async {
    addedTrackIds.addAll(trackIds);
    return AddTracksResult(added: trackIds.length, alreadyPresent: 0);
  }

  @override
  Future<void> delete(int id) async => deletedIds.add(id);

  @override
  Future<void> removeTrack(int playlistId, int trackId) async {}

  @override
  Future<void> rename(int id, String name) async {}

  @override
  Stream<List<Playlist>> watchAll() => Stream.value([playlist]);

  @override
  Stream<Playlist?> watchById(int id) => Stream.value(playlist);

  @override
  Stream<List<Track>> watchTracks(int id) => Stream.value(tracks);
}

final class _TrackRepository implements TrackRepository {
  const _TrackRepository(this.tracks);

  final List<Track> tracks;

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
  Future<void> setAvailability(Map<String, bool> availability) async {}
  @override
  Future<void> upsertAll(List<Track> tracks) async {}
}

final class _RecordingPlayer implements AudioPlayerService {
  List<Track> loaded = const [];
  int startIndex = 0;
  int playCalls = 0;

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    loaded = List.of(tracks);
    this.startIndex = startIndex;
  }

  @override
  Future<void> play() async => playCalls++;
  @override
  Stream<AudioItem?> get currentItemStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playbackStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<List<Track>> get queueStream => const Stream.empty();
  @override
  Stream<RepeatMode> get repeatModeStream => const Stream.empty();
  @override
  Stream<bool> get shuffleEnabledStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Future<void> addToQueue(Track track) async {}
  @override
  Future<void> clearQueue() async {}
  @override
  Future<void> loadFile({required String path, required String title}) async {}
  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> playNext(Track track) async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> removeFromQueue(int index) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}
  @override
  Future<void> setShuffle(bool enabled) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> skipToIndex(int index) async {}
  @override
  Future<void> stop() async {}
}
