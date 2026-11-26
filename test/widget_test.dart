import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the four sections and returns from settings', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        startupProvider.overrideWith((ref) => const StartupData(
          settings: AppSettings(),
          focus: null,
          clock: null,
          companion: null,
          sessions: [],
        )),
      ],
      child: const CompanionFocusApp(),
    ));
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
}
