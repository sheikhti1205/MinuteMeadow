import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/core/time/boot_clock.dart';
import 'package:companion_focus/core/time/timer_checkpoint.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The debug build can run the live companion stage, so its animation never
/// settles. Advance a fixed number of frames instead of waiting for quiet.
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 16,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(step);
  }
}

Future<List<SessionRecord>> _readSessions(
  WidgetTester tester,
  LocalDatabase database,
) async {
  final sessions = await tester.runAsync(database.sessions);
  return sessions ?? const <SessionRecord>[];
}

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
      // Start from a clean timer and history so the counts and labels are exact.
      await database.customStatement(
        "DELETE FROM app_state WHERE name IN ('focus', 'clock')",
      );
      await database.customStatement('DELETE FROM focus_sessions');
      await container.read(startupProvider.future);
      final boot = await BootClock.sample();
      expect(boot, isNotNull);
      expect(boot!.elapsed, greaterThan(Duration.zero));
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CompanionFocusApp(),
    ));
    await _pumpFrames(tester);
    expect(find.text('MinuteMeadow'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Focus duration'));
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextFormField), '37');
    await tester.tap(find.text('Save'));
    await _pumpFrames(tester);

    AppSettings? savedSettings;
    for (var attempt = 0; attempt < 20; attempt++) {
      final stored = await tester.runAsync(() => database.readState('settings'));
      savedSettings = stored == null ? null : AppSettings.decode(stored);
      if (savedSettings?.focusMinutes == 37) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(savedSettings?.focusMinutes, 37);
    await _pumpFrames(tester);
    expect(find.text('37 min'), findsOneWidget);

    await tester.pageBack();
    await _pumpFrames(tester);
    final primary = find.byKey(FocusPage.primaryActionKey);
    // The action stays above the shell navigation, so a compact 320 x 640
    // device reaches it without scrolling.
    final page = tester.getRect(find.byType(FocusPage));
    final action = tester.getRect(primary);
    expect(action.top, greaterThanOrEqualTo(page.top));
    expect(action.bottom, lessThanOrEqualTo(page.bottom));
    expect(primary.hitTestable(), findsOneWidget);
    await tester.tap(primary);
    await _pumpFrames(tester);
    expect(find.descendant(of: primary, matching: find.text('Pause')), findsOneWidget);

    // Running focus is immersive: the shell removes its header and tabs.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(primary);
    await _pumpFrames(tester);
    expect(find.descendant(of: primary, matching: find.text('Resume')), findsOneWidget);
    // A paused session still owns the immersive layout.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

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
    expect(await _readSessions(tester, database), isEmpty);

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
    await _pumpFrames(tester);
    expect(find.descendant(of: primary, matching: find.text('Resume')), findsOneWidget);
    // The recovered paused session resumes immersive and hides shell chrome.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    // Explicit quit through the slide control. The dialog confirms the
    // cancellation, then the shell restores its header and bottom navigation.
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    final slideToQuit = find.byKey(FocusPage.slideToQuitKey);
    await tester.drag(
      slideToQuit,
      Offset(tester.getSize(slideToQuit).width, 0),
    );
    await _pumpFrames(tester);
    expect(find.text('Cancel this focus session?'), findsOneWidget);
    await tester.tap(find.text('Cancel session'));
    await _pumpFrames(tester);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Session cancelled'), findsOneWidget);

    List<SessionRecord> sessions = const [];
    for (var attempt = 0; attempt < 20; attempt++) {
      sessions = await _readSessions(tester, database);
      if (sessions.length == 1) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sessions, hasLength(1));
    expect(sessions.single.completed, isFalse);
    expect(sessions.single.intended, const Duration(minutes: 37));
  });
}
