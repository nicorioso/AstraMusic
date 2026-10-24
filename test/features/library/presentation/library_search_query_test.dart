import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aplica la búsqueda después de 300 ms', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(librarySearchQueryProvider.notifier);

      notifier.update('canción');
      async.elapse(const Duration(milliseconds: 299));
      expect(container.read(librarySearchQueryProvider), isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(container.read(librarySearchQueryProvider), 'canción');
    });
  });

  test('reinicia el debounce y limpiar se aplica inmediatamente', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(librarySearchQueryProvider.notifier);

      notifier.update('can');
      async.elapse(const Duration(milliseconds: 200));
      notifier.update('canción');
      async.elapse(const Duration(milliseconds: 200));
      expect(container.read(librarySearchQueryProvider), isEmpty);

      notifier.update('');
      expect(container.read(librarySearchQueryProvider), isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(container.read(librarySearchQueryProvider), isEmpty);
    });
  });
}
