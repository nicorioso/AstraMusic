import 'package:astramusic/features/library/domain/library_folder.dart';

abstract interface class LibraryFoldersRepository {
  Stream<List<LibraryFolder>> watchAll();
  Future<LibraryFolder> add(String path);
  Future<void> remove(int id);
  Future<void> markScanned(int id, DateTime scannedAt);
}
