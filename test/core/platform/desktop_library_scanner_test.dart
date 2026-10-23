import 'dart:io';

import 'package:astramusic/core/platform/desktop_library_scanner.dart';
import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('encuentra audio recursivo e ignora carpetas ocultas', () async {
    final root = await Directory.systemTemp.createTemp('astramusic_scan_');
    addTearDown(() => root.delete(recursive: true));

    final nested = await Directory(path.join(root.path, 'subcarpeta')).create();
    final hidden = await Directory(path.join(root.path, '.oculta')).create();
    await File(path.join(root.path, 'Primera.MP3')).writeAsBytes([1]);
    await File(path.join(nested.path, 'Segunda.flac')).writeAsBytes([2, 3]);
    await File(path.join(nested.path, 'nota.txt')).writeAsString('ignorar');
    await File(path.join(hidden.path, 'Secreta.ogg')).writeAsBytes([4]);

    final task = await const DesktopLibraryScanner().startScan(
      rootPath: root.path,
    );
    final events = await task.events.toList();
    final completed = events.whereType<ScanCompleted>().single;

    expect(completed.errorCount, 0);
    expect(
      completed.tracks.map((track) => track.title),
      unorderedEquals(['Primera', 'Segunda']),
    );
    expect(
      completed.tracks.map((track) => path.extension(track.uri).toLowerCase()),
      unorderedEquals(['.mp3', '.flac']),
    );
    expect(completed.tracks.every((track) => track.fileSize != null), isTrue);
    expect(completed.tracks.every((track) => track.dateAdded != null), isTrue);
    expect(events.whereType<ScanProgress>(), isNotEmpty);
  });
}
