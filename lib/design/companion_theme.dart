import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class CompanionTheme {
  static const pageInset = 16.0;
  static const controlCorner = 4.0;

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
    surfaceContainer: Color(0xFFF1E6D7),
    secondaryContainer: Color(0xFFE1E8D2),
    onSecondaryContainer: Color(0xFF252D1C),
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
    surfaceContainer: Color(0xFF322923),
    secondaryContainer: Color(0xFF424F35),
    onSecondaryContainer: Color(0xFFE1EBD4),
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(controlCorner)),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant;
          return IconThemeData(color: color, size: 21);
        }),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(controlCorner)),
          ),
        ),
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
