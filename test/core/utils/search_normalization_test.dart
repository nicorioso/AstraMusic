import 'package:astramusic/core/utils/search_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza acentos, eñe, mayúsculas y espacios', () {
    expect(
      normalizeForSearch('  CANCIÓN   NIÑA  pingüino '),
      'cancion nina pinguino',
    );
  });

  test('conserva japonés y cirílico y aplica minúsculas', () {
    expect(normalizeForSearch(' 東京  ПРИВЕТ '), '東京 привет');
  });

  test('normaliza una cadena vacía', () {
    expect(normalizeForSearch('   '), isEmpty);
  });
}
