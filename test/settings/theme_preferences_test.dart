import 'package:companion_focus/design/appearance_preferences.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/theme_colors_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings with a non-default value in every field this editor does not own,
/// so a theme save that overwrites one of them fails loudly.
AppSettings _busySettings() => const AppSettings(
  focusMinutes: 40,
  shortBreakMinutes: 8,
  longBreakMinutes: 20,
  themeMode: ThemeMode.dark,
  notifications: true,
  sound: false,
  haptics: false,
  reducedMotion: true,
  lowPower: true,
  appearance: AppearancePreferences(
    homeLayout: HomeLayout.studio,
    cardStyle: FocusCardStyle.glass,
    cardEffect: FocusCardEffect.aurora,
    amoled: true,
    palette: AppPalette.clay,
    customAccent: Color(0xFF3F6F87),
    customSurface: Color(0xFF20242A),
    appFont: AppFont.serif,
    timerFont: AppFont.mono,
    wallpaper: WallpaperType.dunes,
    watchDial: true,
  ),
  completionVibration: false,
  notificationPromptSeen: true,
);

/// Opens the editor over a host route and returns the list of saves.
Future<List<AppSettings>> _openEditor(
  WidgetTester tester, {
  required AppSettings settings,
  Color? systemSeed,
  AppSettings Function()? latestSettings,
}) async {
  final saves = <AppSettings>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: CompanionTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                ThemeColorsPage.route(
                  settings: settings,
                  systemSeed: systemSeed,
                  latestSettings: latestSettings,
                  onSave: (next) async => saves.add(next),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Theme & Colors'), findsOneWidget);
  return saves;
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
}

void main() {
  group('watch dial', () {
    test('defaults off and persists additively', () {
      const defaults = AppearancePreferences();
      expect(defaults.watchDial, isFalse);
      expect(
        AppearancePreferences.fromJson(<String, Object?>{}).watchDial,
        isFalse,
      );
      expect(
        () => AppearancePreferences.fromJson(<String, Object?>{'watchDial': 3}),
        throwsFormatException,
      );

      final dial = defaults.copyWith(watchDial: true);
      expect(dial.watchDial, isTrue);
      expect(dial, isNot(defaults));
      expect(dial.toJson()['watchDial'], isTrue);
      expect(AppearancePreferences.fromJson(dial.toJson()), dial);
      expect(dial.copyWith(amoled: true).watchDial, isTrue);
    });
  });

  group('ThemeSelection', () {
    test('merges only the theme fields into a stored settings object', () {
      const selection = ThemeSelection(
        mode: ThemeMode.light,
        amoled: false,
        palette: AppPalette.tide,
        appFont: AppFont.sans,
        timerFont: AppFont.condensed,
      );

      final merged = selection.mergeInto(_busySettings());
      final appearance = merged.appearance;

      expect(merged.themeMode, ThemeMode.light);
      expect(appearance.palette, AppPalette.tide);
      expect(appearance.amoled, isFalse);
      expect(appearance.customAccent, isNull);
      expect(appearance.customSurface, isNull);
      expect(appearance.appFont, AppFont.sans);
      expect(appearance.timerFont, AppFont.condensed);

      // Independent fields keep the stored values.
      expect(appearance.homeLayout, HomeLayout.studio);
      expect(appearance.cardStyle, FocusCardStyle.glass);
      expect(appearance.cardEffect, FocusCardEffect.aurora);
      expect(appearance.wallpaper, WallpaperType.dunes);
      expect(appearance.watchDial, isTrue);
      expect(merged.completionVibration, isFalse);
      expect(merged.notificationPromptSeen, isTrue);
      expect(merged.notifications, isTrue);
      expect(merged.lowPower, isTrue);
      expect(merged.focusMinutes, 40);
    });

    test('reads back only the owned fields', () {
      expect(
        ThemeSelection.fromSettings(_busySettings()),
        const ThemeSelection(
          mode: ThemeMode.dark,
          amoled: true,
          palette: AppPalette.clay,
          customAccent: Color(0xFF3F6F87),
          customSurface: Color(0xFF20242A),
          appFont: AppFont.serif,
          timerFont: AppFont.mono,
        ),
      );
    });
  });

  group('Theme & Colors', () {
    testWidgets('Reset clears the theme fields and keeps the others', (
      tester,
    ) async {
      final saves = await _openEditor(tester, settings: _busySettings());

      await tester.tap(find.text('Reset to default'));
      await tester.pump();
      await _apply(tester);

      expect(saves, hasLength(1));
      final saved = saves.single;
      expect(saved.themeMode, ThemeMode.system);
      expect(saved.appearance.palette, AppPalette.grayscale);
      expect(saved.appearance.amoled, isFalse);
      expect(saved.appearance.customAccent, isNull);
      expect(saved.appearance.customSurface, isNull);
      expect(saved.appearance.appFont, AppFont.system);
      expect(saved.appearance.timerFont, AppFont.system);

      expect(saved.appearance.homeLayout, HomeLayout.studio);
      expect(saved.appearance.cardStyle, FocusCardStyle.glass);
      expect(saved.appearance.cardEffect, FocusCardEffect.aurora);
      expect(saved.appearance.wallpaper, WallpaperType.dunes);
      expect(saved.appearance.watchDial, isTrue);
      expect(saved.notifications, isTrue);
      expect(saved.completionVibration, isFalse);
      expect(saved.notificationPromptSeen, isTrue);
      expect(saved.lowPower, isTrue);
    });

    testWidgets('Apply without edits saves the stored settings', (
      tester,
    ) async {
      final settings = _busySettings();
      final saves = await _openEditor(tester, settings: settings);

      await _apply(tester);

      expect(saves, hasLength(1));
      final saved = saves.single;
      expect(saved.themeMode, settings.themeMode);
      expect(saved.appearance, settings.appearance);
      expect(saved.completionVibration, settings.completionVibration);
      expect(saved.notificationPromptSeen, settings.notificationPromptSeen);
      expect(saved.focusMinutes, settings.focusMinutes);
    });

    testWidgets('Apply merges into the settings stored at save time', (
      tester,
    ) async {
      var latest = _busySettings();
      final saves = await _openEditor(
        tester,
        settings: latest,
        latestSettings: () => latest,
      );

      // Another surface saves layout and alert changes while this page is open.
      latest = latest.copyWith(
        appearance: latest.appearance.copyWith(
          homeLayout: HomeLayout.refined,
          watchDial: false,
        ),
        notifications: false,
      );

      final light = find.text('Light');
      await tester.ensureVisible(light);
      await tester.pump();
      await tester.tap(light);
      await tester.pump();
      await _apply(tester);

      final saved = saves.single;
      expect(saved.themeMode, ThemeMode.light);
      expect(saved.appearance.homeLayout, HomeLayout.refined);
      expect(saved.appearance.watchDial, isFalse);
      expect(saved.notifications, isFalse);
      expect(saved.appearance.palette, AppPalette.clay);
    });

    testWidgets('System palette is disabled and explained without a seed', (
      tester,
    ) async {
      final saves = await _openEditor(tester, settings: const AppSettings());

      expect(
        find.text(ThemeColorsPage.systemSeedUnavailableMessage),
        findsOneWidget,
      );
      final system = tester.widget<ChoiceChip>(
        find.byKey(ThemeColorsPage.paletteChoiceKey(AppPalette.system)),
      );
      expect(system.onSelected, isNull);
      final meadow = tester.widget<ChoiceChip>(
        find.byKey(ThemeColorsPage.paletteChoiceKey(AppPalette.meadow)),
      );
      expect(meadow.onSelected, isNotNull);

      await _apply(tester);
      expect(saves.single.appearance.palette, AppPalette.grayscale);
    });

    testWidgets('System palette saves when the host supplies a seed', (
      tester,
    ) async {
      final saves = await _openEditor(
        tester,
        settings: const AppSettings(),
        systemSeed: const Color(0xFF3F6F87),
      );

      expect(
        find.text(ThemeColorsPage.systemSeedUnavailableMessage),
        findsNothing,
      );
      final system = find.byKey(
        ThemeColorsPage.paletteChoiceKey(AppPalette.system),
      );
      await tester.ensureVisible(system);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(system).onSelected, isNotNull);

      await tester.tap(system);
      await tester.pump();
      await _apply(tester);
      expect(saves.single.appearance.palette, AppPalette.system);
    });
  });

  group('System palette scheme', () {
    test('takes the platform seed through the shared scheme path', () {
      const appearance = AppearancePreferences(palette: AppPalette.system);
      const grayscale = AppearancePreferences();
      final fallback = CompanionTheme.schemeFor(
        appearance,
        brightness: Brightness.light,
      );
      final plain = CompanionTheme.schemeFor(
        grayscale,
        brightness: Brightness.light,
      );
      expect(fallback.primary, plain.primary);
      expect(fallback.surface, plain.surface);
      expect(fallback.onSurface, plain.onSurface);

      const seed = Color(0xFF3F6F87);
      final seeded = CompanionTheme.schemeFor(
        appearance,
        brightness: Brightness.light,
        systemSeed: seed,
      );
      // The authored palette with the same seed resolves identically.
      final authored = CompanionTheme.schemeFor(
        const AppearancePreferences(palette: AppPalette.tide),
        brightness: Brightness.light,
      );
      expect(seeded.primary, authored.primary);
      expect(seeded.secondary, authored.secondary);
      expect(seeded.surface, authored.surface);
      expect(seeded.primary, isNot(fallback.primary));
    });
  });

  group('Custom accent contrast', () {
    test('keeps an accent the custom surface makes readable', () {
      // Below 3:1 on the light grayscale surface, so the old order dropped it,
      // but above 4.5:1 on the dark surface selected at the same time.
      const accent = Color(0xFF959595);
      const surface = Color(0xFF111111);
      final light = CompanionTheme.schemeFor(
        const AppearancePreferences(),
        brightness: Brightness.light,
      );
      expect(
        CompanionTheme.contrastRatio(accent, light.surface),
        lessThan(3.0),
      );

      final scheme = CompanionTheme.schemeFor(
        const AppearancePreferences(
          customAccent: accent,
          customSurface: surface,
        ),
        brightness: Brightness.light,
      );
      expect(scheme.surface, surface);
      expect(scheme.primary, accent);
      expect(
        CompanionTheme.contrastRatio(scheme.primary, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(scheme.onPrimary, CompanionTheme.readableOn(accent));
    });

    test('adjusts a weak accent until ordinary text reads on it', () {
      const accent = Color(0xFF808080);
      final plain = CompanionTheme.schemeFor(
        const AppearancePreferences(),
        brightness: Brightness.light,
      );
      expect(
        CompanionTheme.contrastRatio(accent, plain.surface),
        lessThan(4.5),
      );

      final scheme = CompanionTheme.schemeFor(
        const AppearancePreferences(customAccent: accent),
        brightness: Brightness.light,
      );
      expect(scheme.primary, isNot(accent));
      expect(
        CompanionTheme.contrastRatio(scheme.primary, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(scheme.onPrimary, CompanionTheme.readableOn(scheme.primary));
    });
  });
}
