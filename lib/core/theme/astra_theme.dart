import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:flutter/material.dart';

const _fontFallback = <String>[
  'Noto Sans CJK JP',
  'Noto Sans CJK SC',
  'Noto Sans CJK KR',
  'Yu Gothic',
  'Meiryo',
  'Microsoft YaHei',
  'Malgun Gothic',
  'sans-serif',
];

ThemeData buildAstraTheme() {
  const colors = AstraColors.gargantua;
  final scheme = ColorScheme.dark(
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.surfaceHover,
    onPrimaryContainer: colors.accent,
    secondary: colors.ember,
    onSecondary: colors.text,
    surface: colors.surface,
    onSurface: colors.text,
    error: colors.error,
    onError: colors.text,
    outline: colors.divider,
    outlineVariant: colors.surfaceHover,
  );
  final typography =
      Typography.material2021(
        platform: TargetPlatform.android,
        colorScheme: scheme,
      ).white.apply(
        fontFamily: 'Inter',
        fontFamilyFallback: _fontFallback,
        bodyColor: colors.text,
        displayColor: colors.text,
      );
  final textTheme = typography.copyWith(
    headlineLarge: typography.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: typography.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: typography.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    titleLarge: typography.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: typography.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: typography.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    bodyMedium: typography.bodyMedium?.copyWith(color: colors.textMuted),
    bodySmall: typography.bodySmall?.copyWith(color: colors.textMuted),
    labelMedium: typography.labelMedium?.copyWith(color: colors.textMuted),
  );
  final pill = OutlineInputBorder(
    borderRadius: BorderRadius.circular(999),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.voidColor,
    canvasColor: colors.surface,
    fontFamily: 'Inter',
    fontFamilyFallback: _fontFallback,
    textTheme: textTheme,
    extensions: const [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.voidColor,
      foregroundColor: colors.text,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: colors.surfaceRaised,
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: colors.divider),
    iconTheme: const IconThemeData(color: colors.textMuted),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.photon,
      inactiveTrackColor: colors.divider,
      thumbColor: colors.photon,
      overlayColor: colors.accent.withValues(alpha: 0.18),
      valueIndicatorColor: colors.surfaceHover,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? colors.accentHover
              : colors.accent,
        ),
        foregroundColor: const WidgetStatePropertyAll(colors.onAccent),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        side: const BorderSide(color: colors.divider),
        minimumSize: const Size(48, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.accent),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.textMuted),
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: 56,
      minLeadingWidth: 48,
      iconColor: colors.textMuted,
      textColor: colors.text,
      subtitleTextStyle: TextStyle(color: colors.textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceRaised,
      indicatorColor: colors.surfaceHover,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textMuted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: colors.surfaceHover,
      contentTextStyle: TextStyle(color: colors.text),
      actionTextColor: colors.accent,
      behavior: SnackBarBehavior.floating,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: colors.surfaceRaised,
      textStyle: TextStyle(color: colors.text),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? colors.accent
            : colors.textDisabled,
      ),
      radius: const Radius.circular(999),
      thickness: const WidgetStatePropertyAll(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceHover,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: colors.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceRaised,
      border: pill,
      enabledBorder: pill,
      focusedBorder: pill.copyWith(
        borderSide: const BorderSide(color: colors.accent, width: 2),
      ),
      hintStyle: const TextStyle(color: colors.textMuted),
      prefixIconColor: colors.textMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  );
}
