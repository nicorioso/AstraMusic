import 'package:astramusic/features/playlists/application/m3u_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:astramusic/features/library/domain/track.dart';

void main() {
  test('exportación sin carpeta destino conserva URI absoluta', () {
    final uri = Uri.file('/music/a.mp3').toString();
    final text = M3uService.encode([Track(uri: uri, title: 'A', dateAdded: DateTime(2026))]);
    expect(text, contains(uri));
  });
  test('analiza BOM, comentarios y rutas relativas; omite URL remotas', () {
    expect(M3uService.parse('\uFEFF#EXTM3U\n#EXTINF:1,Tema\nsub/a.mp3\nhttps://x/a.mp3\n', baseDirectory: '/music'), [Uri.file('/music/sub/a.mp3').toString()]);
  });
}
