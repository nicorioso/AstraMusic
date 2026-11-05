import 'dart:io';

import 'package:astramusic/core/platform/desktop_drop_import.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('recorre carpetas, filtra audio y evita rutas duplicadas', () async {
    final root = await Directory.systemTemp.createTemp('astra-drop-');
    addTearDown(() => root.delete(recursive: true));
    final nested = await Directory(path.join(root.path, 'sub')).create();
    final song = await File(path.join(nested.path, 'Tema.MP3')).create();
    await File(path.join(root.path, 'nota.txt')).create();

    final files = await audioFilesFromDrop([
      DropItemDirectory(root.path, const []),
      DropItemFile(song.path),
    ]);
    expect(files, hasLength(1));
    expect(files.single.path, song.path);
    expect(files.single.title, 'Tema');
  });
}
