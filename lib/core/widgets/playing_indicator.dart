import 'dart:math' as math;

import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({required this.playing, super.key});

  final bool playing;

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final animate =
        widget.playing &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const Key('playing-indicator-boundary'),
    child: SizedBox(
      key: const Key('playing-indicator'),
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _BarsPainter(
            progress: _controller.value,
            color: context.astraColors.accent,
            active: _controller.isAnimating,
          ),
        ),
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.progress,
    required this.color,
    required this.active,
  });

  final double progress;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 3; index++) {
      final wave = active
          ? (math.sin((progress * math.pi * 2) + index * 1.8) + 1) / 2
          : 0.35 + index * 0.12;
      final height = 5 + wave * (size.height - 7);
      final x = 3.0 + index * 6;
      canvas.drawLine(
        Offset(x, size.height - 2),
        Offset(x, size.height - 2 - height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.active != active;
}
