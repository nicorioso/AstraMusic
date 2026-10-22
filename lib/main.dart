import 'dart:io';

import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:astramusic/features/player/data/audio_handler_player_service.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:astramusic/features/player/presentation/player_screen.dart';
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
  final playerService = AudioHandlerPlayerService(handler);

  runApp(
    ProviderScope(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(playerService),
        notificationPermissionGrantedProvider.overrideWithValue(
          notificationPermissionGranted,
        ),
      ],
      child: const AstraMusicApp(),
    ),
  );
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
      home: const PlayerScreen(),
    );
  }
}
