import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

class AstraBackground extends StatelessWidget {
  const AstraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.voidColor,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.gradientTop, colors.voidColor.withValues(alpha: 0)],
        ),
      ),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
