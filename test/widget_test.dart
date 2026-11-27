import 'dart:async';
import 'dart:convert';

import 'package:companion_focus/app/app.dart';
import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/app/installed_companion_view.dart';
import 'package:companion_focus/core/notifications/timer_notifications.dart';
import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/core/time/timer_checkpoint.dart';
import 'package:companion_focus/design/appearance_preferences.dart';
import 'package:companion_focus/features/clock/clock_engine.dart';
import 'package:companion_focus/features/companion/companion_library.dart';
import 'package:companion_focus/features/companion/companion_scope.dart';
import 'package:companion_focus/features/focus/background/focus_wallpaper.dart';
import 'package:companion_focus/features/focus/background/focus_wallpaper_store.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:companion_focus/features/insights/insights_page.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'companion/pack_fixture.dart';

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

/// Waits, in bounded steps, until a popped page has left the route stack.
///
/// [Navigator.maybePop] resolves asynchronously, so the reverse transition can
/// start only after the first pump; one fixed pump then lands on the ticker's
/// first frame and still measures zero elapsed time. While the page is still
/// on top its barrier swallows taps meant for the shell below.
Future<void> _settlePushedPage(WidgetTester tester, Finder page) async {
  for (var attempt = 0; attempt < 24 && page.evaluate().isNotEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(page, findsNothing, reason: 'The pushed page should finish closing.');
}

/// Waits, in bounded steps, for a widget the shell only shows after a queued
/// write settles.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets, reason: 'Expected $finder to appear.');
}

/// Binds the Android notifications implementation and answers its channel.
///
/// The generated plugin registrant does not run under `flutter test`, so the
/// plugin would otherwise throw before any call reaches a platform bridge.
/// Register the real Android Dart implementation, as the app does on device,
/// and answer the host calls so the test reports one deterministic state:
/// initialized, with notifications granted only when [enabled] is true.
void _mockNotifications({bool enabled = false}) {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => switch (call.method) {
          'initialize' => true,
          'areNotificationsEnabled' => enabled,
          _ => null,
        },
      );
}

/// Completion requests the app sends to the host, and the platform feedback it
/// must not fall back to.
typedef _TimerFeedback = ({
  List<MethodCall> completions,
  List<String> legacy,
  List<String> unexpected,
});

