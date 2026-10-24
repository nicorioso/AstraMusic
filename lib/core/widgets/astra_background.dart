import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

class AstraBackground extends StatelessWidget {
  const AstraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    return ColoredBox(
      color: colors.voidColor,
      child: Stack(
        children: [
          Container(
            height: 300,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.gradientTop,
                  colors.voidColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
