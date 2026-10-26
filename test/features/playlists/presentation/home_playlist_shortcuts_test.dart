import 'package:astramusic/features/playlists/domain/playlist.dart';
import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prioriza recientes y rellena con favoritos y creación descendente', () {
    final all = [
      _playlist(1, day: 1),
      _playlist(2, day: 4),
      _playlist(3, day: 3),
      _playlist(4, day: 2),
    ];

    final result = composeHomePlaylistShortcuts(
      recent: [all[2], all[0]],
      all: all,
    );

    expect(result.map((item) => item.isFavorites ? -1 : item.playlist!.id), [
      3,
      1,
      -1,
      2,
      4,
    ]);
  });

  test('elimina duplicados y limita a ocho accesos', () {
    final all = List.generate(10, (index) => _playlist(index + 1, day: index));

    final result = composeHomePlaylistShortcuts(
      recent: [all[0], all[0], ...all.skip(1).take(7)],
      all: all,
    );

    expect(result, hasLength(8));
    expect(result.where((item) => item.isFavorites), isEmpty);
    expect(result.map((item) => item.playlist!.id).toSet(), hasLength(8));
  });

  test('sin playlists no muestra accesos, incluso con favoritos', () {
    expect(
      composeHomePlaylistShortcuts(recent: const [], all: const []),
      isEmpty,
    );
  });
}

Playlist _playlist(int id, {required int day}) => Playlist(
  id: id,
  name: 'Playlist $id',
  trackCount: id,
  addedAt: DateTime(2026, 1, day + 1),
  createdAt: DateTime(2026, 1, day + 1),
  updatedAt: DateTime(2026, 1, day + 1),
);
