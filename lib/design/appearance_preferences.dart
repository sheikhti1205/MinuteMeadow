import 'dart:ui';

/// Home layouts shared by the appearance editor and the home surface.
enum HomeLayout { classic, refined, studio }

/// Focus card containers shared by the appearance editor and the home surface.
enum FocusCardStyle { filled, outlined, glass }

/// Ambient card effects. The editor and the home surface read the same enum so
/// a saved choice renders consistently.
enum FocusCardEffect { off, dunes, rain, embers, aurora, mesh }

/// Wallpapers are types, never media. Settings stay small and backup-safe:
/// renderers resolve these names to their own drawing code, and no image bytes
/// or file paths are ever persisted with preferences.
enum WallpaperType { none, dunes, rain, embers, aurora, mesh }

/// Optional colour palettes. [grayscale] is the original MinuteMeadow chrome
/// and stays byte-for-byte identical to the base light and dark schemes.
/// [system] uses an injected platform seed when one is available.
enum AppPalette { grayscale, system, meadow, clay, tide, dusk }

/// Readable system font families. No font files are bundled with the app.
enum AppFont { system, sans, serif, condensed, mono }

extension HomeLayoutInfo on HomeLayout {
  String get label => switch (this) {
    HomeLayout.classic => 'Classic',
    HomeLayout.refined => 'Refined',
    HomeLayout.studio => 'Studio',
  };
}

extension FocusCardStyleInfo on FocusCardStyle {
  String get label => switch (this) {
    FocusCardStyle.filled => 'Filled',
    FocusCardStyle.outlined => 'Outlined',
    FocusCardStyle.glass => 'Glass',
  };
}

extension FocusCardEffectInfo on FocusCardEffect {
  String get label => switch (this) {
    FocusCardEffect.off => 'Off',
    FocusCardEffect.dunes => 'Dunes',
    FocusCardEffect.rain => 'Rain',
    FocusCardEffect.embers => 'Embers',
    FocusCardEffect.aurora => 'Aurora',
    FocusCardEffect.mesh => 'Mesh',
  };
}

extension WallpaperTypeInfo on WallpaperType {
  String get label => switch (this) {
    WallpaperType.none => 'None',
    WallpaperType.dunes => 'Dunes',
    WallpaperType.rain => 'Rain',
    WallpaperType.embers => 'Embers',
    WallpaperType.aurora => 'Aurora',
    WallpaperType.mesh => 'Mesh',
  };
}

extension AppPaletteInfo on AppPalette {
  String get label => switch (this) {
    AppPalette.grayscale => 'Grayscale',
    AppPalette.system => 'System',
    AppPalette.meadow => 'Meadow',
    AppPalette.clay => 'Clay',
    AppPalette.tide => 'Tide',
    AppPalette.dusk => 'Dusk',
  };

  /// A seed for palettes that carry an authored hue. Grayscale and system
  /// colours are resolved by the theme, not by a seed here.
  Color? get seed => switch (this) {
    AppPalette.grayscale || AppPalette.system => null,
    AppPalette.meadow => const Color(0xFF5F7A5A),
    AppPalette.clay => const Color(0xFFA85A42),
    AppPalette.tide => const Color(0xFF3F6F87),
    AppPalette.dusk => const Color(0xFF6C5C87),
  };
}

extension AppFontInfo on AppFont {
  String get label => switch (this) {
    AppFont.system => 'System',
    AppFont.sans => 'Sans',
    AppFont.serif => 'Serif',
    AppFont.condensed => 'Condensed',
    AppFont.mono => 'Mono',
  };

  /// Generic platform families work on Android without bundling assets.
  String? get family => switch (this) {
    AppFont.system => null,
    AppFont.sans => 'sans-serif',
    AppFont.serif => 'serif',
    AppFont.condensed => 'sans-serif-condensed',
    AppFont.mono => 'monospace',
  };
}

/// Appearance choices that are independent of the timer and alert settings.
///
/// Every field is non-null except the two optional custom colours. A missing
/// JSON field decodes to the original grayscale appearance, so settings and
/// backups written before this model existed keep working. Each editor only
/// replaces the fields it owns, so a theme save cannot move the home layout or
/// clear the watch dial.
class AppearancePreferences {
  const AppearancePreferences({
    this.homeLayout = HomeLayout.classic,
    this.cardStyle = FocusCardStyle.filled,
    this.cardEffect = FocusCardEffect.off,
    this.amoled = false,
    this.palette = AppPalette.grayscale,
    this.customAccent,
    this.customSurface,
    this.appFont = AppFont.system,
    this.timerFont = AppFont.system,
    this.wallpaper = WallpaperType.none,
    this.watchDial = false,
  });

  static const defaults = AppearancePreferences();

  final HomeLayout homeLayout;
  final FocusCardStyle cardStyle;
  final FocusCardEffect cardEffect;
  final bool amoled;
  final AppPalette palette;
  final Color? customAccent;
  final Color? customSurface;
  final AppFont appFont;
  final AppFont timerFont;
  final WallpaperType wallpaper;

