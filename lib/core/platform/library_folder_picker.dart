import 'package:file_picker/file_picker.dart';

abstract interface class LibraryFolderPicker {
  Future<String?> pickFolder();
}

final class SystemLibraryFolderPicker implements LibraryFolderPicker {
  const SystemLibraryFolderPicker();

  @override
  Future<String?> pickFolder() => FilePicker.getDirectoryPath(
    dialogTitle: 'Selecciona una carpeta de música',
  );
}
