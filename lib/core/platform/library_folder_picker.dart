import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

abstract interface class LibraryFolderPicker {
  Future<String?> pickFolder();
}

final class SystemLibraryFolderPicker implements LibraryFolderPicker {
  const SystemLibraryFolderPicker();

  @override
  Future<String?> pickFolder() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecciona una carpeta de música',
    );
    return selected == null ? null : path.normalize(path.absolute(selected));
  }
}
