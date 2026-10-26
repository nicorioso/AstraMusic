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
    final scannedTracks = events
        .whereType<ScanBatch>()
        .expand((event) => event.tracks)
        .toList();

    expect(completed.errorCount, 2);
    expect(
      scannedTracks.map((track) => track.title),
      unorderedEquals(['Primera', 'Segunda']),
    );
    expect(
      scannedTracks.map((track) => path.extension(track.uri).toLowerCase()),
      unorderedEquals(['.mp3', '.flac']),
    );
    expect(scannedTracks.every((track) => track.fileSize != null), isTrue);
    expect(scannedTracks.every((track) => track.dateAdded != null), isTrue);
    expect(scannedTracks.every((track) => track.dateModified != null), isTrue);
    expect(events.whereType<ScanProgress>(), isNotEmpty);
  });

  test(
    'omite etiquetas sin cambios y relee solo el archivo modificado',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'astramusic_incremental_',
      );
      addTearDown(() => root.delete(recursive: true));
      final unchangedFile = await File(path.join(root.path, 'estable.mp3'))
          .writeAsBytes([1]);
      final changedFile = await File(path.join(root.path, 'cambia.flac'))
          .writeAsBytes([2]);

      final first = await _completedScan(root.path);
      expect(first.errorCount, 2);
      final known = {
        for (final track in first.tracks)
          track.uri: KnownFileStats(
            fileSize: track.fileSize,
            dateModified: track.dateModified,
          ),
      };

      final second = await _completedScan(root.path, knownFiles: known);
      expect(second.errorCount, 0);
      expect(second.unchangedCount, 2);
      expect(second.tracks.every((track) => track.unchanged), isTrue);

      await changedFile.writeAsBytes([2, 3, 4]);
      await changedFile.setLastModified(
        known[changedFile.path]!.dateModified!.add(const Duration(seconds: 2)),
      );
      final third = await _completedScan(root.path, knownFiles: known);

      expect(third.errorCount, 1);
      expect(third.unchangedCount, 1);
      expect(
        third.tracks
            .singleWhere((track) => track.uri == unchangedFile.path)
            .unchanged,
        isTrue,
      );
      expect(
        third.tracks
            .singleWhere((track) => track.uri == changedFile.path)
            .unchanged,
        isFalse,
      );
    },
  );
}

Future<ScanCompleted> _completedScan(
  String rootPath, {
  Map<String, KnownFileStats> knownFiles = const {},
}) async {
  final task = await const DesktopLibraryScanner().startScan(
    rootPath: rootPath,
    knownFiles: knownFiles,
  );
  final events = await task.events.toList();
  final completed = events.whereType<ScanCompleted>().single;
  return ScanCompleted(
    tracks: events
        .whereType<ScanBatch>()
        .expand((event) => event.tracks)
        .toList(growable: false),
    errorCount: completed.errorCount,
    unchangedCount: completed.unchangedCount,
  );
}
