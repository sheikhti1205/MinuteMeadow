import 'package:companion_focus/app/installed_companion_view.dart';
import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _builtIns = ['Dunes', 'Rain', 'Embers', 'Aurora', 'Mesh'];

class _Harness {
  _Harness() : notifier = ValueNotifier(const AppSettings());

  final ValueNotifier<AppSettings> notifier;
  final List<AppSettings> saves = [];

  Widget build() => MaterialApp(
    theme: CompanionTheme.light,
    home: SettingsPage(
      settings: notifier,
      onSave: (next) async {
        saves.add(next);
        notifier.value = next;
      },
      onExport: () async =>
          const DataBackup(settings: AppSettings(), sessions: []).encode(),
      onReplace: (backup) async {
        notifier.value = backup.settings;
      },
      onClear: () async {
        notifier.value = const AppSettings();
      },
    ),
  );

  void dispose() => notifier.dispose();
}

Future<_Harness> _pump(WidgetTester tester) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.build());
  await tester.pumpAndSettle();
  return harness;
}

/// Bounded frame advance: editors may preview continuously, so nothing here
/// waits for the whole tree to settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
  } else {
    await tester.ensureVisible(finder.first);
  }
  await _settle(tester);
}

Future<void> _open(WidgetTester tester, String label) async {
  final entry = find.text(label);
  await _reveal(tester, entry);
  expect(entry, findsWidgets, reason: 'Settings must label "$label".');
  await tester.tap(entry.first);
  await _settle(tester);
}

void main() {
  testWidgets('Home & Cards wallpaper offers its preview and sources', (
    tester,
  ) async {
    await _pump(tester);

    await _open(tester, 'Home & Cards');
    await _open(tester, 'Wallpaper');

    expect(find.text('None'), findsWidgets);
    expect(find.text('Choose photo'), findsWidgets);
    expect(find.text('Live wallpapers'), findsWidgets);
    expect(
      _builtIns.where((name) => find.text(name).evaluate().isNotEmpty).length,
      greaterThanOrEqualTo(2),
      reason: 'Built-in wallpapers are listed on the wallpaper surface.',
    );

    final handle = tester.ensureSemantics();
    try {
      final preview = find.bySemanticsLabel(RegExp(r'^Wallpaper preview'));
      expect(preview, findsOneWidget);
      await tester.ensureVisible(preview);
      await tester.pump();
      expect(tester.getSize(preview).width, greaterThan(0));
      expect(tester.getSize(preview).height, greaterThan(0));
    } finally {
      handle.dispose();
    }

    expect(find.byType(InstalledCompanionView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Focus ambience is optional and independent of Sound', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final harness = await _pump(tester);

      expect(find.text('Audio & haptics'), findsOneWidget);
      await _open(tester, 'Focus ambience');

      expect(find.text('Off'), findsWidgets);
      expect(find.text('Rain'), findsWidgets);
      expect(find.text('Volume'), findsWidgets);
      expect(find.byType(Slider), findsWidgets);

      final soundBefore = harness.notifier.value.sound;

      await tester.tap(find.text('Rain').first);
      await _settle(tester);
      await tester.tap(find.text('Off').first);
      await _settle(tester);

      expect(harness.notifier.value.sound, soundBefore);
      for (final saved in harness.saves) {
        expect(saved.sound, soundBefore);
      }
      expect(find.byType(InstalledCompanionView), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
