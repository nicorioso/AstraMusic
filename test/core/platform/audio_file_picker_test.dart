import 'package:astramusic/core/platform/audio_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefiere la ruta local y conserva content URI cuando no existe', () {
    expect(
      pickedFileLocation(
        localPath: '/música/canción.mp3',
        uri: Uri.file('/música/canción.mp3'),
      ),
      '/música/canción.mp3',
    );
    expect(
      pickedFileLocation(
        localPath: null,
        uri: Uri.parse('content://media/external/audio/media/1'),
      ),
      'content://media/external/audio/media/1',
    );
  });
}
