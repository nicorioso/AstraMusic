import 'package:astramusic/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra error y permite reintentar si la base no abre', (
    tester,
  ) async {
    var attempts = 0;
    Future<StartupResources> failingInitializer() async {
      attempts++;
      throw StateError('No se pudo abrir la base de datos');
    }

    await tester.pumpWidget(StartupGate(initializer: failingInitializer));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('startup-error-message')), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.byKey(const Key('startup-retry-button')));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byKey(const Key('startup-error-message')), findsOneWidget);
  });
}
