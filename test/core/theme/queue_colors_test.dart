import 'package:astramusic/core/theme/contrast.dart';
import 'package:astramusic/core/theme/queue_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final background in const [Color(0xFF666600), Color(0xFF050506)]) {
    test('panel translúcido conserva contraste sobre $background', () {
      const text = Color(0xFFF5EBDD);
      final fill = queuePanelFillColor(
        surface: const Color(0xFF0F0D0C),
        text: text,
        background: background,
      );
      final composited = Color.alphaBlend(fill, background);

      expect(fill.a, lessThan(1));
      expect(contrastRatio(text, composited), greaterThanOrEqualTo(4.5));
    });
  }
}
