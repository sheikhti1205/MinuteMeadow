import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class CompanionTheme {
  static const pageInset = 16.0;

  static final light = _theme(_lightColors);
  static final dark = _theme(_darkColors);

  static const _lightColors = ColorScheme.light(
    primary: Color(0xFF873829),
    onPrimary: Color(0xFFFFF9EE),
    secondary: Color(0xFF4E5940),
    onSecondary: Color(0xFFFFF9EE),
    surface: Color(0xFFFFF9EE),
    onSurface: Color(0xFF251E1A),
    onSurfaceVariant: Color(0xFF5E5149),
    outline: Color(0xFF78675C),
    error: Color(0xFF9C2828),
    onError: Color(0xFFFFFAF3),
  );

  static const _darkColors = ColorScheme.dark(
    primary: Color(0xFFFFAB97),
    onPrimary: Color(0xFF40110B),
    secondary: Color(0xFFBACAA4),
    onSecondary: Color(0xFF243017),
    surface: Color(0xFF211B18),
    onSurface: Color(0xFFFCECDF),
    onSurfaceVariant: Color(0xFFCEBCAE),
    outline: Color(0xFFAE9989),
    error: Color(0xFFFFB4A9),
    onError: Color(0xFF580E0B),
  );

  static ThemeData _theme(ColorScheme colors) {
    final base = ThemeData(colorScheme: colors, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
