import 'dart:async';

import 'package:astramusic/core/platform/desktop_window.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    required this.child,
    required this.window,
    super.key,
  });

  final Widget child;
  final DesktopWindowController window;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  late final OverlayEntry _entry = OverlayEntry(builder: _buildContent);

  @override
  void didUpdateWidget(DesktopWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  Widget _buildContent(BuildContext context) => Column(
    children: [
      DesktopTitleBar(window: widget.window),
      Expanded(child: widget.child),
    ],
  );

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({required this.window, super.key});

  final DesktopWindowController window;

  Future<void> _toggleMaximize() async {
    if (await window.isMaximized()) {
      await window.unmaximize();
    } else {
      await window.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    return Material(
      color: colors.surface,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: const Key('desktop-title-drag-area'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => unawaited(window.startDragging()),
                onDoubleTap: () => unawaited(_toggleMaximize()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 18,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'AstraMusic',
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _WindowControl(
              key: const Key('window-minimize'),
              label: 'Minimizar',
              icon: Icons.remove_rounded,
              onPressed: () => unawaited(window.minimize()),
            ),
            _WindowControl(
              key: const Key('window-maximize'),
              label: 'Maximizar o restaurar',
              icon: Icons.crop_square_rounded,
              onPressed: () => unawaited(_toggleMaximize()),
            ),
            _WindowControl(
              key: const Key('window-close'),
              label: 'Cerrar',
              icon: Icons.close_rounded,
              onPressed: () => unawaited(window.close()),
              close: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowControl extends StatelessWidget {
  const _WindowControl({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.close = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: close ? colors.error : colors.textMuted,
        hoverColor: close
            ? colors.error.withValues(alpha: 0.16)
            : colors.surfaceHover,
        focusColor: colors.surfaceHover,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const RoundedRectangleBorder(),
        ),
      ),
    );
  }
}
