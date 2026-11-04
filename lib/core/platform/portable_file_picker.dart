import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

abstract interface class PortableFilePicker {
  Future<String?> pickFile(List<String> extensions);
  Future<String?> pickFolder();
  Future<bool> save(String name, Uint8List bytes, String mimeType);
}

final class SystemPortableFilePicker implements PortableFilePicker {
  const SystemPortableFilePicker();

  @override
  Future<String?> pickFile(List<String> extensions) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
    return file?.path;
  }

  @override
  Future<String?> pickFolder() => FilePicker.getDirectoryPath();

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeType);
    return saved != null;
  }
}
