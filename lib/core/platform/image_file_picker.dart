import 'package:file_picker/file_picker.dart';

abstract interface class ImageFilePicker {
  Future<String?> pickImage();
}

final class SystemImageFilePicker implements ImageFilePicker {
  const SystemImageFilePicker();

  @override
  Future<String?> pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    return file?.path;
  }
}
