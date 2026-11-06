import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release conserva los íconos de la notificación de audio', () {
    final config = File('lib/main.dart').readAsStringSync();
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();

    expect(
      config,
      contains("androidNotificationIcon: 'drawable/ic_stat_astramusic'"),
    );
    expect(
      File(
        'android/app/src/main/res/drawable/ic_stat_astramusic.xml',
      ).existsSync(),
      isTrue,
    );
    expect(keep, contains('@drawable/ic_stat_astramusic'));
    expect(keep, contains('@drawable/audio_service_*'));
  });
}
