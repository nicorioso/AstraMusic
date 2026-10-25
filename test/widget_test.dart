import 'dart:async';

import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
import 'package:astramusic/features/player/presentation/queue_screen.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el corazón del reproductor alterna el favorito', (tester) async {
    final service = FakeAudioPlayerService();
    final repository = _FavoriteTrackRepository();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(null),
        trackRepository: repository,
      ),
    );
    await tester.pump();
    service.seedQueue(1);
    await tester.pump();

    await tester.tap(find.byKey(const Key('favorite-current-track-button')));
    await tester.pump();
    expect(repository.changes, [(1, true)]);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorite-current-track-button')));
    await tester.pump();
    expect(repository.changes, [(1, true), (1, false)]);
  });

  testWidgets('elige un archivo y alterna entre reproducción y pausa', (
    tester,
  ) async {
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.text('cancion'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('play-pause-button')));
    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();

    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('muestra un error de carga sin lanzar una excepción', (
    tester,
  ) async {
    final service = FakeAudioPlayerService(failOnLoad: true);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/invalido.xyz', title: 'invalido'),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('Formato no compatible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alterna aleatorio, repetir y resalta la canción en la cola', (
    tester,
  ) async {
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('shuffle-button')));
    await tester.tap(find.byKey(const Key('shuffle-button')));
    await tester.pump();
    expect(find.byIcon(Icons.shuffle_on), findsOneWidget);

    await tester.tap(find.byKey(const Key('repeat-button')));
    await tester.pump();
    expect(find.text('Repetir: toda la cola'), findsOneWidget);
    await tester.tap(find.byKey(const Key('repeat-button')));
    await tester.pump();
    expect(find.text('Repetir: una canción'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);

    await tester.pumpWidget(_queueTestApp(service));
    await tester.pump();
    service.seedQueue(1);
    await tester.pump();
    expect(find.byKey(const Key('current-queue-item')), findsOneWidget);
    expect(find.text('Canción 0'), findsOneWidget);
  });

  testWidgets('un fallo de aleatorio no deshabilita los controles', (
    tester,
  ) async {
    final service = FakeAudioPlayerService(failOnShuffle: true);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(path: 'file:///tmp/cancion.mp3', title: 'cancion'),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('shuffle-button')));
    await tester.tap(find.byKey(const Key('shuffle-button')));
    await tester.pump();

    expect(
      find.text('No fue posible cambiar el modo aleatorio.'),
      findsOneWidget,
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key('next-button'))).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('previous-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('repeat-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('la pantalla del reproductor no desborda en tamaño compacto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(
          PickedAudioFile(
            path: 'file:///tmp/cancion.mp3',
            title: 'Título extremadamente largo para una pantalla compacta',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
    await tester.tap(find.byKey(const Key('choose-audio-button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play-pause-button')), findsOneWidget);
  });

  for (final size in const [Size(360, 800), Size(937, 1029), Size(1400, 900)]) {
    testWidgets('reproductor y cola no desbordan a ${size.width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = FakeAudioPlayerService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        _testApp(
          service: service,
          picker: const FakeAudioFilePicker(
            PickedAudioFile(
              path: 'file:///tmp/星間の非常に長い曲名.mp3',
              title: '星間の非常に長い曲名とコロンビアの夜空',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('choose-audio-button')));
      await tester.tap(find.byKey(const Key('choose-audio-button')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_queueTestApp(service));
      await tester.pump();
      service.seedQueue(1);
      await tester.pump();
      expect(find.byType(QueueScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('la cola usa al menos 70% del alto de la ventana', (
    tester,
  ) async {
    const size = Size(937, 1029);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(null),
        home: const QueueScreen(),
      ),
    );
    service.seedQueue(30);
    await tester.pump();

    final viewport = tester.getSize(find.byKey(const Key('queue-list')));
    expect(viewport.height, greaterThanOrEqualTo(size.height * 0.70));
    expect(find.text('Canción 7'), findsOneWidget);
  });

  for (final size in const [Size(360, 800), Size(937, 1029), Size(1400, 900)]) {
    testWidgets('controles visibles y alcanzables a ${size.width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = FakeAudioPlayerService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        _testApp(service: service, picker: const FakeAudioFilePicker(null)),
      );
      service.seedQueue(1);
      await tester.pump();

      final controlKeys = <Key>[
        const Key('current-audio-title'),
        const Key('current-audio-artist'),
        const Key('play-pause-button'),
        const Key('next-button'),
        const Key('previous-button'),
        const Key('shuffle-button'),
        const Key('repeat-button'),
        const Key('seek-slider'),
        if (size.width < 840) const Key('open-queue-button'),
      ];
      for (final key in controlKeys) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget);
        expect(
          finder.hitTestable(),
          findsOneWidget,
          reason: '$key no es alcanzable',
        );
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      if (size.width >= 840) {
        expect(find.byKey(const Key('desktop-queue-title')), findsOneWidget);
        expect(find.byKey(const Key('current-queue-item')), findsOneWidget);
      }
    });
  }

  testWidgets('la cola integrada resalta la actual y permite saltar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _testApp(service: service, picker: const FakeAudioFilePicker(null)),
    );
    service.seedQueue(2);
    await tester.pump();

    expect(find.byKey(const Key('current-queue-item')), findsOneWidget);
    await tester.tap(find.text('Canción 1'));
    await tester.pump();
    expect(service.skippedIndex, 1);
  });

  testWidgets('deslizar hacia abajo cierra el reproductor móvil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(null),
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('launch-player'),
            onPressed: () =>
                Navigator.of(context).push(playerScreenRoute(context)),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    service.seedQueue(1);
    await tester.pump();
    await tester.tap(find.byKey(const Key('launch-player')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('swipe-to-close')),
      const Offset(0, 140),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
  });

  testWidgets('disableAnimations elimina transiciones y errores', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(null),
        disableAnimations: true,
      ),
    );
    service.seedQueue(1);
    await tester.pump();
    await tester.tap(find.byKey(const Key('play-pause-button')));
    await tester.pump();

    for (final switcher in tester.widgetList<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    )) {
      expect(switcher.duration, Duration.zero);
    }
    expect(find.byKey(const Key('playing-indicator')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el indicador queda detenido sin reproducción', (tester) async {
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(_queueTestApp(service));
    service.seedQueue(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('playing-indicator')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final size in const [Size(360, 800), Size(937, 1029), Size(1400, 900)]) {
    testWidgets(
      'salida visible vuelve sin perder scroll a ${size.width.toInt()} px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final service = FakeAudioPlayerService();
        final scrollController = ScrollController();
        addTearDown(service.dispose);
        addTearDown(scrollController.dispose);
        await tester.pumpWidget(
          _testApp(
            service: service,
            picker: const FakeAudioFilePicker(null),
            home: _PlayerLaunchHost(controller: scrollController),
          ),
        );
        scrollController.jumpTo(240);
        await tester.pump();
        final previousOffset = scrollController.offset;
        await tester.tap(find.byKey(const Key('launch-player')));
        await tester.pumpAndSettle();

        final close = find.byKey(const Key('close-player-button'));
        expect(close, findsOneWidget);
        expect(close.hitTestable(), findsOneWidget);
        final touchArea = tester.getSize(close);
        expect(touchArea.width, greaterThanOrEqualTo(48));
        expect(touchArea.height, greaterThanOrEqualTo(48));
        expect(
          find.byTooltip(size.width < 840 ? 'Cerrar' : 'Volver'),
          findsOneWidget,
        );
        await tester.tap(close);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('previous-screen')), findsOneWidget);
        expect(scrollController.offset, previousOffset);
      },
    );
  }

  testWidgets('Escape cierra el reproductor en escritorio', (tester) async {
    const size = Size(937, 1029);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _testApp(
        service: service,
        picker: const FakeAudioFilePicker(null),
        home: _PlayerLaunchHost(controller: ScrollController()),
      ),
    );
    await tester.tap(find.byKey(const Key('launch-player')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byKey(const Key('previous-screen')), findsOneWidget);
  });

  testWidgets('la cola es translúcida y no tiene separador vertical', (
    tester,
  ) async {
    const size = Size(1400, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = FakeAudioPlayerService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _testApp(service: service, picker: const FakeAudioFilePicker(null)),
    );
    service.seedQueue(1);
    await tester.pump();

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('queue-panel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color!.a, lessThan(1));
    expect(find.byType(VerticalDivider), findsNothing);
  });
}

