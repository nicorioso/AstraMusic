import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

class PlayCircleButton extends StatefulWidget {
  const PlayCircleButton({
    required this.onPressed,
    required this.isPlaying,
    this.size = 56,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool isPlaying;
  final double size;

  @override
  State<PlayCircleButton> createState() => _PlayCircleButtonState();
}

class _PlayCircleButtonState extends State<PlayCircleButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.isPlaying ? 'Pausar' : 'Reproducir',
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: IconButton(
          onPressed: widget.onPressed,
          iconSize: widget.size * 0.52,
          constraints: BoxConstraints.tightFor(
            width: widget.size,
            height: widget.size,
          ),
          style: IconButton.styleFrom(
            backgroundColor: enabled
                ? (_hovered ? colors.accentHover : colors.accent)
                : colors.textDisabled,
            foregroundColor: colors.onAccent,
            disabledForegroundColor: colors.surface,
          ),
          icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
      ),
    );
  }
}
