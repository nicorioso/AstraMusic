import 'dart:async';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/platform/artwork_cache.dart';
import 'package:astramusic/core/platform/android_system_settings.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
import 'package:astramusic/core/widgets/responsive_shell.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/application/artwork_backfill_service.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inicia el relleno de carátulas desde el shell real', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(fixture.app());
    await tester.pump();

    expect(fixture.backfill.runCount, 1);
  });

  testWidgets('confirma antes de vaciar la biblioteca', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-settings-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('clear-library-button')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Se eliminarán de AstraMusic todas las canciones, las playlists '
        'creadas, la cola y las carpetas guardadas. Tus archivos del '
        'dispositivo NO se borran. Esta acción no se puede deshacer.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(fixture.repository.clearCount, 0);

    await tester.tap(find.byKey(const Key('clear-library-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar todo'));
    await tester.pumpAndSettle();

    expect(fixture.repository.clearCount, 1);
    expect(fixture.cache.clearCount, 1);
    expect(find.text('Biblioteca vaciada'), findsOneWidget);
  });

  testWidgets('Ajustes avisa si notificaciones están denegadas', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(fixture.app(notificationPermissionGranted: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-settings-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-notification-warning')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open-notification-settings')));
    await tester.pump();
    expect(fixture.systemSettings.notificationSettingsCount, 1);
  });

  testWidgets('Diagnóstico muestra las métricas debug y permite salir', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-diagnostics-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diagnostics-destination')), findsOneWidget);
    expect(find.text('Arranque hasta primer frame'), findsOneWidget);
    expect(find.text('Caché de carátulas'), findsOneWidget);
    expect(find.text('Reconstrucciones del listado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-diagnostics-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-destination')), findsOneWidget);
  });

  testWidgets('los ticks de posición no reconstruyen el listado ni sus filas', (
    tester,
  ) async {
    PerformanceDiagnostics.instance.resetForTesting();
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final before = PerformanceDiagnostics.instance.value;

    fixture.player.emitPosition(const Duration(seconds: 1));
    await tester.pump();

    final after = PerformanceDiagnostics.instance.value;
    expect(after.listBuilds, before.listBuilds);
    expect(after.trackRowBuilds, before.trackRowBuilds);
  });

  testWidgets('elige el shell y responde al cambio de ancho', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(600, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    expect(find.byKey(const Key('mobile-shell')), findsOneWidget);

    await _setSize(tester, const Size(1000, 800));
    await tester.pump();
    expect(find.byKey(const Key('desktop-shell')), findsOneWidget);
  });

  testWidgets('cambia de destino desde la navegación móvil', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(600, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();

    await tester.tap(find.text('Buscar'));
    await tester.pump();
    expect(find.byKey(const Key('search-destination')), findsOneWidget);

    await tester.tap(find.text('Biblioteca'));
    await tester.pump();
    expect(find.byKey(const Key('library-destination')), findsOneWidget);
  });

  testWidgets('Escape vuelve desde una pantalla secundaria de escritorio', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();

    await tester.tap(find.text('Ajustes'));
    await tester.pump();
    expect(find.byKey(const Key('settings-destination')), findsOneWidget);
    expect(find.byKey(const Key('desktop-back-button')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('settings-destination')), findsNothing);
    expect(find.byKey(const Key('home-destination')), findsOneWidget);
  });

  testWidgets('pliega la barra lateral entre 300 y 72 dp', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('desktop-sidebar'))).width, 300);
    await tester.tap(find.byTooltip('Plegar barra lateral'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('desktop-sidebar'))).width, 72);
    await tester.tap(find.byKey(const Key('expand-sidebar-button')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('desktop-sidebar'))).width, 300);
  });

  testWidgets('centra todos los iconos de la barra lateral plegada', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    await tester.tap(find.byTooltip('Plegar barra lateral'));
    await tester.pump();

    final sidebarCenter = tester
        .getRect(find.byKey(const Key('desktop-sidebar')))
        .center
        .dx;
    for (final key in const [
      Key('collapsed-library-button'),
      Key('expand-sidebar-button'),
      ValueKey('collapsed-playlist-7'),
      Key('collapsed-settings-button'),
    ]) {
      final button = find.byKey(key);
      final icon = find.descendant(of: button, matching: find.byType(Icon));
      expect(
        (tester.getCenter(icon).dx - sidebarCenter).abs(),
        lessThanOrEqualTo(1),
        reason: '$key no comparte el eje central',
      );
      final area = tester.getSize(button);
      expect(area.width, greaterThanOrEqualTo(48));
      expect(area.height, greaterThanOrEqualTo(48));
    }
  });

  for (final width in const [900.0, 1200.0, 1600.0]) {
    testWidgets('el volumen conserva ancho y margen a ${width.toInt()} dp', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await _setSize(tester, Size(width, 800));
      await tester.pumpWidget(fixture.app());
      await tester.pump();

      final barRect = tester.getRect(
        find.byKey(const Key('desktop-player-bar')),
      );
      final sliderRect = tester.getRect(
        find.byKey(const Key('desktop-volume-slider')),
      );
      final muteRect = tester.getRect(
        find.byKey(const Key('desktop-mute-button')),
      );
      expect(sliderRect.width, greaterThanOrEqualTo(110));
      expect(sliderRect.left - muteRect.right, greaterThanOrEqualTo(8));
      expect(barRect.right - sliderRect.right, greaterThanOrEqualTo(16));
      expect(sliderRect.top, greaterThanOrEqualTo(barRect.top));
      expect(sliderRect.bottom, lessThanOrEqualTo(barRect.bottom));
    });
  }

  testWidgets('silencia y restaura el volumen anterior', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    fixture.player.emitVolume(0.65);
    await tester.pump();

    await tester.tap(find.byKey(const Key('desktop-mute-button')));
    await tester.pump();
    expect(fixture.player.volume, 0);
    await tester.tap(find.byKey(const Key('desktop-mute-button')));
    await tester.pump();
    expect(fixture.player.volume, 0.65);
  });

  testWidgets('oculta el mini reproductor cuando no hay canción', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    expect(find.byKey(const Key('mobile-mini-player')), findsNothing);
  });

  testWidgets(
    'resalta por id en biblioteca, búsqueda, playlist y cola, incluso tras next',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await _setSize(tester, const Size(360, 800));
      await tester.pumpWidget(fixture.app());
      await tester.pump();
      fixture.player.seedTrack(fixture.repository.tracks);
      fixture.player.emitShuffle(true);
      await tester.pump();
      final initialContainer = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('mobile-shell'))),
      );
      expect(
        initialContainer.read(playerControllerProvider).shuffleEnabled,
        isTrue,
      );

      await tester.drag(
        find.byKey(const Key('shell-track-list')),
        const Offset(0, -2000),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('current-track-indicator-0')),
        findsOneWidget,
      );
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mobile-search-field')),
        'cancion 0',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('current-track-indicator-0')),
        findsOneWidget,
      );

      await tester.tap(find.text('Biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlist de prueba'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlist-detail')), findsOneWidget);
      expect(find.byKey(const Key('mobile-mini-player')), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('current-track-indicator-0')),
        findsOneWidget,
      );

      await tester.runAsync(() => fixture.player.next());
      await tester.pump();
      expect(
        find.byKey(const ValueKey('current-track-indicator-1')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-destination')), findsOneWidget);
      expect(find.byKey(const Key('mobile-shell')), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('mobile-shell'))),
      );
      container
          .read(appDestinationProvider.notifier)
          .select(AppDestination.queue);
      await tester.pump();
      expect(find.byKey(const Key('queue-destination')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('current-track-indicator-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reproducir desde playlist mantiene mini reproductor y navegación móvil',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await _setSize(tester, const Size(360, 800));
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlist de prueba'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Canción 0'));
      await tester.pump();

      expect(find.byKey(const Key('playlist-detail')), findsOneWidget);
      expect(find.byKey(const Key('mobile-mini-player')), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la barra de escritorio no contiene controles extra', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pump();

    final bar = find.byKey(const Key('desktop-player-bar'));
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.queue_music)),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.lyrics)),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.fullscreen)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bar,
        matching: find.byKey(const Key('desktop-volume-slider')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('la rejilla abre y reproduce una playlist marcándola', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-shortcut-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playlist-detail')), findsOneWidget);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-shortcut-play-7')));
    await tester.pumpAndSettle();
    expect(fixture.playlists.markedPlayedIds, [7]);
    expect(fixture.player.playQueueCalls, 1);
  });

  testWidgets('buscar separa canciones y playlists ignorando acentos', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Busca canciones, artistas, álbumes o playlists.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('mobile-search-field')),
      'exitos',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Éxitos acústicos'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('mobile-search-field')),
      'cancion 2',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Canciones'), findsOneWidget);
    expect(find.text('Canción 2'), findsOneWidget);
  });

  testWidgets('Inicio ordena por fecha de adición descendente', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    final titles = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('shell-track-list')),
        matching: find.byType(Text),
      ),
    );
    expect(titles.first.data, 'Canción 29');
  });

  testWidgets('tabla adapta la columna de álbum al ancho del panel', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-album-header')), findsNothing);

    await _setSize(tester, const Size(1600, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('destination-content'))).width,
      greaterThan(1100),
    );
    expect(find.byKey(const Key('desktop-album-header')), findsOneWidget);
  });

  testWidgets('muestra las acciones vacías correctas por shell', (
    tester,
  ) async {
    final fixture = _Fixture(trackCount: 0);
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Añadir archivos'), findsOneWidget);

    await _setSize(tester, const Size(1400, 900));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Añadir carpeta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Biblioteca conserva favoritos, creación y acceso a Ajustes', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _setSize(tester, const Size(360, 800));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    expect(find.text('Canciones que te gustan'), findsOneWidget);
    expect(find.byKey(const Key('create-playlist-button')), findsOneWidget);
    expect(find.byKey(const Key('library-settings-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-destination')), findsOneWidget);
  });

  for (final size in const [Size(360, 800), Size(937, 1029), Size(1400, 900)]) {
    testWidgets('contenido y controles válidos a ${size.width.toInt()} px', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await _setSize(tester, size);
      await tester.pumpWidget(fixture.app());
      await tester.pump();
      fixture.player.seedTrack();
      await tester.pump();

      final content = tester.getSize(
        find.byKey(const Key('destination-content')),
      );
      final reserved = size.width >= desktopBreakpoint ? 88.0 : 80.0;
      expect(
        content.height,
        greaterThanOrEqualTo((size.height - reserved) * 0.70),
      );

      final controlKeys = size.width >= desktopBreakpoint
          ? const [
              Key('desktop-shuffle-button'),
              Key('desktop-previous-button'),
              Key('desktop-play-button'),
              Key('desktop-next-button'),
              Key('desktop-repeat-button'),
              Key('desktop-mute-button'),
              Key('desktop-volume-slider'),
            ]
          : const [Key('mobile-mini-player'), Key('mobile-mini-play-button')];
      for (final key in controlKeys) {
        expect(find.byKey(key).hitTestable(), findsOneWidget, reason: '$key');
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

final class _Fixture {
  _Fixture({int trackCount = 30})
    : repository = _FakeTrackRepository(
        List.generate(
          trackCount,
          (index) => Track(
            id: index,
            uri: 'file:///track-$index.mp3',
            title: 'Canción $index',
            artist: 'Artista $index',
            album: 'Álbum $index',
            duration: const Duration(minutes: 3),
            dateAdded: DateTime(2026, 1, index + 1),
          ),
        ),
      );

  final player = _FakePlayer();
  final cache = _FakeArtworkCache();
  final backfill = _RecordingArtworkBackfill();
  final systemSettings = _FakeAndroidSystemSettings();
  final _FakeTrackRepository repository;
  late final _FakePlaylistRepository playlists = _FakePlaylistRepository(
    repository.tracks,
  );

  Widget app({bool notificationPermissionGranted = true}) => ProviderScope(
    overrides: [
      audioPlayerServiceProvider.overrideWithValue(player),
      trackRepositoryProvider.overrideWithValue(repository),
      isAndroidPlatformProvider.overrideWithValue(true),
      artworkCacheProvider.overrideWithValue(cache),
      artworkBackfillServiceProvider.overrideWithValue(backfill),
      playlistRepositoryProvider.overrideWithValue(playlists),
      notificationPermissionGrantedProvider.overrideWithValue(
        notificationPermissionGranted,
      ),
      androidSystemSettingsProvider.overrideWithValue(systemSettings),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      home: const ResponsiveShell(),
    ),
  );

  Future<void> dispose() => player.dispose();
}

final class _FakeAndroidSystemSettings implements AndroidSystemSettings {
  int notificationSettingsCount = 0;
  int batterySettingsCount = 0;

  @override
  Future<bool> openAppNotificationSettings() async {
    notificationSettingsCount++;
    return true;
  }

  @override
  Future<void> openBatteryOptimizationSettings() async {
    batterySettingsCount++;
  }
}

final class _RecordingArtworkBackfill implements ArtworkBackfill {
  int runCount = 0;

  @override
  Future<void> runOnce() async => runCount++;
}

final class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(this.tracks);

  final List<Track> tracks;
  final markedPlayedIds = <int>[];
  Playlist get playlist => Playlist(
    id: 7,
    name: 'Playlist de prueba',
    trackCount: tracks.length,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  Playlist get accentedPlaylist => Playlist(
    id: 8,
    name: 'Éxitos acústicos',
    trackCount: 0,
    createdAt: DateTime(2026, 2),
    updatedAt: DateTime(2026, 2),
  );

  @override
  Future<Playlist> create(String name) async => Playlist(
    id: 1,
    name: name.trim(),
    trackCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<void> delete(int id) async {}

  @override
  Future<AddTracksResult> addTracks(int playlistId, List<int> trackIds) async =>
      AddTracksResult(added: trackIds.length, alreadyPresent: 0);

  @override
  Future<void> removeTrack(int playlistId, int trackId) async {}

  @override
  Future<void> move(int playlistId, int oldIndex, int newIndex) async {}

  @override
  Future<void> markPlayed(int id) async => markedPlayedIds.add(id);

  @override
  Stream<List<Playlist>> watchRecent(int limit) => Stream.value(const []);

  @override
  Future<List<Track>> coverTracks(int playlistId, {int limit = 4}) async =>
      tracks.take(limit).toList();

  @override
  Future<void> rename(int id, String name) async {}

  @override
  Stream<List<Playlist>> watchAll() =>
      Stream.value([playlist, accentedPlaylist]);

  @override
  Stream<Playlist?> watchById(int id) => Stream.value(playlist);

  @override
  Stream<List<Track>> watchTracks(int id) => Stream.value(tracks);
}

final class _FakeTrackRepository implements TrackRepository {
  _FakeTrackRepository(this.tracks);
  final List<Track> tracks;
  int clearCount = 0;
  @override
  Future<int> count() async => tracks.length;
  @override
  Future<void> deleteAll() async {}

  @override
  Future<Set<String>> excludedUris() async => const {};

  @override
  Future<void> excludeAndDelete(Track track) async {}

  @override
  Future<void> restoreExcluded(Set<String> uris) async {}

  @override
  Future<void> clearLibrary() async {
    clearCount++;
    tracks.clear();
  }

  @override
  Future<void> setFavorite(int id, bool favorite) async {}
  @override
  Stream<List<Track>> watchFavorites() =>
      Stream.value(tracks.where((track) => track.isFavorite).toList());

  @override
  Future<void> deleteByUris(Set<String> uris) async {}
  @override
  Future<Track?> getById(int id) async => null;
  @override
  Future<void> markUnavailable(Set<String> uris) async {}
  @override
  Future<void> setAvailability(Map<String, bool> availability) async {}
  @override
  Future<void> upsertAll(List<Track> tracks) async {}
  @override
  Stream<List<Track>> watchAll() => Stream.value(tracks);
  @override
  Stream<List<Track>> watchSearch(String query) => Stream.value(
    tracks
        .where(
          (track) => normalizeForSearch(
            '${track.title} ${track.artist ?? ''} ${track.album ?? ''}',
          ).contains(normalizeForSearch(query)),
        )
        .toList(),
  );
}

final class _FakeArtworkCache implements ArtworkCache {
  int clearCount = 0;

  @override
  Future<int> sizeBytes() async => 0;

  @override
  Future<void> clear() async => clearCount++;

  @override
  Future<void> deleteByKey(String key) async {}
}

final class _FakePlayer implements AudioPlayerService {
  final _playback = StreamController<AudioPlaybackState>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);
  final _item = StreamController<AudioItem?>.broadcast(sync: true);
  final _queue = StreamController<List<Track>>.broadcast(sync: true);
  final _index = StreamController<int?>.broadcast(sync: true);
  final _shuffle = StreamController<bool>.broadcast(sync: true);
  final _repeat = StreamController<RepeatMode>.broadcast(sync: true);
  final _volume = StreamController<double>.broadcast(sync: true);
  double volume = 1;
  int playQueueCalls = 0;
  List<Track> _tracks = const [];
  var _trackIndex = 0;

  void seedTrack([List<Track>? tracks]) {
    _tracks = tracks ?? const [];
    _trackIndex = 0;
    if (_tracks.isNotEmpty) {
      _queue.add(List.of(_tracks));
      _index.add(0);
    }
    _item.add(
      AudioItem(
        path: _tracks.isEmpty ? 'file:///track-0.mp3' : _tracks.first.uri,
        title: _tracks.isEmpty ? 'Canción actual' : _tracks.first.title,
        artist: _tracks.isEmpty ? 'Artista actual' : _tracks.first.artist,
        duration: const Duration(minutes: 3),
        trackId: _tracks.isEmpty ? 0 : _tracks.first.id,
      ),
    );
    _duration.add(const Duration(minutes: 3));
    _playback.add(const AudioPlaybackState(AudioPlaybackStatus.paused));
  }

  void emitVolume(double value) {
    volume = value;
    _volume.add(value);
  }

  void emitShuffle(bool value) => _shuffle.add(value);

  void emitPosition(Duration value) => _position.add(value);

  @override
  Stream<AudioItem?> get currentItemStream => _item.stream;
  @override
  Stream<int?> get currentIndexStream => _index.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playbackStateStream => _playback.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<List<Track>> get queueStream => _queue.stream;
  @override
  Stream<RepeatMode> get repeatModeStream => _repeat.stream;
  @override
  Stream<bool> get shuffleEnabledStream => _shuffle.stream;
  @override
  Stream<double> get volumeStream => _volume.stream;
  @override
  Future<void> addToQueue(Track track) async {}
  @override
  Future<void> clearQueue() async {}
  @override
  Future<void> loadFile({required String path, required String title}) async {}
  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {}
  @override
  Future<void> next() async {
    if (_tracks.isEmpty) return;
    _trackIndex = (_trackIndex + 1).clamp(0, _tracks.length - 1);
    final track = _tracks[_trackIndex];
    _index.add(_trackIndex);
    _item.add(
      AudioItem(
        path: track.uri,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        trackId: track.id,
      ),
    );
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> playNext(Track track) async {}
  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    playQueueCalls++;
    _tracks = List.of(tracks);
    _trackIndex = startIndex;
    final track = tracks[startIndex];
    _queue.add(List.of(tracks));
    _index.add(startIndex);
    _item.add(
      AudioItem(
        path: track.uri,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        trackId: track.id,
      ),
    );
  }

  @override
  Future<void> previous() async {}
  @override
  Future<void> removeFromQueue(int index) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRepeatMode(RepeatMode mode) async => _repeat.add(mode);
  @override
  Future<void> setShuffle(bool enabled) async => _shuffle.add(enabled);
  @override
  Future<void> setVolume(double value) async => emitVolume(value);
  @override
  Future<void> skipToIndex(int index) async {}
  @override
  Future<void> stop() async {}

  Future<void> dispose() => Future.wait([
    _playback.close(),
    _position.close(),
    _duration.close(),
    _item.close(),
    _queue.close(),
    _index.close(),
    _shuffle.close(),
    _repeat.close(),
    _volume.close(),
  ]);
}
