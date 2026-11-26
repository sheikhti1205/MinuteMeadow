import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class CompanionTheme {
  static const pageInset = 16.0;
  static const controlCorner = 4.0;

  static final light = _theme(_lightColors);
  static final dark = _theme(_darkColors);

  static const _lightColors = ColorScheme.light(
    primary: Color(0xFF1A1A1A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE6E6E6),
    onPrimaryContainer: Color(0xFF111111),
    primaryFixed: Color(0xFFE6E6E6),
    primaryFixedDim: Color(0xFFD4D4D4),
    onPrimaryFixed: Color(0xFF111111),
    onPrimaryFixedVariant: Color(0xFF3D3D3D),
    secondary: Color(0xFF808080),
    onSecondary: Color(0xFF111111),
    secondaryContainer: Color(0xFFECECEC),
    onSecondaryContainer: Color(0xFF1A1A1A),
    secondaryFixed: Color(0xFFECECEC),
    secondaryFixedDim: Color(0xFFDCDCDC),
    onSecondaryFixed: Color(0xFF111111),
    onSecondaryFixedVariant: Color(0xFF3D3D3D),
    tertiary: Color(0xFF4A4A4A),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE9E9E9),
    onTertiaryContainer: Color(0xFF111111),
    tertiaryFixed: Color(0xFFE9E9E9),
    tertiaryFixedDim: Color(0xFFD4D4D4),
    onTertiaryFixed: Color(0xFF111111),
    onTertiaryFixedVariant: Color(0xFF3D3D3D),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFAFAFA),
    onSurface: Color(0xFF111111),
    surfaceDim: Color(0xFFDEDEDE),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF4F4F4),
    surfaceContainerHigh: Color(0xFFEFEFEF),
    surfaceContainerHighest: Color(0xFFE8E8E8),
    onSurfaceVariant: Color(0xFF5C5C5C),
    outline: Color(0xFF6B6B6B),
    outlineVariant: Color(0xFFDADADA),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF1F1F1F),
    onInverseSurface: Color(0xFFF7F7F7),
    inversePrimary: Color(0xFFE6E6E6),
    surfaceTint: Color(0x00000000),
  );

  static const _darkColors = ColorScheme.dark(
    primary: Color(0xFFF2F2F2),
    onPrimary: Color(0xFF111111),
    primaryContainer: Color(0xFFDEDEDE),
    onPrimaryContainer: Color(0xFF111111),
    primaryFixed: Color(0xFFE6E6E6),
    primaryFixedDim: Color(0xFFD4D4D4),
    onPrimaryFixed: Color(0xFF111111),
    onPrimaryFixedVariant: Color(0xFF3D3D3D),
    secondary: Color(0xFF9E9E9E),
    onSecondary: Color(0xFF111111),
    secondaryContainer: Color(0xFF2C2C2C),
    onSecondaryContainer: Color(0xFFF2F2F2),
    secondaryFixed: Color(0xFFECECEC),
    secondaryFixedDim: Color(0xFFDCDCDC),
    onSecondaryFixed: Color(0xFF111111),
    onSecondaryFixedVariant: Color(0xFF3D3D3D),
    tertiary: Color(0xFFC7C7C7),
    onTertiary: Color(0xFF111111),
    tertiaryContainer: Color(0xFF333333),
    onTertiaryContainer: Color(0xFFF2F2F2),
    tertiaryFixed: Color(0xFFE9E9E9),
    tertiaryFixedDim: Color(0xFFD4D4D4),
    onTertiaryFixed: Color(0xFF111111),
    onTertiaryFixedVariant: Color(0xFF3D3D3D),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF111111),
    onSurface: Color(0xFFF2F2F2),
    surfaceDim: Color(0xFF0B0B0B),
    surfaceBright: Color(0xFF333333),
    surfaceContainerLowest: Color(0xFF0B0B0B),
    surfaceContainerLow: Color(0xFF1A1A1A),
    surfaceContainer: Color(0xFF1F1F1F),
    surfaceContainerHigh: Color(0xFF252525),
    surfaceContainerHighest: Color(0xFF2C2C2C),
    onSurfaceVariant: Color(0xFFB0B0B0),
    outline: Color(0xFFA8A8A8),
    outlineVariant: Color(0xFF2E2E2E),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF2F2F2),
    onInverseSurface: Color(0xFF111111),
    inversePrimary: Color(0xFF1A1A1A),
    surfaceTint: Color(0x00000000),
  );

  static ThemeData _theme(ColorScheme colors) {
    final base = ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        elevation: 0,
        indicatorShape: StadiumBorder(
          side: BorderSide(color: colors.outline),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant;
          return IconThemeData(color: color, size: 21);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
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
