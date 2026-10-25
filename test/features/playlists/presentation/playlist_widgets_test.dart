import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/core/widgets/responsive_shell.dart';
import 'package:astramusic/core/widgets/track_artwork.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/playlists/presentation/playlist_widgets.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(360, 800), Size(937, 1029)]) {
    for (final count in const [0, 1, 30]) {
      testWidgets(
        'selector real con $count playlists a ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          final fixture = _Fixture(
            playlistCount: count,
            useComplexPlaylistNames: true,
          );
          await _setSize(tester, size);
          await tester.pumpWidget(fixture.shellApp());
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Acciones de Canción 1'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Añadir a playlist'));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('playlist-chooser')), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (count == 0) {
            expect(find.text('Aún no tienes playlists'), findsWidgets);
          } else {
            expect(find.textContaining('播放列表'), findsWidgets);
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('playlist-chooser')), findsNothing);
          expect(tester.takeException(), isNull);

          if (size.width < desktopBreakpoint) {
            await tester.tap(find.text('Buscar'));
            await tester.pump();
            expect(find.byKey(const Key('search-destination')), findsOneWidget);
          } else {
            await tester.tap(find.byKey(const Key('desktop-home-button')));
            await tester.pump();
            expect(find.byKey(const Key('home-destination')), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('atrás cierra el selector móvil y la app sigue respondiendo', (
    tester,
  ) async {
    final fixture = _Fixture(playlistCount: 30, useComplexPlaylistNames: true);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.shellApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a playlist'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playlist-chooser')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playlist-chooser')), findsNothing);
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    expect(find.byKey(const Key('search-destination')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(
      find.descendant(
        of: find.byKey(const Key('desktop-playlist-list')),
        matching: find.text('Viaje'),
      ),
      findsOneWidget,
    );
    expect(find.text('Playlist · 3 canciones'), findsOneWidget);
  });

  testWidgets('Canciones que te gustan aparece primero y sin administrar', (
    tester,
  ) async {
    final fixture = _Fixture(favoriteFirst: true);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.shellApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    final favorites = find.byKey(const Key('favorites-playlist-tile'));
    expect(favorites, findsOneWidget);
    expect(
      tester.getTopLeft(favorites).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('library-playlist-7'))).dy,
      ),
    );
    await tester.tap(favorites);
    await tester.pumpAndSettle();
    expect(find.text('Canciones que te gustan'), findsOneWidget);
    expect(find.byKey(const Key('playlist-menu-button')), findsNothing);

    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    expect(find.text('Renombrar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
    await tester.tap(find.text('Quitar de Me gusta'));
    await tester.pump();
    expect(fixture.trackRepository.favoriteChanges, [(1, false)]);
  });

  for (final scenario in const [(0, 0), (2, 1), (5, 4)]) {
    testWidgets(
      'PlaylistCover usa ${scenario.$2} carátulas con ${scenario.$1}',
      (tester) async {
        final fixture = _Fixture(trackCount: scenario.$1);
        await tester.pumpWidget(fixture.coverApp());
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('cover-under-test')),
            matching: find.byType(TrackArtwork),
          ),
          findsNWidgets(scenario.$2),
        );
      },
    );
  }

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
    expect(fixture.playlists.playedIds, [7]);
  });

  testWidgets('reordenar en el detalle llama move con el índice final', (
    tester,
  ) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.detailApp());
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byKey(const Key('playlist-track-list')),
    );
    list.onReorderItem!(0, 2);
    await tester.pump();

    expect(fixture.playlists.moves, [(0, 2)]);
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

  testWidgets('abre overlays desde sus flujos reales sin excepciones', (
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
    expect(find.byKey(const Key('playlist-name-field')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar de la biblioteca'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(fixture.detailApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlist-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renombrar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playlist-name-field')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('confirm-delete-playlist-button')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar de esta playlist'));
    await tester.pumpAndSettle();
    expect(fixture.playlists.removedTrackIds, [1]);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(fixture.queueApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Acciones de Canción 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a playlist'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playlist-chooser')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playlist-chooser')), findsNothing);
    expect(tester.takeException(), isNull);
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
  _Fixture({
    int trackCount = 3,
    int playlistCount = 1,
    bool useComplexPlaylistNames = false,
    bool favoriteFirst = false,
  }) {
    tracks = List.generate(
      trackCount,
      (index) => Track(
        id: index + 1,
        uri: 'file:///track-${index + 1}.mp3',
        title: 'Canción ${index + 1}',
        artist: 'Artista',
        duration: const Duration(minutes: 3),
        dateAdded: DateTime(2026),
        favoritedAt: favoriteFirst && index == 0 ? DateTime(2026) : null,
        isAvailable: index != 1,
      ),
    );
    playlists = _FakePlaylistRepository(
      tracks,
      playlistCount: playlistCount,
      useComplexNames: useComplexPlaylistNames,
    );
    player.seedQueue(tracks);
    trackRepository = _TrackRepository(tracks);
  }

  late final List<Track> tracks;
  late final _FakePlaylistRepository playlists;
  late final _TrackRepository trackRepository;
  final player = _RecordingPlayer();

  Widget shellApp() => ProviderScope(
    key: UniqueKey(),
    overrides: [
      playlistRepositoryProvider.overrideWithValue(playlists),
      trackRepositoryProvider.overrideWithValue(trackRepository),
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
    key: UniqueKey(),
    overrides: [
      playlistRepositoryProvider.overrideWithValue(playlists),
      trackRepositoryProvider.overrideWithValue(trackRepository),
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

  Widget queueApp() => ProviderScope(
    key: UniqueKey(),
    overrides: [
      playlistRepositoryProvider.overrideWithValue(playlists),
      audioPlayerServiceProvider.overrideWithValue(player),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      home: const QueueScreen(),
    ),
  );

  Widget coverApp() => ProviderScope(
    overrides: [playlistRepositoryProvider.overrideWithValue(playlists)],
    child: MaterialApp(
      theme: buildAstraTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            key: const Key('cover-under-test'),
            child: PlaylistCover(playlist: playlists.playlist, size: 96),
          ),
        ),
      ),
    ),
  );
}

final class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(
    this.tracks, {
    required int playlistCount,
    required bool useComplexNames,
  }) : items = List.generate(
         playlistCount,
         (index) => Playlist(
           id: index + 7,
           name: useComplexNames && index == 0
               ? '播放列表 Viaje con un nombre largo para probar el diseño'
               : useComplexNames
               ? '播放列表 ${index + 1}'
               : index == 0
               ? 'Viaje'
               : 'Playlist ${index + 1}',
           trackCount: tracks.length,
           createdAt: DateTime(2026),
           updatedAt: DateTime(2026),
         ),
       );

  final List<Track> tracks;
  final List<Playlist> items;
  final List<String> createdNames = [];
  final List<int> addedTrackIds = [];
  final List<int> deletedIds = [];
  final List<int> removedTrackIds = [];
  final List<(int, int)> moves = [];
  final List<int> playedIds = [];
  Playlist get playlist => items.isEmpty
      ? Playlist(
          id: 7,
          name: 'Viaje',
          trackCount: tracks.length,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        )
      : items.first;

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
  Future<void> removeTrack(int playlistId, int trackId) async {
    removedTrackIds.add(trackId);
  }

  @override
  Future<void> move(int playlistId, int oldIndex, int newIndex) async {
    moves.add((oldIndex, newIndex));
  }

  @override
  Future<void> markPlayed(int id) async => playedIds.add(id);

  @override
  Stream<List<Playlist>> watchRecent(int limit) => Stream.value(const []);

  @override
  Future<List<Track>> coverTracks(int playlistId, {int limit = 4}) async =>
      tracks.take(limit).toList();

  @override
  Future<void> rename(int id, String name) async {}

  @override
  Stream<List<Playlist>> watchAll() => Stream.value(items);

  @override
  Stream<Playlist?> watchById(int id) => Stream.value(playlist);

  @override
  Stream<List<Track>> watchTracks(int id) => Stream.value(tracks);
}

final class _TrackRepository implements TrackRepository {
  _TrackRepository(this.tracks);

  final List<Track> tracks;
  final List<(int, bool)> favoriteChanges = [];

  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);
  @override
  Stream<List<Track>> watchSearch(String query) => watchAll();
  @override
  Future<void> clearLibrary() async {}
  @override
  Future<void> setFavorite(int id, bool favorite) async {
    favoriteChanges.add((id, favorite));
  }

  @override
  Stream<List<Track>> watchFavorites() =>
      Stream.value(tracks.where((track) => track.isFavorite).toList());
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
  List<Track> queue = const [];
  int startIndex = 0;
  int playCalls = 0;

  void seedQueue(List<Track> tracks) => queue = List.of(tracks);

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
  Stream<List<Track>> get queueStream => Stream.value(queue);
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
