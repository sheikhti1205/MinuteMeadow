import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/time/boot_clock.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android opens stored preferences and saves a focus default', (tester) async {
    final database = LocalDatabase.open();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.runAsync(() async {
      await database.writeState('settings', const AppSettings().encode());
      await container.read(startupProvider.future);
      final boot = await BootClock.sample();
      expect(boot, isNotNull);
      expect(boot!.elapsed, greaterThan(Duration.zero));
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CompanionFocusApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Companion Focus'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus duration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '37');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = await tester.runAsync(() => database.readState('settings'));
    expect(AppSettings.decode(stored!).focusMinutes, 37);
    await tester.pumpAndSettle();
    expect(find.text('37 min'), findsOneWidget);
  });
}
