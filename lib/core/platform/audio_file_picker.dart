import 'package:file_picker/file_picker.dart';

class PickedAudioFile {
  const PickedAudioFile({required this.path, required this.title});

  final String path;
  final String title;
}

abstract interface class AudioFilePicker {
  Future<PickedAudioFile?> pickAudioFile();
  Future<List<PickedAudioFile>> pickAudioFiles();
}

final class SystemAudioFilePicker implements AudioFilePicker {
  const SystemAudioFilePicker();

  @override
  Future<PickedAudioFile?> pickAudioFile() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null) return null;

    return _toPickedAudioFile(file);
  }

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    return files.map(_toPickedAudioFile).toList(growable: false);
  }

  PickedAudioFile _toPickedAudioFile(PlatformFile file) => PickedAudioFile(
    path: file.uri.toString(),
    title: _withoutExtension(file.name),
  );

  String _withoutExtension(String fileName) {
    final extensionStart = fileName.lastIndexOf('.');
    if (extensionStart <= 0) return fileName;
    return fileName.substring(0, extensionStart);
  }
}
