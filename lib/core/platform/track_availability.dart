import 'dart:io';
import 'dart:isolate';

import 'package:astramusic/features/library/domain/track_repository.dart';

abstract interface class TrackAvailabilityChecker {
  Future<bool> exists(String uri);
  Future<Map<String, bool>> checkAll(Iterable<String> uris);
}

final class SystemTrackAvailabilityChecker implements TrackAvailabilityChecker {
  const SystemTrackAvailabilityChecker();

  @override
  Future<bool> exists(String uri) async => _locationExists(uri);

  @override
  Future<Map<String, bool>> checkAll(Iterable<String> uris) async {
    final locations = uris.toList(growable: false);
    if (locations.isEmpty) return const {};
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return Isolate.run(() => _checkLocations(locations));
    }
    return _checkLocations(locations);
  }
}

final class TrackAvailabilityService {
  const TrackAvailabilityService(
    this._repository, {
    this.checker = const SystemTrackAvailabilityChecker(),
    this.batchSize = 200,
  });

  final TrackRepository _repository;
  final TrackAvailabilityChecker checker;
  final int batchSize;

  Future<void> refresh() async {
    final tracks = await _repository.watchAll().first;
    final fileTracks = tracks.where((track) => _isFileLocation(track.uri));
    final availability = await checker.checkAll(
      fileTracks.map((track) => track.uri),
    );
    final entries = availability.entries.toList(growable: false);
    for (var offset = 0; offset < entries.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, entries.length);
      await _repository.setAvailability(
        Map.fromEntries(entries.sublist(offset, end)),
      );
    }
  }
}

Map<String, bool> _checkLocations(List<String> uris) => {
  for (final uri in uris) uri: _locationExists(uri),
};

bool _locationExists(String location) {
  if (location.startsWith('content://')) return true;
  final uri = Uri.tryParse(location);
  if (uri != null &&
      uri.scheme.isNotEmpty &&
      uri.scheme != 'file' &&
      location.contains('://')) {
    return true;
  }
  try {
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : location;
    return File(path).existsSync();
  } on Object {
    return false;
  }
}

bool _isFileLocation(String location) {
  if (location.startsWith('content://')) return false;
  final uri = Uri.tryParse(location);
  return uri == null ||
      uri.scheme.isEmpty ||
      uri.scheme == 'file' ||
      !location.contains('://');
}
