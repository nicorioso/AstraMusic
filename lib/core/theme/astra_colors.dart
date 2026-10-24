import 'package:flutter/material.dart';

@immutable
class AstraColors extends ThemeExtension<AstraColors> {
  const AstraColors({
    required this.voidColor,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.divider,
    required this.accent,
    required this.accentHover,
    required this.ember,
    required this.photon,
    required this.text,
    required this.textMuted,
    required this.textDisabled,
    required this.error,
    required this.onAccent,
    required this.gradientTop,
  });

  static const gargantua = AstraColors(
    voidColor: Color(0xFF050506),
    surface: Color(0xFF0F0D0C),
    surfaceRaised: Color(0xFF1A1613),
    surfaceHover: Color(0xFF241E19),
    divider: Color(0xFF2B231C),
    accent: Color(0xFFF2A33A),
    accentHover: Color(0xFFFFB95A),
    ember: Color(0xFFD9531E),
    photon: Color(0xFFFFE7BF),
    text: Color(0xFFF5EBDD),
    textMuted: Color(0xFFA99B8C),
    textDisabled: Color(0xFF6B5F54),
    error: Color(0xFFE5484D),
    onAccent: Color(0xFF1A0F02),
    gradientTop: Color(0x593D2410),
  );

  final Color voidColor;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color divider;
  final Color accent;
  final Color accentHover;
  final Color ember;
  final Color photon;
  final Color text;
  final Color textMuted;
  final Color textDisabled;
  final Color error;
  final Color onAccent;
  final Color gradientTop;

  @override
  AstraColors copyWith({
    Color? voidColor,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? divider,
    Color? accent,
    Color? accentHover,
    Color? ember,
    Color? photon,
    Color? text,
    Color? textMuted,
    Color? textDisabled,
    Color? error,
    Color? onAccent,
    Color? gradientTop,
  }) => AstraColors(
    voidColor: voidColor ?? this.voidColor,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceHover: surfaceHover ?? this.surfaceHover,
    divider: divider ?? this.divider,
    accent: accent ?? this.accent,
    accentHover: accentHover ?? this.accentHover,
    ember: ember ?? this.ember,
    photon: photon ?? this.photon,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    textDisabled: textDisabled ?? this.textDisabled,
    error: error ?? this.error,
    onAccent: onAccent ?? this.onAccent,
    gradientTop: gradientTop ?? this.gradientTop,
  );

  @override
  AstraColors lerp(covariant AstraColors? other, double t) {
    if (other == null) return this;
    return AstraColors(
      voidColor: Color.lerp(voidColor, other.voidColor, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
      photon: Color.lerp(photon, other.photon, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      error: Color.lerp(error, other.error, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      gradientTop: Color.lerp(gradientTop, other.gradientTop, t)!,
    );
  }
}

extension AstraThemeContext on BuildContext {
  AstraColors get astraColors =>
      Theme.of(this).extension<AstraColors>() ?? AstraColors.gargantua;
}
