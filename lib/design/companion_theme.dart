import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'appearance_preferences.dart';

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

  /// Builds the shared chrome for saved appearance choices.
  ///
  /// [systemSeed] is the optional platform colour hook for
  /// [AppPalette.system]. When it is null, System stays grayscale instead of
  /// inventing a hue. AMOLED affects the dark result only.
  static ThemeData forAppearance(
    AppearancePreferences appearance, {
    required Brightness brightness,
    Color? systemSeed,
  }) => _theme(
    schemeFor(appearance, brightness: brightness, systemSeed: systemSeed),
    appFontFamily: appearance.appFont.family,
    timerFontFamily: appearance.timerFont.family,
  );

  /// Resolves a saved appearance into a Material colour scheme.
  ///
  /// The grayscale palette returns the original light or dark scheme
  /// unchanged. Every other palette seeds a Material scheme through the same
  /// path: authored palettes carry their own seed, and [AppPalette.system]
  /// takes the platform [systemSeed]. When that seed is unavailable the result
  /// stays grayscale, which is the safety net for an older saved value; the
  /// editor disables the choice instead of offering a silent no-op. A custom
  /// surface and a dark AMOLED result settle the background roles first, then
  /// the custom accent is checked against that final surface: it is kept
  /// exactly when it already clears the 4.5:1 ordinary-text threshold, and
  /// otherwise moved toward the readable neutral until it does.
  static ColorScheme schemeFor(
    AppearancePreferences appearance, {
    required Brightness brightness,
    Color? systemSeed,
  }) {
    final grayscale = brightness == Brightness.dark
        ? _darkColors
        : _lightColors;
    final palette = appearance.palette;
    final seed = palette == AppPalette.system ? systemSeed : palette.seed;
    var scheme = seed == null
        ? grayscale
        : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final surface = appearance.customSurface;
    if (surface != null) {
      scheme = _withSurface(scheme, surface);
    }

    if (appearance.amoled && brightness == Brightness.dark) {
      scheme = _withAmoled(scheme);
    }

    // Primary is also the default foreground for links and buttons, so a
    // custom accent needs the ordinary-text threshold against the surface
    // that survived the overrides above, not the 3:1 non-text one.
    final accent = appearance.customAccent;
    if (accent != null) {
      final visibleAccent = _readableAccent(accent, scheme.surface);
      scheme = scheme.copyWith(
        primary: visibleAccent,
        onPrimary: readableOn(visibleAccent),
        inversePrimary: visibleAccent,
      );
    }
    return scheme;
  }

  /// WCAG 2.2 relative-contrast ratio for two opaque colours.
  static double contrastRatio(Color first, Color second) {
    final a = first.computeLuminance();
    final b = second.computeLuminance();
    final lighter = math.max(a, b);
    final darker = math.min(a, b);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Black or white, whichever reads more strongly on [background].
  ///
  /// One of the two always clears 4.58:1 for any opaque colour, so custom
  /// surfaces keep readable text without a colour picker limit.
  static Color readableOn(Color background) =>
      contrastRatio(background, const Color(0xFFFFFFFF)) >=
          contrastRatio(background, const Color(0xFF000000))
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  /// Keeps [accent] exactly when it already reads on [background], otherwise
  /// blends it toward the readable neutral until it clears 4.5:1.
  ///
  /// Ordinary-size text and icons need 4.5:1, and Primary is a foreground as
  /// well as a fill. The neutral clears 4.58:1 for any opaque background, so
  /// the blend always reaches a readable colour within the 5% steps; an accent
  /// that is already valid is never altered.
  static Color _readableAccent(Color accent, Color background) {
    const minimum = 4.5;
    if (contrastRatio(accent, background) >= minimum) return accent;
    final neutral = readableOn(background);
    for (var step = 1; step <= 20; step++) {
      final blend = Color.alphaBlend(
        neutral.withValues(alpha: step / 20),
        accent,
      );
      if (contrastRatio(blend, background) >= minimum) return blend;
    }
    return neutral;
  }

  /// Rebuilds the surface roles around a custom colour.
  ///
  /// [readableOn] fixes the text colour from the exact surface, then the
  /// elevation colours move away from it for depth. A moved colour can reach a
  /// luminance where neither black nor white text clears 4.5:1, so each one is
  /// blended back toward the surface until the text stays readable. Text roles
  /// are chosen with a margin so they also hold on those adjacent surfaces.
  static ColorScheme _withSurface(ColorScheme scheme, Color surface) {
    final onSurface = readableOn(surface);
    final dark = surface.computeLuminance() < 0.5;
    final tint = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    const dim = Color(0xFF000000);
    const bright = Color(0xFFFFFFFF);

    Color mix(double amount) =>
        Color.alphaBlend(tint.withValues(alpha: amount), surface);
    Color readable(Color candidate, double minimum, Color fallback) =>
        contrastRatio(candidate, surface) >= minimum ? candidate : fallback;

    Color tinted(Color color) {
      var result = color;
      for (var step = 0; step < 6; step++) {
        if (contrastRatio(onSurface, result) >= 4.5) return result;
        result = Color.alphaBlend(surface.withValues(alpha: 0.35), result);
      }
      return contrastRatio(onSurface, result) >= 4.5 ? result : surface;
    }

    final onSurfaceVariant = readable(mix(0.62), 5.2, onSurface);
    final outline = readable(mix(0.52), 3.4, onSurface);
    final error = readable(scheme.error, 4.5, onSurface);
    final primary = readable(scheme.primary, 3.4, onSurface);
    final primaryContainer = tinted(
      dark
          ? mix(0.18)
          : Color.alphaBlend(dim.withValues(alpha: 0.07), surface),
    );
    final secondaryContainer = tinted(
      dark
          ? mix(0.12)
          : Color.alphaBlend(dim.withValues(alpha: 0.05), surface),
    );
    final tertiaryContainer = tinted(
      dark
          ? mix(0.10)
          : Color.alphaBlend(dim.withValues(alpha: 0.04), surface),
    );
    final errorContainer = Color.alphaBlend(
      error.withValues(alpha: dark ? 0.30 : 0.14),
      surface,
    );

    return scheme.copyWith(
      primary: primary,
      onPrimary: readableOn(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: onSurface,
      secondary: onSurfaceVariant,
      onSecondary: readableOn(onSurfaceVariant),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSurface,
      tertiary: outline,
      onTertiary: readableOn(outline),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onSurface,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: Color.alphaBlend(
        tint.withValues(alpha: 0.16),
        surface,
      ),
      surfaceDim: tinted(
        Color.alphaBlend(dim.withValues(alpha: dark ? 0.26 : 0.10), surface),
      ),
      surfaceBright: tinted(
        dark
            ? Color.alphaBlend(bright.withValues(alpha: 0.18), surface)
            : bright,
      ),
      surfaceContainerLowest: tinted(
        dark
            ? Color.alphaBlend(dim.withValues(alpha: 0.30), surface)
            : Color.alphaBlend(bright.withValues(alpha: 0.65), surface),
      ),
      surfaceContainerLow: tinted(
        dark
            ? mix(0.04)
            : Color.alphaBlend(bright.withValues(alpha: 0.35), surface),
      ),
      surfaceContainer: tinted(
        dark
            ? mix(0.07)
            : Color.alphaBlend(dim.withValues(alpha: 0.03), surface),
      ),
      surfaceContainerHigh: tinted(
        dark
            ? mix(0.10)
            : Color.alphaBlend(dim.withValues(alpha: 0.05), surface),
      ),
      surfaceContainerHighest: tinted(
        dark
            ? mix(0.14)
            : Color.alphaBlend(dim.withValues(alpha: 0.08), surface),
      ),
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: primary,
      error: error,
      onError: readableOn(error),
      errorContainer: errorContainer,
      onErrorContainer: readableOn(errorContainer),
    );
  }

  static ColorScheme _withAmoled(ColorScheme scheme) {
    const black = Color(0xFF000000);
    const text = Color(0xFFF2F2F2);
    final primary = contrastRatio(scheme.primary, black) >= 3.0
        ? scheme.primary
        : text;
    return scheme.copyWith(
      primary: primary,
      onPrimary: readableOn(primary),
      primaryContainer: const Color(0xFF222222),
      onPrimaryContainer: text,
      secondaryContainer: const Color(0xFF1F1F1F),
      onSecondaryContainer: text,
      tertiaryContainer: const Color(0xFF1A1A1A),
      onTertiaryContainer: text,
      surface: black,
      onSurface: text,
      surfaceDim: black,
      surfaceBright: const Color(0xFF2A2A2A),
      surfaceContainerLowest: black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF222222),
      onSurfaceVariant: const Color(0xFFB0B0B0),
      outline: const Color(0xFFA8A8A8),
      outlineVariant: const Color(0xFF2E2E2E),
      inverseSurface: text,
      onInverseSurface: const Color(0xFF111111),
      inversePrimary: primary,
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
    );
  }

  static ThemeData _theme(
    ColorScheme colors, {
    String? appFontFamily,
    String? timerFontFamily,
  }) {
    final base = ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    var textTheme = base.textTheme;
    var primaryTextTheme = base.primaryTextTheme;
    if (appFontFamily != null) {
      textTheme = textTheme.apply(fontFamily: appFontFamily);
      primaryTextTheme = primaryTextTheme.apply(fontFamily: appFontFamily);
    }
    TextStyle? withTimerFont(TextStyle? style) => timerFontFamily == null
        ? style
        : style?.copyWith(fontFamily: timerFontFamily);
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
      textTheme: textTheme.copyWith(
        displayLarge: withTimerFont(
          textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        displayMedium: withTimerFont(textTheme.displayMedium),
        displaySmall: withTimerFont(textTheme.displaySmall),
        // The compact Focus time readout is the only headline-sized timer.
        headlineMedium: withTimerFont(textTheme.headlineMedium),
      ),
      primaryTextTheme: primaryTextTheme,
    );
  }
}
