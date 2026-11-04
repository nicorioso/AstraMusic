import 'dart:io';

import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/core/utils/search_normalization.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;

class MissingTrack {
  const MissingTrack(this.id, this.uri, this.title, this.artist);
  final int id;
  final String uri;
  final String title;
  final String? artist;
}

class RepairResult {
  const RepairResult({required this.repaired, required this.unmatched, required this.ambiguous});
  final int repaired;
  final int unmatched;
  final int ambiguous;
}

/// Solo reasigna coincidencias únicas; conserva el id y las relaciones existentes.
final class MissingTracksService {
  MissingTracksService(this._db);
  final AppDatabase _db;

  Future<List<MissingTrack>> findMissing() async {
    final rows = await _db.select(_db.tracks).get();
    final missing = <MissingTrack>[];
    for (final row in rows) {
      final uri = Uri.tryParse(row.uri);
      if (uri?.scheme != 'file') continue;
      if (!await File.fromUri(uri!).exists()) {
        missing.add(MissingTrack(row.id, row.uri, row.title, row.artist));
      }
    }
    return missing;
  }

  Future<RepairResult> repair(Directory folder) async {
    if (!await folder.exists()) throw FileSystemException('La carpeta no existe', folder.path);
    final candidates = <String, List<File>>{};
    await for (final entity in folder.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final key = normalizeForSearch(path.basenameWithoutExtension(entity.path));
      candidates.putIfAbsent(key, () => []).add(entity);
    }
    final missing = await findMissing();
    var repaired = 0;
    var unmatched = 0;
    var ambiguous = 0;
    final used = <String>{};
    await _db.transaction(() async {
      for (final track in missing) {
        final oldName = path.basenameWithoutExtension(Uri.parse(track.uri).toFilePath());
        final keys = <String>{normalizeForSearch(oldName), normalizeForSearch(track.title)};
        if (track.artist != null) keys.add(normalizeForSearch('${track.artist} - ${track.title}'));
        final matches = <File>{for (final key in keys) ...?candidates[key]};
        if (matches.isEmpty) { unmatched++; continue; }
        if (matches.length != 1) { ambiguous++; continue; }
        final file = matches.single;
        final newUri = file.uri.toString();
        if (!used.add(newUri)) { ambiguous++; continue; }
        final occupied = await (_db.select(_db.tracks)..where((row) => row.uri.equals(newUri))).getSingleOrNull();
        if (occupied != null) { ambiguous++; continue; }
        await (_db.update(_db.tracks)..where((row) => row.id.equals(track.id))).write(
          TracksCompanion(uri: Value(newUri), folderPath: Value(path.dirname(file.path)), isAvailable: const Value(true)),
        );
        repaired++;
      }
    });
    return RepairResult(repaired: repaired, unmatched: unmatched, ambiguous: ambiguous);
  }
}