class _PlayerLaunchHost extends StatelessWidget {
  const _PlayerLaunchHost({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('previous-screen'),
    body: ListView(
      controller: controller,
      children: [
        const SizedBox(height: 520),
        Center(
          child: TextButton(
            key: const Key('launch-player'),
            onPressed: () =>
                Navigator.of(context).push(playerScreenRoute(context)),
            child: const Text('Abrir reproductor'),
          ),
        ),
        const SizedBox(height: 900),
      ],
    ),
  );
}

Widget _testApp({
  required AudioPlayerService service,
  required AudioFilePicker picker,
  Widget home = const PlayerScreen(),
  TrackRepository? trackRepository,
  bool disableAnimations = false,
}) {
  final repository = trackRepository ?? _FavoriteTrackRepository();
  return ProviderScope(
    overrides: [
      audioPlayerServiceProvider.overrideWithValue(service),
      audioFilePickerProvider.overrideWithValue(picker),
      trackRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: home,
    ),
  );
}

final class _FavoriteTrackRepository implements TrackRepository {
  final _favorites = <int>{};
  final _controller = StreamController<List<Track>>.broadcast(sync: true);
  final List<(int, bool)> changes = [];

  List<Track> get _current => _favorites
      .map(
        (id) => Track(
          id: id,
          uri: 'file:///favorite-$id.mp3',
          title: 'Favorita $id',
          dateAdded: DateTime(2026),
          favoritedAt: DateTime(2026),
        ),
      )
      .toList();

