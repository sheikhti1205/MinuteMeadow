import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the four sections and returns from settings', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Companion Focus'), findsOneWidget);
    final navigation = find.byType(NavigationBar);
    for (final (index, label) in ['Clock', 'Companion', 'Insights', 'Focus']
        .indexed) {
      await tester.tap(find.descendant(of: navigation, matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, (index + 1) % 4);
    }
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Timer defaults'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Companion Focus'), findsOneWidget);
  });

  testWidgets('main destinations reflow on a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finish = DateTime.now().toUtc();
    final app = _app(
      settings: const AppSettings(themeMode: ThemeMode.dark),
      sessions: [
        SessionRecord(
          id: 'completed-session',
          startedAt: finish.subtract(const Duration(minutes: 25)),
          finishedAt: finish,
          intended: const Duration(minutes: 25),
          actual: const Duration(minutes: 25),
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: app,
      ),
    ));
    await tester.pumpAndSettle();

    final navigation = find.byType(NavigationBar);
    expect(Theme.of(tester.element(navigation)).brightness, Brightness.dark);
    for (final label in ['Clock', 'Companion', 'Insights', 'Focus']) {
      await tester.tap(find.descendant(of: navigation, matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label should fit at 320 dp');
    }
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Timer defaults'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  AppSettings settings = const AppSettings(),
  List<SessionRecord> sessions = const [],
}) {
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      startupProvider.overrideWith((ref) => StartupData(
        settings: settings,
        focus: null,
        clock: null,
        companion: null,
        sessions: sessions,
      )),
    ],
    child: const CompanionFocusApp(),
  );
}
