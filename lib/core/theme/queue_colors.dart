import 'package:astramusic/core/theme/contrast.dart';
import 'package:flutter/material.dart';

const queuePanelInitialOpacity = 0.38;
const queuePanelMaximumOpacity = 0.9;
const queueCurrentRowOpacity = 0.14;
const queueHoverOpacity = 0.06;

Color queuePanelFillColor({
  required Color surface,
  required Color text,
  required Color background,
}) {
  var opacity = queuePanelInitialOpacity;
  while (opacity <= queuePanelMaximumOpacity) {
    final fill = surface.withValues(alpha: opacity);
    final composited = Color.alphaBlend(fill, background);
    if (contrastRatio(text, composited) >= 4.5) return fill;
    opacity += 0.05;
  }
  return surface.withValues(alpha: queuePanelMaximumOpacity);
}
