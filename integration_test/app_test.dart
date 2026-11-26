import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/time/boot_clock.dart';
import 'package:companion_focus/core/time/timer_checkpoint.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android reloads focus defaults and a paused timer from SQLite', (tester) async {
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

    await tester.pageBack();
    await tester.pumpAndSettle();
    final primary = find.byKey(FocusPage.primaryActionKey);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(find.descendant(of: primary, matching: find.text('Pause')), findsOneWidget);

    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(find.descendant(of: primary, matching: find.text('Resume')), findsOneWidget);

    FocusSnapshot? snapshot;
    for (var attempt = 0; attempt < 10; attempt++) {
      final stored = await tester.runAsync(() => database.readState('focus'));
      final checkpoint = TimerCheckpoint.decode(stored);
      snapshot = FocusSnapshot.tryDecode(checkpoint?.snapshot);
      if (snapshot?.status == FocusStatus.paused) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(snapshot?.status, FocusStatus.paused);
    expect(snapshot?.intended, const Duration(minutes: 37));

    await tester.pumpWidget(const SizedBox.shrink());
    final reopened = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(reopened.dispose);
    await tester.runAsync(() => reopened.read(startupProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: reopened,
      child: const CompanionFocusApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.descendant(of: primary, matching: find.text('Resume')), findsOneWidget);
  });
}
