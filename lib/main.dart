import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/diagnostics/performance_diagnostics.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/platform/track_availability.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/core/widgets/responsive_shell.dart';
import 'package:astramusic/features/library/data/drift_track_repository.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/application/playback_persistence_coordinator.dart';
import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:astramusic/features/player/data/audio_handler_player_service.dart';
import 'package:astramusic/features/player/data/drift_playback_state_repository.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runZonedGuarded(() {
    PerformanceDiagnostics.instance.startStartup();
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isAndroid) {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
    }
    FlutterError.onError = (details) {
      _logStartupError(details.exception, details.stack ?? StackTrace.current);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _logStartupError(error, stack);
      return true;
    };
    runApp(const StartupGate(initializer: initializeAstraMusic));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceDiagnostics.instance.recordFirstFrame();
    });
  }, _logStartupError);
}

@visibleForTesting
Future<StartupResources> initializeAstraMusic() async {
  AppDatabase? database;
  try {
    if (Platform.isLinux || Platform.isWindows) {
      JustAudioMediaKit.ensureInitialized();
    }
    final notificationPermissionGranted =
        await _requestNotificationPermission();
    final handler = await AudioService.init<AstraAudioHandler>(
      builder: AstraAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nicorioso.astramusic.channel.audio',
        androidNotificationChannelName: 'AstraMusic',
        androidNotificationChannelDescription: 'Reproducción de audio local',
        androidStopForegroundOnPause: false,
      ),
    );
    final artworkProvider = CachedArtworkProvider();
    final playerService = AudioHandlerPlayerService(
      handler,
      artworkProvider: artworkProvider,
    );
    database = AppDatabase();
    await database.customSelect('SELECT 1').getSingle();
    final persistence = PlaybackPersistenceCoordinator(
      playerService,
      DriftPlaybackStateRepository(database),
    );
    unawaited(
      persistence.start().catchError(
        (Object error, StackTrace stack) => _logStartupError(error, stack),
      ),
    );
    unawaited(
      TrackAvailabilityService(DriftTrackRepository(database))
          .refresh()
          .catchError(
            (Object error, StackTrace stack) => _logStartupError(error, stack),
          ),
    );
    return StartupResources(
      database: database,
      playerService: playerService,
      artworkProvider: artworkProvider,
      persistence: persistence,
      notificationPermissionGranted: notificationPermissionGranted,
    );
  } catch (_) {
    await database?.close();
    rethrow;
  }
}

@visibleForTesting
final class StartupResources {
  const StartupResources({
    required this.database,
    required this.playerService,
    required this.artworkProvider,
    required this.persistence,
    required this.notificationPermissionGranted,
  });

  final AppDatabase database;
  final AudioHandlerPlayerService playerService;
  final ArtworkProvider artworkProvider;
  final PlaybackPersistenceCoordinator persistence;
  final bool notificationPermissionGranted;
}

@visibleForTesting
class StartupGate extends StatefulWidget {
  const StartupGate({required this.initializer, super.key});

  final Future<StartupResources> Function() initializer;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  StartupResources? _resources;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (!_loading) setState(() => _loading = true);
    setState(() => _error = null);
    try {
      final resources = await widget.initializer().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _resources = resources;
        _loading = false;
      });
    } catch (error, stack) {
      _logStartupError(error, stack);
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resources = _resources;
    if (resources != null) {
      return ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(resources.playerService),
          notificationPermissionGrantedProvider.overrideWithValue(
            resources.notificationPermissionGranted,
          ),
          artworkProviderProvider.overrideWithValue(resources.artworkProvider),
          appDatabaseProvider.overrideWithValue(resources.database),
        ],
        child: PlaybackLifecycle(
          coordinator: resources.persistence,
          child: const AstraMusicApp(),
        ),
      );
    }
    return MaterialApp(
      title: 'AstraMusic',
      theme: buildAstraTheme(),
      darkTheme: buildAstraTheme(),
      themeMode: ThemeMode.dark,
      home: _error == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : StartupErrorScreen(error: _error!, onRetry: _initialize),
    );
  }
}

@visibleForTesting
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'No fue posible iniciar AstraMusic.\n$error',
              key: const Key('startup-error-message'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('startup-retry-button'),
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlaybackLifecycle extends StatefulWidget {
  const PlaybackLifecycle({
    required this.coordinator,
    required this.child,
    super.key,
  });

  final PlaybackPersistenceCoordinator coordinator;
  final Widget child;

  @override
  State<PlaybackLifecycle> createState() => _PlaybackLifecycleState();
}

class _PlaybackLifecycleState extends State<PlaybackLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onPause: () => unawaited(widget.coordinator.flush()),
      onDetach: () => unawaited(widget.coordinator.flush()),
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    unawaited(widget.coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> _requestNotificationPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final status = await Permission.notification.request();
    return status.isGranted;
  } catch (_) {
    return false;
  }
}

void _logStartupError(Object error, StackTrace stack) {
  if (kDebugMode) debugPrint('AstraMusic: $error\n$stack');
}

class AstraMusicApp extends StatelessWidget {
  const AstraMusicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AstraMusic',
    theme: buildAstraTheme(),
    darkTheme: buildAstraTheme(),
    themeMode: ThemeMode.dark,
    home: const ResponsiveShell(),
  );
}
