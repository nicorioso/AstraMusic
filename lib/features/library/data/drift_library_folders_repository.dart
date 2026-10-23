import 'package:astramusic/core/db/app_database.dart';
import 'package:astramusic/features/library/domain/library_folder.dart';
import 'package:astramusic/features/library/domain/library_folders_repository.dart';
import 'package:drift/drift.dart';

final class DriftLibraryFoldersRepository implements LibraryFoldersRepository {
  DriftLibraryFoldersRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<LibraryFolder>> watchAll() {
    final query = _database.select(_database.libraryFolders)
      ..orderBy([
        (folder) => OrderingTerm.asc(folder.path.collate(Collate.noCase)),
      ]);
    return query.watch().map((rows) => List.unmodifiable(rows.map(_toDomain)));
  }

  @override
  Future<LibraryFolder> add(String path) async {
    await _database
        .into(_database.libraryFolders)
        .insert(
          LibraryFoldersCompanion.insert(path: path, addedAt: DateTime.now()),
          mode: InsertMode.insertOrIgnore,
        );
    final query = _database.select(_database.libraryFolders)
      ..where((folder) => folder.path.equals(path));
    return _toDomain(await query.getSingle());
  }

  @override
  Future<void> remove(int id) async {
    await (_database.delete(
      _database.libraryFolders,
    )..where((folder) => folder.id.equals(id))).go();
  }

  @override
  Future<void> markScanned(int id, DateTime scannedAt) async {
    await (_database.update(_database.libraryFolders)
          ..where((folder) => folder.id.equals(id)))
        .write(LibraryFoldersCompanion(lastScannedAt: Value(scannedAt)));
  }

  LibraryFolder _toDomain(LibraryFolderRow row) => LibraryFolder(
    id: row.id,
    path: row.path,
    addedAt: row.addedAt,
    lastScannedAt: row.lastScannedAt,
  );
}
