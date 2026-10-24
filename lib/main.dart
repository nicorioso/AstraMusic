import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/presentation/library_screen.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/application/playback_persistence_coordinator.dart';
import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:astramusic/features/player/data/audio_handler_player_service.dart';
import 'package:astramusic/features/player/data/drift_playback_state_repository.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

  final notificationPermissionGranted = await _requestNotificationPermission();
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
  final database = AppDatabase();
  final persistence = PlaybackPersistenceCoordinator(
    playerService,
    DriftPlaybackStateRepository(database),
  );
  await persistence.start();

  runApp(
    ProviderScope(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(playerService),
        notificationPermissionGrantedProvider.overrideWithValue(
          notificationPermissionGranted,
        ),
        artworkProviderProvider.overrideWithValue(artworkProvider),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: PlaybackLifecycle(
        coordinator: persistence,
        child: const AstraMusicApp(),
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

class AstraMusicApp extends StatelessWidget {
  const AstraMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AstraMusic',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const LibraryScreen(),
    );
  }
}
