import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

  runApp(const ProviderScope(child: AstraMusicApp()));
}

class AstraMusicApp extends StatelessWidget {
  const AstraMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'AstraMusic',
      home: Scaffold(body: Center(child: Text('AstraMusic'))),
    );
  }
}
