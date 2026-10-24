import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:astramusic/core/platform/library_scanner.dart';
import 'package:astramusic/core/platform/tag_reader.dart';
import 'package:path/path.dart' as path;

const supportedAudioExtensions = <String>{
  '.mp3',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.wav',
};
const desktopScanProgressInterval = 100;

final class DesktopLibraryScanner implements LibraryScanner {
  const DesktopLibraryScanner();

  @override
  Future<LibraryScanTask> startScan({
    String? rootPath,
    Map<String, KnownFileStats> knownFiles = const {},
  }) async {
    if (rootPath == null || rootPath.trim().isEmpty) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'La carpeta es requerida.',
      );
    }

    final root = Directory(path.normalize(path.absolute(rootPath)));
    if (!await root.exists()) {
      throw FileSystemException(
        'La carpeta seleccionada no existe.',
        root.path,
      );
    }

    final receivePort = ReceivePort();
    final controller = StreamController<ScanEvent>();
    var finished = false;
    late final StreamSubscription<Object?> subscription;
    final isolate = await Isolate.spawn<_DesktopScanRequest>(
      _scanDirectory,
      _DesktopScanRequest(root.path, receivePort.sendPort, {
        for (final entry in knownFiles.entries)
          entry.key: [
            entry.value.fileSize,
            entry.value.dateModified?.millisecondsSinceEpoch,
          ],
      }),
      debugName: 'astramusic-library-scan',
    );

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      receivePort.close();
      await subscription.cancel();
      await controller.close();
    }

    subscription = receivePort.listen((message) {
      if (message is! Map<Object?, Object?> || finished) return;
      final type = message['type'];
      final foundCount = message['foundCount'] as int? ?? 0;
      final errorCount = message['errorCount'] as int? ?? 0;
      final unchangedCount = message['unchangedCount'] as int? ?? 0;

      if (type == 'progress') {
        controller.add(
          ScanProgress(
            foundCount: foundCount,
            errorCount: errorCount,
            unchangedCount: unchangedCount,
          ),
        );
        return;
      }

      if (type == 'completed') {
        final rawTracks = message['tracks']! as List<Object?>;
        controller.add(
          ScanCompleted(
            tracks: rawTracks
                .cast<Map<Object?, Object?>>()
                .map(_trackFromMessage)
                .toList(growable: false),
            errorCount: errorCount,
            unchangedCount: unchangedCount,
          ),
        );
        unawaited(finish());
      }
    });

    return LibraryScanTask(controller.stream, () async {
      if (finished) return;
      isolate.kill(priority: Isolate.immediate);
      controller.add(const ScanCancelled());
      await finish();
    });
  }
}

final class _DesktopScanRequest {
  const _DesktopScanRequest(this.rootPath, this.sendPort, this.knownFiles);

  final String rootPath;
  final SendPort sendPort;
  final Map<String, List<int?>> knownFiles;
}

void _scanDirectory(_DesktopScanRequest request) {
  final tracks = <Map<String, Object?>>[];
  var errors = 0;
  var unchanged = 0;

  void reportProgress() {
    request.sendPort.send({
      'type': 'progress',
      'foundCount': tracks.length,
      'errorCount': errors,
      'unchangedCount': unchanged,
    });
  }

  void visit(Directory directory) {
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      errors++;
      reportProgress();
      return;
    }

    for (final entry in entries) {
      if (entry is Directory) {
        if (!path.basename(entry.path).startsWith('.')) visit(entry);
        continue;
      }
      if (entry is! File || !_isSupportedAudio(entry.path)) continue;

      try {
        final stat = entry.statSync();
        final modifiedMs = stat.modified.millisecondsSinceEpoch;
        final known = request.knownFiles[entry.path];
        final isUnchanged =
            known != null && known[0] == stat.size && known[1] == modifiedMs;
        if (isUnchanged) unchanged++;

        AudioTags? tags;
        if (!isUnchanged) {
          final result = readTagsSafely(const AudioMetadataTagReader(), entry);
          tags = result.tags;
          if (result.hadError) errors++;
        }
        tracks.add({
          'uri': entry.path,
          'title': tags?.title ?? path.basenameWithoutExtension(entry.path),
          'artist': tags?.artist,
          'album': tags?.album,
          'durationMs': tags?.durationMs,
          'trackNumber': tags?.trackNumber,
          'year': tags?.year,
          'fileSize': stat.size,
          'dateAddedMs': stat.modified.millisecondsSinceEpoch,
          'dateModifiedMs': modifiedMs,
          'unchanged': isUnchanged,
        });
        if (tracks.length % desktopScanProgressInterval == 0) {
          reportProgress();
        }
      } on FileSystemException {
        errors++;
        reportProgress();
      }
    }
  }

  visit(Directory(request.rootPath));
  reportProgress();
  request.sendPort.send({
    'type': 'completed',
    'foundCount': tracks.length,
    'errorCount': errors,
    'unchangedCount': unchanged,
    'tracks': tracks,
  });
}

bool _isSupportedAudio(String filePath) =>
    supportedAudioExtensions.contains(path.extension(filePath).toLowerCase());

ScannedTrack _trackFromMessage(Map<Object?, Object?> message) => ScannedTrack(
  uri: message['uri']! as String,
  title: message['title']! as String,
  artist: message['artist'] as String?,
  album: message['album'] as String?,
  durationMs: message['durationMs'] as int?,
  trackNumber: message['trackNumber'] as int?,
  year: message['year'] as int?,
  fileSize: message['fileSize'] as int?,
  dateAdded: switch (message['dateAddedMs']) {
    final int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
    _ => null,
  },
  dateModified: switch (message['dateModifiedMs']) {
    final int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
    _ => null,
  },
  unchanged: message['unchanged'] as bool? ?? false,
);
