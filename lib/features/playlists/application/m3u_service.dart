import 'dart:convert';
import 'dart:io';

import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/domain/track_repository.dart';
import 'package:astramusic/features/playlists/domain/playlist_repository.dart';
import 'package:path/path.dart' as path;

/// Intercambia listas extendidas UTF-8 sin agregar archivos ajenos a la biblioteca.
final class M3uService {
  M3uService(this._playlists, this._tracks);

  final PlaylistRepository _playlists;
  final SyncTrackRepository _tracks;

  static List<String> parse(String source, {required String baseDirectory}) {
    final entries = <String>[];
    for (final raw in const LineSplitter().convert(source.replaceFirst('\uFEFF', ''))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final uri = Uri.tryParse(line);
      if (uri == null) continue;
      if (uri.hasScheme && uri.scheme != 'file' && uri.scheme != 'content') continue;
      if (uri.scheme == 'content') {
        entries.add(uri.toString());
      } else {
        final local = uri.scheme == 'file' ? uri.toFilePath() : line;
        final resolved = path.normalize(path.isAbsolute(local) ? local : path.join(baseDirectory, local));
        entries.add(Uri.file(resolved).toString());
      }
    }
    return entries;
  }

  static String encode(Iterable<Track> tracks, {String? baseDirectory}) {
    final lines = <String>['#EXTM3U'];
    for (final track in tracks) {
      final uri = Uri.tryParse(track.uri);
      final location = uri?.scheme == 'file'
          ? (baseDirectory == null ? track.uri : path.relative(uri!.toFilePath(), from: baseDirectory))
          : track.uri;
      lines.add(location);
    }
    return '${lines.join('\n')}\n';
  }

  Future<void> export(int playlistId, File target) async {
    final playlist = await _playlists.watchById(playlistId).first;
    if (playlist == null) throw StateError('La playlist no existe.');
    final tracks = await _playlists.watchTracks(playlistId).first;
    await target.writeAsString(
      encode(tracks, baseDirectory: target.parent.path),
      encoding: utf8,
      flush: true,
    );
  }

  Future<({int playlistId, int added, int missing})> import(
    File source, {required String name}
  ) async {
    final entries = parse(
      await source.readAsString(encoding: utf8),
      baseDirectory: source.parent.path,
    );
    final found = await _tracks.findByUris(entries.toSet());
    final byUri = {for (final track in found) track.uri: track};
    final ids = <int>[];
    var missing = 0;
    for (final entry in entries) {
      final id = byUri[entry]?.id;
      if (id == null) { missing++; } else { ids.add(id); }
    }
    final playlist = await _playlists.create(name);
    final result = await _playlists.addTracks(playlist.id, ids);
    return (playlistId: playlist.id, added: result.added, missing: missing);
  }
}
