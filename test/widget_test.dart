import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/app/installed_companion_view.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/companion/companion_page.dart';
import 'package:companion_focus/features/companion/companion_scope.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Advances a fixed number of frames so a live companion stage can never make
/// the suite wait forever.
Future<void> _frames(WidgetTester tester, [int count = 4]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// The per-destination ticker gate the shell wraps every tab in.
TickerMode _tabTicker(
  WidgetTester tester,
  int index, {
  bool skipOffstage = true,
}) => tester.widget<TickerMode>(
  find.byKey(ValueKey('tab-ticker-$index'), skipOffstage: skipOffstage),
);

void main() {
  testWidgets('opens the four destinations and returns from settings', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _frames(tester);

    expect(find.text('MinuteMeadow'), findsOneWidget);
    expect(_tabTicker(tester, 0).enabled, isTrue);

    final navigation = find.byType(NavigationBar);
    for (final (step, label) in ['Clock', 'Companion', 'Insights', 'Focus']
        .indexed) {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(label)),
      );
      await _frames(tester);
      final selected = (step + 1) % 4;
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, selected);
      expect(_tabTicker(tester, selected).enabled, isTrue);
      // Hidden IndexedStack children are offstage, so look them up explicitly.
      expect(_tabTicker(tester, step, skipOffstage: false).enabled, isFalse);
    }
    expect(_tabTicker(tester, 0).enabled, isTrue);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Timer defaults'), findsOneWidget);
    // The shell below the opaque settings route stops ticking, then resumes.
    expect(_tabTicker(tester, 0, skipOffstage: false).enabled, isFalse);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('MinuteMeadow'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(_tabTicker(tester, 0).enabled, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main destinations reflow on a narrow phone with large text', (
    tester,
  ) async {
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
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: app,
      ),
    ));
    await _frames(tester, 6);

    final navigation = find.byType(NavigationBar);
    expect(Theme.of(tester.element(navigation)).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    for (final label in ['Clock', 'Companion', 'Insights', 'Focus']) {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(label)),
      );
      await _frames(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: '$label should fit at 320 dp',
      );
    }
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Timer defaults'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('focus timer link opens the shared settings route', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _frames(tester);
    final focusState = tester.state<State<FocusPage>>(find.byType(FocusPage));

    await tester.ensureVisible(find.byKey(FocusPage.configureTimersKey));
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.configureTimersKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Timer defaults'), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(identical(tester.state<State<FocusPage>>(find.byType(FocusPage)), focusState), isTrue);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    // The AppBar entry point pushes the same route and keeps the current tab.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Clock'),
      ),
    );
    await _frames(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Clock'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('draws the shared stage on Focus and Companion', (tester) async {
    await tester.pumpWidget(_app());
    await _frames(tester);

    // One authoritative library is shared by every route and destination.
    expect(find.byType(CompanionSessionScope), findsOneWidget);

    final focusStage = tester.widget<InstalledCompanionView>(
      find.descendant(
        of: find.byKey(FocusPage.stageKey),
        matching: find.byType(InstalledCompanionView),
      ),
    );
    expect(focusStage.key, const ValueKey('companion-stage-development'));
    expect(focusStage.showInteractionControls, isFalse);
    // The Focus stage fills its square; the confirmation is a live-region
    // label on the stage, so no inline notice height is reserved.
    expect(
      focusStage.stageHeight,
      tester.getSize(find.byKey(FocusPage.stageKey)).shortestSide,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Companion'),
      ),
    );
    await _frames(tester);

    final destinationStage = tester.widget<InstalledCompanionView>(
      find.descendant(
        of: find.byType(CompanionPage),
        matching: find.byType(InstalledCompanionView),
      ),
    );
    expect(destinationStage.key, const ValueKey('companion-stage-development'));
    expect(destinationStage.showInteractionControls, isTrue);
    expect(destinationStage.stageHeight, 220);
    expect(find.text('No companions installed'), findsOneWidget);
    expect(find.text('Browse marketplace'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('running and paused focus hide chrome, quit restores it', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _frames(tester);
    final focusState = tester.state<State<FocusPage>>(find.byType(FocusPage));

    await tester.ensureVisible(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await _frames(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(identical(tester.state<State<FocusPage>>(find.byType(FocusPage)), focusState), isTrue);

    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await _frames(tester);
    expect(find.text('Paused. Continue when you are ready.'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(identical(tester.state<State<FocusPage>>(find.byType(FocusPage)), focusState), isTrue);

    await tester.tap(find.byKey(FocusPage.closeActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Cancel this focus session?'), findsOneWidget);
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _frames(tester, 8);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Session cancelled'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);
    expect(identical(tester.state<State<FocusPage>>(find.byType(FocusPage)), focusState), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starts a restored paused session immersive and survives Back', (
    tester,
  ) async {
    await tester.pumpWidget(_app(focus: _pausedSnapshot()));
    await _frames(tester, 6);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    expect(
      tester.widget<FocusPage>(find.byType(FocusPage)).key,
      const ValueKey(('focus', 0)),
    );

    // Simulates the Android system Back button at the root route.
    // ignore: invalid_use_of_protected_member
    final backHandled = await tester.binding.handlePopRoute();
    expect(backHandled, isTrue, reason: 'Back must not exit the session');
    await _frames(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FocusPage), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.byKey(FocusPage.closeActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _frames(tester, 8);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Session cancelled'), findsOneWidget);

    await tester.ensureVisible(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await _frames(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

String _pausedSnapshot() {
  final now = DateTime.now().toUtc();
  return FocusSnapshot(
    id: 'paused-session',
    phase: FocusPhase.focus,
    status: FocusStatus.paused,
    startedAt: now.subtract(const Duration(minutes: 8)),
    anchor: now.subtract(const Duration(minutes: 8)),
    intended: const Duration(minutes: 25),
    remaining: const Duration(minutes: 12),
    finishedAt: null,
    completedFocusSessions: 0,
  ).encode();
}

Widget _app({
  AppSettings settings = const AppSettings(),
  List<SessionRecord> sessions = const [],
  String? focus,
  String? companion,
}) {
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      startupProvider.overrideWith(
        (ref) => StartupData(
          settings: settings,
          focus: focus,
          clock: null,
          companion: companion,
          sessions: sessions,
        ),
      ),
    ],
    child: const CompanionFocusApp(),
  );
}