/// Records what the app asks the host to play for a finished timer.
///
/// Completion feedback travels on its own channel, so a test observes the
/// request instead of the platform sound or vibration behind it. The legacy
/// platform calls stay recorded because a restored finish must not fall back to
/// them. Every call is answered with null, and a method other than
/// `playCompletion` is kept apart so an unexpected request fails an assertion
/// instead of surfacing as a channel exception the app would have to swallow.
_TimerFeedback _captureTimerFeedback() {
  final completions = <MethodCall>[];
  final legacy = <String>[];
  final unexpected = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('app.companionfocus/timer_feedback'),
    (call) async {
      if (call.method == 'playCompletion') {
        completions.add(call);
      } else {
        unexpected.add(call.method);
      }
      return null;
    },
  );
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemSound.play' ||
        call.method == 'HapticFeedback.vibrate') {
      legacy.add(call.method);
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('app.companionfocus/timer_feedback'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  return (completions: completions, legacy: legacy, unexpected: unexpected);
}

/// A control a user can operate, whichever widget the app chooses for it.
///
/// A recovery action could become a text button, a trailing icon button or a
/// tappable row, and each of those keeps an ink response, button or list tile
/// above its wording.
final Finder _operable = find.byWidgetPredicate(
  (widget) =>
      widget is InkResponse ||
      widget is ButtonStyleButton ||
      widget is Switch ||
      widget is ListTile ||
      widget is GestureDetector,
  description: 'an operable settings control',
);

/// Whether [pattern] labels a control the user can tap.
///
/// The check reads the wording a user sees and asks whether a control wraps it,
/// so it survives a different widget choice without pinning exact copy.
bool _hasTappableLabel(WidgetTester tester, Pattern pattern) {
  final labels = find.descendant(
    of: find.byType(SettingsPage),
    matching: find.textContaining(pattern),
  );
  for (var index = 0; index < labels.evaluate().length; index++) {
    final control = find.ancestor(of: labels.at(index), matching: _operable);
    if (control.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Looks for a tappable label, scrolling the pushed Settings list when the
/// control may sit below the first viewport.
///
/// A live companion stage behind the route never settles, so this pumps a
/// bounded number of frames instead of waiting for the whole tree.
Future<bool> _scrollForTappableLabel(
  WidgetTester tester,
  Pattern pattern,
) async {
  final scrollable = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; attempt < 12; attempt++) {
    if (_hasTappableLabel(tester, pattern)) return true;
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }
  return _hasTappableLabel(tester, pattern);
}

/// Wording a user would read on a control for opening the system notification
/// settings.
///
/// The blocked switch row already says "Blocked in Android settings", so each
/// alternative requires an actionable verb or the word "permission" to avoid
/// matching that explanation.
final _settingsRecoveryLabel = RegExp(
  r'open.{0,24}settings|manage.{0,24}settings|allow.{0,32}settings|'
  r'(grant|change|fix).{0,32}permission|'
  r'notification (settings|permission)|system settings|app settings',
  caseSensitive: false,
);

/// Wording a user would read on a control that previews the completion alert.
///
/// Both a preview word and an alert word must appear near each other, so an
/// unrelated "test" elsewhere on the page does not count as the affordance.
final _previewAlertLabel = RegExp(
  r'\b(test|try|preview|sample)\b.{0,32}'
  r'\b(alert|notification|sound|vibration|feedback|chime)\b|'
  r'\b(alert|notification|sound|vibration|feedback|chime)\b.{0,32}'
  r'\b(test|try|preview|sample)\b',
  caseSensitive: false,
);

/// Opens the shell's Settings route and lets its first frame settle.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Wraps a timer snapshot the way the app persists one, without reading the
/// boot clock during test setup.
String _checkpoint(String snapshot) => jsonEncode({
  'timerCheckpoint': 1,
  'snapshot': snapshot,
  'wallMs': DateTime.now().toUtc().millisecondsSinceEpoch,
});

/// Scrolls the pushed Settings list to a section it builds lazily.
///
/// The Local data rows sit below the first viewport, and `ensureVisible` alone
/// cannot reach a row the list has not built yet. The scrollable is scoped to
/// the Settings page because the shell behind the pushed route stays mounted.
Future<void> _scrollSettingsTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byType(Scrollable),
    ),
    maxScrolls: 30,
  );
}

/// Waits for the primary action to be enabled again.
///
/// A finished session is recorded before the page allows the next one, so the
/// control stays disabled while that write is in flight.
Future<void> _awaitPrimaryAction(WidgetTester tester) async {
  final action = find.byKey(FocusPage.primaryActionKey);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (action.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(action).onPressed != null) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    tester.widget<FilledButton>(action).onPressed,
    isNotNull,
    reason: 'The cancelled session must be saved before another one starts.',
  );
}

/// Answers the boot-clock platform call every timer checkpoint awaits.
///
/// A widget test has no host process behind the platform channels, and that
/// reply never reaches a fake-async test body. The checkpoint future would
/// stay pending, blocking the serialized write queue and with it the page's
/// "save the finished session, then allow another" gate.
void _mockBootClock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('app.companionfocus/boot_clock'),
        (call) async => call.method == 'sample'
            ? const <String, int>{'bootCount': 0, 'elapsedMs': 0}
            : null,
      );
}

/// Opens the copy/paste import dialog with [backup] already entered.
Future<void> _openImportDialog(WidgetTester tester, String backup) async {
  await _scrollSettingsTo(tester, find.text('Import backup'));
  await tester.pump();
  await tester.tap(find.text('Import backup'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    backup,
  );
  await tester.pump();
  final restore = find.widgetWithText(FilledButton, 'Restore backup');
  expect(tester.widget<FilledButton>(restore).onPressed, isNotNull);
  expect(restore.hitTestable(), findsOneWidget);
}

/// Confirms the open import dialog and lets its route start closing.
Future<void> _confirmImport(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Restore backup'));
  await tester.pump();
}

/// Returns the pushed Settings list to its top, where notices are rendered.
///
/// The failure notice is the first row of that list, and a lazily built list
/// does not keep a row far above the viewport.
Future<void> _scrollSettingsToTop(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byType(SettingsPage),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable.first).position.jumpTo(0);
  await tester.pump();
  expect(find.text('Timer defaults'), findsOneWidget);
}