  /// Shows the dial face on the watch surface, where the host supports one.
  ///
  /// The Home & Cards surface owns this flag. The Theme & Colors editor neither
  /// shows nor resets it, and a theme save keeps the stored value.
  final bool watchDial;

  bool get hasCustomAccent => customAccent != null;
  bool get hasCustomSurface => customSurface != null;

  AppearancePreferences copyWith({
    HomeLayout? homeLayout,
    FocusCardStyle? cardStyle,
    FocusCardEffect? cardEffect,
    bool? amoled,
    AppPalette? palette,
    Color? customAccent,
    bool clearCustomAccent = false,
    Color? customSurface,
    bool clearCustomSurface = false,
    AppFont? appFont,
    AppFont? timerFont,
    WallpaperType? wallpaper,
    bool? watchDial,
  }) => AppearancePreferences(
    homeLayout: homeLayout ?? this.homeLayout,
    cardStyle: cardStyle ?? this.cardStyle,
    cardEffect: cardEffect ?? this.cardEffect,
    amoled: amoled ?? this.amoled,
    palette: palette ?? this.palette,
    customAccent: clearCustomAccent
        ? null
        : (customAccent ?? this.customAccent),
    customSurface: clearCustomSurface
        ? null
        : (customSurface ?? this.customSurface),
    appFont: appFont ?? this.appFont,
    timerFont: timerFont ?? this.timerFont,
    wallpaper: wallpaper ?? this.wallpaper,
    watchDial: watchDial ?? this.watchDial,
  );

  Map<String, Object> toJson() => {
    'homeLayout': homeLayout.name,
    'cardStyle': cardStyle.name,
    'cardEffect': cardEffect.name,
    'amoled': amoled,
    'palette': palette.name,
    if (customAccent != null) 'customAccent': customAccent!.toARGB32(),
    if (customSurface != null) 'customSurface': customSurface!.toARGB32(),
    'appFont': appFont.name,
    'timerFont': timerFont.name,
    'wallpaper': wallpaper.name,
    'watchDial': watchDial,
  };

  /// Decodes preferences written by this or an earlier version.
  ///
  /// A missing field keeps its original default. Extra fields are ignored, so
  /// a backup from a newer build still restores the fields this build knows.
  static AppearancePreferences fromJson(Object? json) {
    if (json == null) return defaults;
    if (json is! Map<String, Object?>) {
      throw const FormatException('Invalid appearance preferences.');
    }
    return AppearancePreferences(
      homeLayout: _enumValue(
        json['homeLayout'],
        HomeLayout.values,
        HomeLayout.classic,
        'home layout',
      ),
      cardStyle: _enumValue(
        json['cardStyle'],
        FocusCardStyle.values,
        FocusCardStyle.filled,
        'card style',
      ),
      cardEffect: _enumValue(
        json['cardEffect'],
        FocusCardEffect.values,
        FocusCardEffect.off,
        'card effect',
      ),
      amoled: _boolValue(json['amoled'], false, 'AMOLED'),
      palette: _enumValue(
        json['palette'],
        AppPalette.values,
        AppPalette.grayscale,
        'palette',
      ),
      customAccent: _colorValue(json['customAccent'], 'custom accent'),
      customSurface: _colorValue(json['customSurface'], 'custom surface'),
      appFont: _enumValue(
        json['appFont'],
        AppFont.values,
        AppFont.system,
        'app font',
      ),
      timerFont: _enumValue(
        json['timerFont'],
        AppFont.values,
        AppFont.system,
        'timer font',
      ),
      wallpaper: _enumValue(
        json['wallpaper'],
        WallpaperType.values,
        WallpaperType.none,
        'wallpaper',
      ),
      watchDial: _boolValue(json['watchDial'], false, 'watch dial'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearancePreferences &&
      other.homeLayout == homeLayout &&
      other.cardStyle == cardStyle &&
      other.cardEffect == cardEffect &&
      other.amoled == amoled &&
      other.palette == palette &&
      other.customAccent == customAccent &&
      other.customSurface == customSurface &&
      other.appFont == appFont &&
      other.timerFont == timerFont &&
      other.wallpaper == wallpaper &&
      other.watchDial == watchDial;

  @override
  int get hashCode => Object.hash(
    homeLayout,
    cardStyle,
    cardEffect,
    amoled,
    palette,
    customAccent,
    customSurface,
    appFont,
    timerFont,
    wallpaper,
    watchDial,
  );
}

T _enumValue<T extends Enum>(
  Object? value,
  List<T> values,
  T fallback,
  String field,
) {
  if (value == null) return fallback;
  if (value is String) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
  }
  throw FormatException('Invalid $field.');
}

bool _boolValue(Object? value, bool fallback, String field) {
  if (value == null) return fallback;
  if (value is bool) return value;
  throw FormatException('Invalid $field.');
}

Color? _colorValue(Object? value, String field) {
  if (value == null) return null;
  if (value is int && value >= 0 && value <= 0xFFFFFFFF) return Color(value);
  throw FormatException('Invalid $field.');
}