  @override
  Stream<List<Track>> watchFavorites() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> setFavorite(int id, bool favorite) async {
    changes.add((id, favorite));
    favorite ? _favorites.add(id) : _favorites.remove(id);
    _controller.add(_current);
  }

  @override
  Stream<List<Track>> watchAll() => const Stream.empty();
  @override
  Stream<List<Track>> watchSearch(String query) => const Stream.empty();
  @override
  Future<void> clearLibrary() async {}
  @override
  Future<int> count() async => 0;
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

Widget _queueTestApp(AudioPlayerService service) => _testApp(
  service: service,
  picker: const FakeAudioFilePicker(null),
  home: const QueueScreen(),
);

final class FakeAudioFilePicker implements AudioFilePicker {
  const FakeAudioFilePicker(this.file);

  final PickedAudioFile? file;

  @override
  Future<PickedAudioFile?> pickAudioFile() async => file;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => [?file];
}

final class FakeAudioPlayerService implements AudioPlayerService {
  FakeAudioPlayerService({this.failOnLoad = false, this.failOnShuffle = false});

  final bool failOnLoad;
  final bool failOnShuffle;
  final _playbackStateController =
      StreamController<AudioPlaybackState>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _durationController = StreamController<Duration?>.broadcast(sync: true);
  final _currentItemController = StreamController<AudioItem?>.broadcast(
    sync: true,
  );
  final _queueController = StreamController<List<Track>>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);
  final _shuffleController = StreamController<bool>.broadcast(sync: true);
  final _repeatController = StreamController<RepeatMode>.broadcast(sync: true);
  final _volumeController = StreamController<double>.broadcast(sync: true);
  double volume = 1;
  int? skippedIndex;

  void seedQueue(int count) {
    final tracks = List.generate(
      count,
      (index) => Track(
        id: index + 1,
        uri: 'file:///cancion-$index.mp3',
        title: 'Canción $index',
        artist: 'Artista $index',
        duration: const Duration(minutes: 3),
        dateAdded: DateTime(2026),
      ),
    );
    _queueController.add(tracks);
    _indexController.add(0);
    _currentItemController.add(
      AudioItem(
        path: tracks.first.uri,
        title: tracks.first.title,
        artist: tracks.first.artist,
        duration: tracks.first.duration,
        trackId: tracks.first.id,
      ),
    );
    _durationController.add(tracks.first.duration);
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Stream<AudioPlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioItem?> get currentItemStream => _currentItemController.stream;

  @override
  Stream<int?> get currentIndexStream => _indexController.stream;

  @override
  Stream<AudioPlaybackFailure> get failureStream => const Stream.empty();

  @override
  Stream<List<Track>> get queueStream => _queueController.stream;

  @override
  Stream<RepeatMode> get repeatModeStream => _repeatController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<bool> get shuffleEnabledStream => _shuffleController.stream;

  @override
  Future<void> loadFile({required String path, required String title}) async {
    if (failOnLoad) {
      _playbackStateController.add(
        const AudioPlaybackState(
          AudioPlaybackStatus.error,
          errorMessage: 'Formato no compatible',
        ),
      );
      return;
    }

    const duration = Duration(minutes: 3);
    _currentItemController.add(
      AudioItem(path: path, title: title, duration: duration, trackId: 1),
    );
    _queueController.add([
      Track(
        id: 1,
        uri: path,
        title: title,
        duration: duration,
        dateAdded: DateTime(2026),
      ),
    ]);
    _indexController.add(0);
    _durationController.add(duration);
    _positionController.add(Duration.zero);
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    final track = tracks[startIndex];
    _queueController.add(List.unmodifiable(tracks));
    _indexController.add(startIndex);
    _currentItemController.add(
      AudioItem(
        path: track.uri,
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        trackId: track.id,
      ),
    );
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> addToQueue(Track track) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> playNext(Track track) async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _repeatController.add(mode);
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    _volumeController.add(value);
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    if (failOnShuffle) {
      throw const AudioPlayerException(
        'No fue posible cambiar el modo aleatorio.',
      );
    }
    _shuffleController.add(enabled);
  }

  @override
  Future<void> skipToIndex(int index) async {
    skippedIndex = index;
  }

  @override
  Future<void> play() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.playing),
    );
  }

  @override
  Future<void> pause() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> stop() async {
    _playbackStateController.add(
      const AudioPlaybackState(AudioPlaybackStatus.paused),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await Future.wait([
      _playbackStateController.close(),
      _positionController.close(),
      _durationController.close(),
      _currentItemController.close(),
      _queueController.close(),
      _indexController.close(),
      _shuffleController.close(),
      _repeatController.close(),
      _volumeController.close(),
    ]);
  }
}
