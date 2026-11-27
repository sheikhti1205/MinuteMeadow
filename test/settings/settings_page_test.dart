import 'package:companion_focus/app/branding.dart';
import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

List<SessionRecord> _sessions() {
  final finish = DateTime.utc(2026, 11, 26, 12);
  return [
    SessionRecord(
      id: 'first',
      startedAt: finish.subtract(const Duration(minutes: 25)),
      finishedAt: finish,
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
    ),
    SessionRecord(
      id: 'second',
      startedAt: finish.subtract(const Duration(minutes: 15)),
      finishedAt: finish,
      intended: const Duration(minutes: 15),
      actual: const Duration(minutes: 15),
      completed: true,
    ),
  ];
}

DataBackup _backup({int sessionCount = 2}) => DataBackup(
  settings: const AppSettings(
    focusMinutes: 30,
    shortBreakMinutes: 10,
    longBreakMinutes: 20,
    themeMode: ThemeMode.dark,
    notifications: true,
    sound: false,
    haptics: true,
    reducedMotion: true,
    lowPower: true,
  ),
  sessions: _sessions().take(sessionCount).toList(growable: false),
);

class _Harness {
  _Harness({AppSettings settings = const AppSettings(), this.theme})
    : notifier = ValueNotifier(settings);

  final ValueNotifier<AppSettings> notifier;
  final ThemeData? theme;
  final List<AppSettings> saves = [];
  final List<DataBackup> replaced = [];
  int clears = 0;
  Object? saveError;

