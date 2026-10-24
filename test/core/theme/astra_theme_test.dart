import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/core/theme/astra_theme.dart';
import 'package:astramusic/core/theme/contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los colores de texto y acento cumplen contraste AA', () {
    const colors = AstraColors.gargantua;
    for (final foreground in [colors.text, colors.textMuted]) {
      expect(
        contrastRatio(foreground, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(foreground, colors.voidColor),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrastRatio(colors.accent, colors.voidColor),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('el tema aplica los tokens Gargantua', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAstraTheme(),
        darkTheme: buildAstraTheme(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final colors = theme.extension<AstraColors>()!;
            expect(theme.useMaterial3, isTrue);
            expect(theme.brightness, Brightness.dark);
            expect(theme.colorScheme.primary, colors.accent);
            expect(theme.colorScheme.onPrimary, colors.onAccent);
            expect(theme.scaffoldBackgroundColor, colors.voidColor);
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
