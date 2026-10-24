import 'dart:async';

import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

const seekConfirmationTolerance = Duration(seconds: 1);
const seekConfirmationTimeout = Duration(milliseconds: 1500);

class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.compact = false,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration>? onSeek;
  final bool compact;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  Duration? _dragPosition;
  Duration? _pendingTarget;
  Timer? _confirmationTimer;
  bool _dragging = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(SeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _pendingTarget;
    if (!_dragging &&
        target != null &&
        (widget.position - target).abs() <= seekConfirmationTolerance) {
      _confirmationTimer?.cancel();
      _pendingTarget = null;
    }
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration ?? Duration.zero;
    final enabled = duration > Duration.zero && widget.onSeek != null;
    final displayedPosition = _clampPosition(
      _dragPosition ?? _pendingTarget ?? widget.position,
      duration,
    );
    final maxMilliseconds = enabled ? duration.inMilliseconds.toDouble() : 1.0;

    final slider = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SliderTheme(
        data: Theme.of(context).sliderTheme.copyWith(
          activeTrackColor: _hovered
              ? context.astraColors.accent
              : context.astraColors.photon,
          thumbColor: _hovered
              ? context.astraColors.accent
              : context.astraColors.photon,
        ),
        child: Slider(
          key: const Key('seek-slider'),
          value: displayedPosition.inMilliseconds.toDouble(),
          max: maxMilliseconds,
          onChangeStart: enabled ? _startDrag : null,
          onChanged: enabled ? _updateDrag : null,
          onChangeEnd: enabled ? _finishDrag : null,
        ),
      ),
    );
    if (widget.compact) {
      return Row(
        children: [
          Text(_formatDuration(displayedPosition)),
          Expanded(child: slider),
          Text(_formatDuration(duration)),
        ],
      );
    }
    return Column(
      children: [
        slider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(displayedPosition),
              key: const Key('seek-position-label'),
            ),
            Text(
              _formatDuration(duration),
              key: const Key('seek-duration-label'),
            ),
          ],
        ),
      ],
    );
  }

  void _startDrag(double value) {
    _confirmationTimer?.cancel();
    setState(() {
      _dragging = true;
      _pendingTarget = null;
      _dragPosition = Duration(milliseconds: value.round());
    });
  }

  void _updateDrag(double value) {
    setState(() {
      _dragPosition = Duration(milliseconds: value.round());
    });
  }

  void _finishDrag(double value) {
    final duration = widget.duration ?? Duration.zero;
    final target = _clampPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    setState(() {
      _dragging = false;
      _dragPosition = null;
      _pendingTarget = target;
    });
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(seekConfirmationTimeout, () {
      if (!mounted) return;
      setState(() => _pendingTarget = null);
    });
    widget.onSeek?.call(target);
  }
}

Duration _clampPosition(Duration position, Duration duration) {
  if (duration <= Duration.zero || position.isNegative) return Duration.zero;
  if (position > duration) return duration;
  return position;
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
