import 'package:astramusic/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el nombre de la aplicación', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AstraMusicApp()));

    expect(find.text('AstraMusic'), findsOneWidget);
  });
}