/// A deterministic saved session for restore and history assertions.
SessionRecord _sessionRecord(String id, {int minutesAgo = 25}) {
  final finish = DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo));
  return SessionRecord(
    id: id,
    startedAt: finish.subtract(const Duration(minutes: 25)),
    finishedAt: finish,
    intended: const Duration(minutes: 25),
    actual: const Duration(minutes: 25),
    completed: true,
  );
}

/// A database whose next history read faults on demand.
///
/// A restore reads the rows it just wrote, so a fault there is the case that
/// must not leave a failed-looking replacement behind or invite a second one.
class _FlakyHistoryDatabase extends LocalDatabase {
  _FlakyHistoryDatabase(super.executor);

  bool failNextRead = false;

  @override
  Future<List<SessionRecord>> sessions() {
    if (failNextRead) {
      failNextRead = false;
      return Future<List<SessionRecord>>.error(
        Exception('The history read failed.'),
      );
    }
    return super.sessions();
  }
}

void main() {
  test('a restore stores none only when a usable photo wins', () {
    const imported = AppSettings(
      appearance: AppearancePreferences(wallpaper: WallpaperType.embers),
    );

    final photoWins = restoredWallpaperSettings(imported, photoWins: true);
    expect(photoWins.appearance.wallpaper, WallpaperType.none);
    expect(photoWins.focusMinutes, imported.focusMinutes);
    expect(photoWins.themeMode, imported.themeMode);

    // Without a usable photo the imported live choice is kept untouched.
    expect(
      identical(
        restoredWallpaperSettings(imported, photoWins: false),
        imported,
      ),
      isTrue,
    );
  });

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
    // Development tools stay opt-in at build time; a debug build alone must
    // not expose the laboratory or the generated catalogue.
    final settingsPage = tester.widget<SettingsPage>(find.byType(SettingsPage));
    expect(settingsPage.animationLab, isNull);
    expect(settingsPage.developmentPacks, isNull);
    // The permission check is wired only where the plugin exists, so the page
    // reports the revoked state instead of guessing.
    expect(settingsPage.notificationsAvailable, TimerNotifications.available);
    expect(
      settingsPage.checkNotificationPermission,
      TimerNotifications.available ? isNotNull : isNull,
    );
    // The registered Android implementation reaches the stubbed host and
    // reports the real denied state, proving the binding instead of relying on
    // an error that never reaches the channel.
    final checkPermission = settingsPage.checkNotificationPermission;
    if (checkPermission != null) {
      bool? allowed;
      unawaited(checkPermission().then((value) {
        allowed = value;
      }));
      for (var attempt = 0; attempt < 20 && allowed == null; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(allowed, isFalse);
    }
    // The shell below the opaque settings route stops ticking, then resumes.
    expect(_tabTicker(tester, 0, skipOffstage: false).enabled, isFalse);

    await tester.pageBack();
    await tester.pump();
    await _settlePushedPage(tester, find.byType(SettingsPage));
    expect(find.text('MinuteMeadow'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(_tabTicker(tester, 0).enabled, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a revoked permission keeps completion feedback in the foreground', (
    tester,
  ) async {
    final feedback = _captureTimerFeedback();
    final app = _app(
      settings: const AppSettings(
        focusMinutes: 1,
        notifications: true,
        sound: true,
        haptics: false,
      ),
    );
    // The boot clock jumps while the process stays alive, so returning to the
    // app discovers an expired timer in the foreground, not on a cold start.
    // Install this after _app so its default boot-clock stub does not win.
    var bootElapsedMs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.companionfocus/boot_clock'),
          (call) async => call.method == 'sample'
              ? <String, int>{'bootCount': 0, 'elapsedMs': bootElapsedMs}
              : null,
        );

    await tester.pumpWidget(app);
    await _frames(tester, 6);

    final primary = find.byKey(FocusPage.primaryActionKey);
    await tester.ensureVisible(primary);
    await tester.pump();
    await tester.tap(primary);
    await _frames(tester, 4);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // Let the background reading finish before the clock jumps, so the jump is
    // measured as time the process missed.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    bootElapsedMs = const Duration(minutes: 2).inMilliseconds;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntil(tester, find.text('Focus complete'));
    await _awaitPrimaryAction(tester);

    expect(
      feedback.completions,
      hasLength(1),
      reason: 'A revoked permission and stored notification intent must not '
          'suppress the in-app completion alert while the app is in the '
          'foreground.',
    );
    final request = feedback.completions.single.arguments;
    expect(
      request,
      isA<Map<Object?, Object?>>(),
      reason: 'The completion request must name the feedback it wants.',
    );
    expect(
      (request as Map<Object?, Object?>)['sound'],
      isTrue,
      reason: 'Sound was enabled for the completion alert.',
    );
    expect(
      feedback.unexpected,
      isEmpty,
      reason: 'The agreed channel carries the playCompletion request alone.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a cold start never replays completion feedback', (tester) async {
    final feedback = _captureTimerFeedback();
    final now = DateTime.now().toUtc();
    final expired = FocusSnapshot(
      id: 'expired-session',
      phase: FocusPhase.focus,
      status: FocusStatus.running,
      startedAt: now.subtract(const Duration(minutes: 26)),
      anchor: now.subtract(const Duration(minutes: 26)),
      intended: const Duration(minutes: 25),
      remaining: null,
      finishedAt: null,
      completedFocusSessions: 0,
      planTarget: 1,
      planSettings: const FocusSettings(),
    ).encode();

    await tester.pumpWidget(_app(focus: expired));
    await _frames(tester, 6);
    await _pumpUntil(tester, find.text('Focus complete'));
    await _awaitPrimaryAction(tester);

    expect(
      feedback.completions,
      isEmpty,
      reason: 'A session that ended while the app was not running must settle '
          'without asking the host to play completion feedback.',
    );
    expect(
      feedback.legacy,
      isEmpty,
      reason: 'A restored finish must not fall back to the in-app click or '
          'vibration either.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('blocked notifications offer an Android settings recovery action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(settings: const AppSettings(notifications: true)),
    );
    await _frames(tester, 6);
    await _openSettings(tester);
    await _pumpUntil(
      tester,
      find.textContaining('Blocked in Android settings'),
    );

    expect(
      await _scrollForTappableLabel(tester, _settingsRecoveryLabel),
      isTrue,
      reason: 'The blocked state must offer a control that opens the system '
          'notification settings, not only explanatory text.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings expose a preview of the completion alert', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        settings: const AppSettings(notifications: true),
        notificationsEnabled: true,
      ),
    );
    await _frames(tester, 6);
    await _openSettings(tester);
    await _pumpUntil(tester, find.text('Completion notifications'));

    expect(
      await _scrollForTappableLabel(tester, _previewAlertLabel),
      isTrue,
      reason: 'Settings must expose a control that previews the completion '
          'alert so a user can verify it without waiting for a timer.',
    );

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
    await _settlePushedPage(tester, find.byType(SettingsPage));
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
    await _settlePushedPage(tester, find.byType(SettingsPage));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Clock'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an empty library injects no sample or empty companion stage', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _frames(tester);

    // One authoritative library is shared by every route and destination.
    expect(find.byType(CompanionSessionScope), findsOneWidget);

    // Normal Focus mounts no companion renderer, so no sample or empty stage
    // can appear there.
    expect(find.byType(InstalledCompanionView), findsNothing);
    expect(find.byKey(const ValueKey('companion-empty-stage')), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Companion'),
      ),
    );
    await _frames(tester);

    // The Companion destination leads with the real library, not a stage.
    expect(find.byType(InstalledCompanionView), findsNothing);
    expect(find.byKey(const ValueKey('companion-empty-stage')), findsNothing);
    expect(find.byTooltip('Import pack'), findsOneWidget);
    expect(find.text('No companions installed'), findsOneWidget);
    expect(find.text('Browse marketplace'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an installed companion is managed without an auto-mounted stage', (
    tester,
  ) async {
    // Keep the whole pack detail, including its remove control, on screen.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final installed = installedFixture();
    final snapshot = CompanionLibrary.empty.install(installed).encode();
    await tester.pumpWidget(_app(companion: snapshot));
    await _frames(tester);

    // Normal Focus stays pet-free even when a real pack is installed.
    expect(find.byType(InstalledCompanionView), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Companion'),
      ),
    );
    await _frames(tester);

    // The destination lists the real library and mounts no renderer above it.
    expect(find.byType(InstalledCompanionView), findsNothing);
    expect(find.byTooltip('Import pack'), findsOneWidget);
    expect(find.text('No companions installed'), findsNothing);
    expect(find.text(installed.manifest.name), findsOneWidget);

    // The existing renderer appears only in the explicitly opened detail.
    await tester.tap(find.text(installed.manifest.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final preview = tester.widget<InstalledCompanionView>(
      find.byType(InstalledCompanionView),
    );
    expect(preview.pack?.id, installed.id);
    expect(preview.useDevelopmentFixture, isFalse);
    expect(preview.showInteractionControls, isTrue);
    expect(preview.stageHeight, 240);
    // The detail shows the real manifest, and the pack can be removed there.
    expect(find.text('Version'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Remove'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('insights edits and deletions persist through the shell', (
    tester,
  ) async {
    // Keep the whole history sheet and its dialogs on screen.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finish = DateTime.now().toUtc();
    final session = SessionRecord(
      id: 'editable-session',
      startedAt: finish.subtract(const Duration(minutes: 25)),
      finishedAt: finish,
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
    );
    final database = LocalDatabase(NativeDatabase.memory());
    await tester.runAsync(() => database.record(session));

    await tester.pumpWidget(_app(database: database, sessions: [session]));
    await _frames(tester, 6);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Insights'),
      ),
    );
    await _frames(tester, 6);
    await tester.ensureVisible(find.byKey(InsightsPage.historyButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(InsightsPage.historyButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(InsightsHistoryPage), findsOneWidget);

    // Editing the label goes through the shell's serialized write queue.
    await tester.tap(find.byKey(InsightsHistoryPage.sessionRowKey(session.id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Edit label or note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byKey(InsightsHistoryPage.editorLabelKey),
      'Deep work',
    );
    await tester.tap(find.byKey(InsightsHistoryPage.editorSaveKey));
    await _pumpUntil(tester, find.text('Session updated.'));
    expect(find.text('Deep work'), findsWidgets);

    // The edit confirmation is still on screen. Clear it so the delete's own
    // confirmation appears immediately instead of queueing behind it for the
    // rest of the first snackbar's display time.
    ScaffoldMessenger.of(
      tester.element(find.byType(InsightsHistoryPage)),
    ).hideCurrentSnackBar();
    await tester.pump(const Duration(milliseconds: 300));

    final stored = await tester.runAsync(
      () => database.sessions().then((records) => records.single),
    );
    expect(stored?.label, 'Deep work');
    // Only descriptive text changes; the recorded outcome stays intact.
    expect(stored?.actual, const Duration(minutes: 25));
    expect(stored?.completed, isTrue);

    // Deleting from the same history page removes the row through the shell.
    await tester.longPress(
      find.byKey(InsightsHistoryPage.sessionRowKey(session.id)),
    );
    await _frames(tester);
    await tester.tap(find.byKey(InsightsHistoryPage.deleteSelectedKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await _pumpUntil(tester, find.text('Session deleted.'));

    expect(find.byKey(InsightsHistoryPage.sessionRowKey(session.id)), findsNothing);
    final remaining = await tester.runAsync(() => database.sessions());
    expect(remaining, isEmpty);

    // The overview rebuilds from the fresh records, not its own copy.
    await tester.pageBack();
    await tester.pump();
    await _settlePushedPage(tester, find.byType(InsightsHistoryPage));
    expect(find.text('No sessions yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a partially stale selection deletes nothing', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finish = DateTime.now().toUtc();
    final saved = SessionRecord(
      id: 'saved-session',
      startedAt: finish.subtract(const Duration(minutes: 25)),
      finishedAt: finish,
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
    );
    // The shell lists a second session that the database no longer holds, the
    // shape a restore or an earlier partial delete can leave behind.
    final stale = SessionRecord(
      id: 'stale-session',
      startedAt: finish.subtract(const Duration(minutes: 50)),
      finishedAt: finish.subtract(const Duration(minutes: 25)),
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
    );
    final database = LocalDatabase(NativeDatabase.memory());
    await tester.runAsync(() => database.record(saved));

    await tester.pumpWidget(_app(database: database, sessions: [saved, stale]));
    await _frames(tester, 6);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Insights'),
      ),
    );
    await _frames(tester, 6);
    await tester.ensureVisible(find.byKey(InsightsPage.historyButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(InsightsPage.historyButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Select both rows and ask the shell to delete them in one transaction.
    await tester.longPress(
      find.byKey(InsightsHistoryPage.sessionRowKey(saved.id)),
    );
    await _frames(tester);
    await tester.tap(find.byKey(InsightsHistoryPage.sessionRowKey(stale.id)));
    await _frames(tester);
    await tester.tap(find.byKey(InsightsHistoryPage.deleteSelectedKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await _pumpUntil(tester, find.byKey(InsightsHistoryPage.errorBannerKey));

    // The mismatch is reported instead of succeeding, and the row that did
    // exist survives: the refused deletion was rolled back, not partially kept.
    expect(find.text('2 sessions deleted.'), findsNothing);
    final rows = await tester.runAsync(() => database.sessions());
    expect(rows, isNotNull);
    expect([for (final row in rows!) row.id], [saved.id]);
    // Nothing was published to the shell, so the page still shows its own list.
    expect(find.byKey(InsightsHistoryPage.sessionRowKey(saved.id)), findsOneWidget);

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
    // The cancelled session is recorded before another one may start.
    await _awaitPrimaryAction(tester);

    await tester.ensureVisible(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await _frames(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an ordinary restore keeps saved timer presets but no active run', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().toUtc();
    final savedPlan = FocusPlanState.initial
        .addPreset(
          'Evening',
          const FocusSettings(
            focusMinutes: 50,
            shortBreakMinutes: 10,
            longBreakMinutes: 20,
          ),
          makeDefault: true,
        )
        .useOneOff(const FocusSettings(focusMinutes: 90))
        .withAutoAdvance(true);

    // What the device held before the restore: a running Focus session with a
    // pending one-off plan, and a Clock with a preset plus a live stopwatch run.
    final clock = ClockEngine(nowMicroseconds: () => 0)
      ..addPreset(label: 'Tea', duration: const Duration(minutes: 5));
    clock
      ..setMode(ClockMode.stopwatch)
      ..start()
      ..addLap()
      ..setMode(ClockMode.countdown)
      ..start();

    final database = LocalDatabase(NativeDatabase.memory());
    await tester.runAsync(
      () => database.writeState(
        'focus',
        _checkpoint(
          FocusSnapshot(
            id: 'running-session',
            phase: FocusPhase.focus,
            status: FocusStatus.running,
            startedAt: now.subtract(const Duration(minutes: 5)),
            anchor: now,
            intended: const Duration(minutes: 50),
            remaining: null,
            finishedAt: null,
            completedFocusSessions: 2,
            planTarget: 4,
            planCompleted: 1,
          ).encode(plan: savedPlan),
        ),
      ),
    );
    await tester.runAsync(
      () => database.writeState('clock', _checkpoint(clock.snapshot())),
    );

    await tester.pumpWidget(_app(database: database));
    await _frames(tester, 6);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final backup = DataBackup(
      settings: const AppSettings(focusMinutes: 30),
      sessions: const [],
    ).encode();
    await _scrollSettingsTo(tester, find.text('Import backup'));
    await tester.pump();
    await tester.tap(find.text('Import backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      backup,
    );
    await tester.pump();
    final restore = find.widgetWithText(FilledButton, 'Restore backup');
    expect(tester.widget<FilledButton>(restore).onPressed, isNotNull);
    // A hit-testable match proves the dialog action is on screen and uncovered.
    expect(restore.hitTestable(), findsOneWidget);
    await tester.tap(restore);
    await _pumpUntil(tester, find.text('Backup restored.'));

    final storedFocus = await tester.runAsync(() => database.readState('focus'));
    final storedClock = await tester.runAsync(() => database.readState('clock'));
    final restoredFocus = FocusSnapshot.tryDecode(
      TimerCheckpoint.decode(storedFocus!)!.snapshot,
    )!;
    final restoredClock = ClockEngine(
      nowMicroseconds: () => 0,
      initialSnapshot: TimerCheckpoint.decode(storedClock!)!.snapshot,
    );

    // The saved plan survives intact: the named preset, its default status and
    // the auto-advance preference. The one-off plan and the run do not.
    final plan = restoredFocus.plan!;
    final names = [for (final preset in plan.presets) preset.name];
    expect(names, contains('Evening'));
    expect(plan.defaultPreset.name, 'Evening');
    expect(plan.autoAdvance, isTrue);
    expect(plan.oneOffSettings, isNull);
    expect(restoredFocus.status, FocusStatus.ready);
    expect(restoredFocus.id, isEmpty);
    expect(restoredFocus.planTarget, 0);
    expect(restoredFocus.intended, const Duration(minutes: 50));

    // The Clock keeps its preset and visible mode while the run and laps go.
    final labels = [for (final preset in restoredClock.presets) preset.label];
    expect(labels, contains('Tea'));
    expect(restoredClock.laps, isEmpty);
    expect(restoredClock.isRunning, isFalse);
    expect(restoredClock.mode, ClockMode.countdown);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a restore that cannot read its commit leaves nothing behind', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final kept = _sessionRecord('kept-session');
    final imported = _sessionRecord('imported-session', minutesAgo: 90);
    final database = _FlakyHistoryDatabase(NativeDatabase.memory());
    await tester.runAsync(() => database.record(kept));

    await tester.pumpWidget(_app(database: database, sessions: [kept]));
    await _frames(tester, 6);
    await _openSettings(tester);

    // What the device holds before the attempt, so the rollback is compared
    // against it rather than against an assumption about the boot state.
    final beforeSettings = await tester.runAsync(
      () => database.readState('settings'),
    );
    final beforeRows = await tester.runAsync(() => database.sessions());

    final backup = DataBackup(
      settings: const AppSettings(focusMinutes: 30),
      sessions: [imported],
    ).encode();
    await _openImportDialog(tester, backup);

    // The replacement writes settings and history and then reads the rows it
    // wrote. That read faults, so the replacement must not survive: a durable
    // restore reported as failed invites the user to repeat it.
    database.failNextRead = true;
    await _confirmImport(tester);
    await _scrollSettingsToTop(tester);
    await _pumpUntil(
      tester,
      find.text('Could not restore the backup. Try again.'),
    );
    expect(
      find.text('Could not restore the backup. Try again.'),
      findsOneWidget,
      reason: 'The fault is still reported, so the user is not told the '
          'replacement succeeded.',
    );
    expect(find.text('Backup restored.'), findsNothing);

    // Nothing was committed: the stored settings and history are the ones the
    // device held before the attempt.
    expect(
      await tester.runAsync(() => database.readState('settings')),
      beforeSettings,
    );
    final rows = await tester.runAsync(() => database.sessions());
    expect(
      [for (final row in rows!) row.id],
      [for (final row in beforeRows!) row.id],
    );

    // The offered retry runs the same restore, and this time it commits once.
    await tester.tap(find.text('Try again'));
    await _pumpUntil(tester, find.text('Backup restored.'));
    final after = await tester.runAsync(() => database.sessions());
    expect([for (final row in after!) row.id], ['imported-session']);
    final stored = await tester.runAsync(() => database.readState('settings'));
    expect(AppSettings.decode(stored!).focusMinutes, 30);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a restore keeps an imported live wallpaper when no photo is usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = LocalDatabase(NativeDatabase.memory());
    // The slot stores encoded bytes, so a row can exist that is not a usable
    // photo. It must not take the imported live choice away, and a restore
    // must never erase it either.
    await tester.runAsync(() async {
      final store = FocusWallpaperStore(database);
      await store.write(
        FocusWallpaperPhoto(bytes: Uint8List.fromList(<int>[1, 2, 3])),
      );
      await database.writeState('focus_wallpaper_location', 'active');
    });

    await tester.pumpWidget(_app(database: database));
    await _frames(tester, 6);
    await _openSettings(tester);

    final backup = DataBackup(
      settings: const AppSettings(
        appearance: AppearancePreferences(wallpaper: WallpaperType.embers),
      ),
      sessions: const [],
    ).encode();
    await _openImportDialog(tester, backup);
    await _confirmImport(tester);
    await _pumpUntil(tester, find.text('Backup restored.'));

    // Return to the shell so the restored wallpaper is read from the page the
    // user actually sees, not from a route the Settings page covers.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final page = tester.widget<FocusPage>(find.byType(FocusPage));
    expect(page.wallpaperSelection.isPhoto, isFalse);
    expect(page.wallpaperSelection.appearanceType, WallpaperType.embers);
    expect(page.wallpaperLocation, WallpaperLocation.active);

    final stored = await tester.runAsync(() => database.readState('settings'));
    expect(
      AppSettings.decode(stored!).appearance.wallpaper,
      WallpaperType.embers,
      reason: 'Only a usable local photo may replace the imported live '
          'wallpaper with none.',
    );
    final kept = await tester.runAsync(
      () => FocusWallpaperStore(database).read(),
    );
    expect(kept?.bytes, <int>[1, 2, 3]);

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
  LocalDatabase? database,
  bool notificationsEnabled = false,
}) {
  _mockBootClock();
  _mockNotifications(enabled: notificationsEnabled);
  final storage = database ?? LocalDatabase(NativeDatabase.memory());
  addTearDown(storage.close);
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(storage),
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
