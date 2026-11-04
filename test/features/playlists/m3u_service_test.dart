import 'package:astramusic/features/playlists/application/m3u_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analiza BOM, comentarios y rutas relativas; omite URL remotas', () {
    expect(M3uService.parse('\uFEFF#EXTM3U\n#EXTINF:1,Tema\nsub/a.mp3\nhttps://x/a.mp3\n', baseDirectory: '/music'), [Uri.file('/music/sub/a.mp3').toString()]);
  });
}