  Widget build({
    bool notificationsAvailable = false,
    Future<bool> Function()? checkNotificationPermission,
    double textScale = 1,
  }) => MaterialApp(
    theme: theme ?? CompanionTheme.light,
    builder: textScale == 1
        ? null
        : (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
    home: SettingsPage(
      settings: notifier,
      onSave: (next) async {
        saves.add(next);
        final error = saveError;
        if (error != null) {
          saveError = null;
          throw error;
        }
        notifier.value = next;
      },
      onExport: () async => DataBackup(
        settings: notifier.value,
        sessions: _sessions(),
      ).encode(),
      onReplace: (backup) async {
        replaced.add(backup);
        notifier.value = backup.settings;
      },
      onClear: () async {
        clears += 1;
        notifier.value = const AppSettings();
      },
      notificationsAvailable: notificationsAvailable,
      checkNotificationPermission: checkNotificationPermission,
    ),
  );

  void dispose() => notifier.dispose();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
  ThemeData? theme,
  bool notificationsAvailable = false,
  Future<bool> Function()? checkNotificationPermission,
}) async {
  final harness = _Harness(settings: settings, theme: theme);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    harness.build(
      notificationsAvailable: notificationsAvailable,
      checkNotificationPermission: checkNotificationPermission,
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// Scrolls the list until [finder] is on screen and aligns it to the top.
///
/// `ensureVisible` puts the target at the top edge, which moves a section
/// header above it out of the sliver's onstage window. Scroll to a header
/// when the test asserts that header.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable);
  for (var attempt = 0; attempt < 60; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  fail('Could not scroll to $finder');
}

Finder _themeOption(ThemeMode mode) =>
    find.byKey(SettingsPage.themeOptionKey(mode));

void main() {
  testWidgets('groups settings with current values and state controls', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Timer defaults'), findsOneWidget);
    expect(find.text('Focus duration'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('Audio & haptics'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(
      find.widgetWithText(SwitchListTile, 'Completion notifications'),
      findsNothing,
    );

    await _scrollTo(tester, find.text('Appearance'));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    // The current value is shown in the pill and as the selected option.
    expect(find.text('System'), findsNWidgets(2));
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Reduce motion'), findsOneWidget);
    expect(find.text('Low-power animation'), findsOneWidget);

    await _scrollTo(tester, find.text('Local data'));
    expect(find.text('Local data'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Clear local data'), findsOneWidget);

    await _scrollTo(tester, find.text('About'));
    final build = Branding.buildNumber > 0
        ? 'build ${Branding.buildNumber}'
        : (Branding.buildId.isEmpty ? 'local build' : 'CI build');
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version ${Branding.version} · $build'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('theme selector saves a shaped, non-colour-only choice', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final harness = await _pump(tester);
      await _scrollTo(tester, _themeOption(ThemeMode.system));

      expect(
        find.descendant(
          of: _themeOption(ThemeMode.system),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(_themeOption(ThemeMode.system))
            .getSemanticsData()
            .label,
        'Theme: System',
      );

      await tester.tap(_themeOption(ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(harness.saves.last.themeMode, ThemeMode.dark);
      expect(harness.notifier.value.themeMode, ThemeMode.dark);
      expect(
        find.descendant(
          of: _themeOption(ThemeMode.dark),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _themeOption(ThemeMode.system),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    } finally {
      handle.dispose();
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switches save state and show a check or close thumb', (
    tester,
  ) async {
    final harness = await _pump(tester);
    final soundTile = find.widgetWithText(SwitchListTile, 'Sound');
    expect(soundTile, findsOneWidget);

    final before = tester.widget<Switch>(
      find.descendant(of: soundTile, matching: find.byType(Switch)),
    );
    expect(before.value, isTrue);
    expect(
      before.thumbIcon!.resolve(<WidgetState>{WidgetState.selected})!.icon,
      Icons.check,
    );

    await tester.tap(soundTile);
    await tester.pumpAndSettle();

    expect(harness.saves.last.sound, isFalse);
    expect(harness.notifier.value.sound, isFalse);
    final after = tester.widget<Switch>(
      find.descendant(of: soundTile, matching: find.byType(Switch)),
    );
    expect(after.value, isFalse);
    expect(
      after.thumbIcon!.resolve(<WidgetState>{})!.icon,
      Icons.close,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('notification control follows host availability and permission', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Completion notifications'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());

    final harness = await _pump(
      tester,
      settings: const AppSettings(notifications: true),
      notificationsAvailable: true,
      checkNotificationPermission: () async => false,
    );
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Completion notifications'), findsOneWidget);
    expect(find.textContaining('Blocked in Android settings'), findsOneWidget);
    expect(harness.notifier.value.notifications, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed permission check stays unknown instead of denying', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const AppSettings(notifications: true),
      notificationsAvailable: true,
      checkNotificationPermission: () async {
        throw Exception('Notification platform unavailable.');
      },
    );

    expect(find.text('Completion notifications'), findsOneWidget);
    expect(find.textContaining('Blocked in Android settings'), findsNothing);
    expect(
      find.text('Alerts when a timer ends, even outside the app.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('About exposes compact identity and full build details', (
    tester,
  ) async {
    await _pump(tester);
    await _scrollTo(tester, find.text('Details'));

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Build details'), findsOneWidget);
    expect(find.text('${Branding.name} ${Branding.version}'), findsOneWidget);
    expect(find.text('Copy ID'), findsOneWidget);
    final identity = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(identity.data, Branding.displayVersion);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Build details'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('export dialog lists the backup contents before copying', (
    tester,
  ) async {
    await _pump(tester);
    await _scrollTo(tester, find.text('Export backup'));

    await tester.tap(find.text('Export backup'));
    await tester.pumpAndSettle();

    expect(find.text('Copy backup'), findsOneWidget);
    expect(find.text('The backup contains:'), findsOneWidget);
    expect(find.textContaining('25 min focus'), findsOneWidget);
    expect(find.textContaining('notifications off'), findsOneWidget);
    expect(find.textContaining('2 focus sessions'), findsOneWidget);
    expect(find.textContaining('labels and notes'), findsOneWidget);
    expect(find.textContaining('Keep it private'), findsOneWidget);
    expect(
      find.textContaining('does not include saved Focus or Clock presets'),
      findsOneWidget,
    );
    expect(find.textContaining('active clocks'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid import stays untouched and valid import previews', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _scrollTo(tester, find.text('Import backup'));

    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, 'not a backup');
    await tester.pump();
    expect(
      find.text('This is not a valid MinuteMeadow backup.'),
      findsOneWidget,
    );
    expect(harness.replaced, isEmpty);
    final restoreButton = find.widgetWithText(FilledButton, 'Restore backup');
    expect(tester.widget<FilledButton>(restoreButton).onPressed, isNull);

    final backup = _backup();
    await tester.enterText(field, backup.encode());
    await tester.pump();
    expect(find.text('This backup will replace:'), findsOneWidget);
    expect(find.textContaining('2 focus sessions'), findsOneWidget);
    expect(
      find.textContaining('clears active timers and laps'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Saved Focus and Clock presets and installed companions stay',
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(restoreButton).onPressed, isNotNull);

    await tester.tap(restoreButton);
    await tester.pumpAndSettle();

    expect(harness.replaced, hasLength(1));
    expect(harness.replaced.single.sessions, hasLength(2));
    expect(harness.notifier.value.focusMinutes, 30);
    expect(find.text('Backup restored.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reset explains replacement and waits for confirmation', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      settings: const AppSettings(focusMinutes: 40),
    );
    await _scrollTo(tester, find.text('Clear local data'));

    await tester.tap(find.text('Clear local data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear local data?'), findsOneWidget);
    expect(
      find.text('Timer defaults return to 25 / 5 / 15 minutes.'),
      findsOneWidget,
    );
    expect(
      find.text('Focus history, active timers, clocks and laps are removed.'),
      findsOneWidget,
    );
    expect(
      find.text('Saved Focus and Clock presets are removed.'),
      findsOneWidget,
    );
    expect(find.text('Installed companions are removed.'), findsOneWidget);
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
    expect(find.textContaining('not presets or companions'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.clears, 0);

    await tester.tap(find.text('Clear local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear data'));
    await tester.pumpAndSettle();

    expect(harness.clears, 1);
    expect(harness.notifier.value.focusMinutes, 25);
    expect(find.text('Local data cleared.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed saves report the cause and retry the same change', (
    tester,
  ) async {
    final harness = await _pump(tester);
    harness.saveError = const FormatException(
      'Allow notifications in Android settings to enable alerts.',
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound'));
    await tester.pumpAndSettle();

    expect(
      find.text('Allow notifications in Android settings to enable alerts.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(harness.saves, hasLength(1));
    expect(harness.notifier.value.sound, isTrue);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(
      find.text('Allow notifications in Android settings to enable alerts.'),
      findsNothing,
    );
    expect(harness.saves, hasLength(2));
    expect(harness.notifier.value.sound, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timer rows and theme choices expose assistive labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester);
      final timer = tester
          .getSemantics(find.byKey(SettingsPage.focusDurationKey))
          .getSemanticsData();
      expect(
        timer.label,
        'Focus duration, 25 min. Deep-work session length',
      );
      expect(timer.hasAction(SemanticsAction.tap), isTrue);

      await _scrollTo(tester, _themeOption(ThemeMode.system));
      expect(
        tester
            .getSemantics(_themeOption(ThemeMode.system))
            .getSemanticsData()
            .label,
        'Theme: System',
      );
    } finally {
      handle.dispose();
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reflows at 320dp with 2x text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.build(notificationsAvailable: true, textScale: 2),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(SettingsPage)),
      ).scale(10),
      20,
    );
    expect(tester.takeException(), isNull);

    await _scrollTo(tester, _themeOption(ThemeMode.dark));
    final systemTop = tester
        .getTopLeft(_themeOption(ThemeMode.system))
        .dy;
    final lightTop = tester.getTopLeft(_themeOption(ThemeMode.light)).dy;
    final darkTop = tester.getTopLeft(_themeOption(ThemeMode.dark)).dy;
    expect(systemTop, lessThan(lightTop));
    expect(lightTop, lessThan(darkTop));
    expect(
      tester.getSize(_themeOption(ThemeMode.system)).height,
      greaterThanOrEqualTo(52),
    );
    expect(tester.takeException(), isNull);

    await _scrollTo(tester, find.text('Clear local data'));
    expect(find.text('Clear local data'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _scrollTo(tester, find.text('Details'));
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renders grouped controls in dark mode', (tester) async {
    await _pump(tester, theme: CompanionTheme.dark);
    await _scrollTo(tester, _themeOption(ThemeMode.system));

    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    expect(
      find.descendant(
        of: _themeOption(ThemeMode.system),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
