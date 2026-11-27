import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/clock/clock_engine.dart';
import 'package:companion_focus/features/clock/clock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonotonicClock {
  int micros = 0;

  int now() => micros;

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
  }
}

Widget _harness(
  ClockEngine engine, {
  List<String>? snapshots,
  VoidCallback? onCountdownCompleted,
  List<DateTime?>? deadlines,
  DateTime Function()? wallClock,
  Future<void> Function(String)? onSnapshot,
}) {
  return MaterialApp(
    theme: CompanionTheme.light,
    home: ClockPage(
      initialSnapshot: null,
      engine: engine,
      onSnapshot:
          onSnapshot ?? (String value) async => snapshots?.add(value),
      onCountdownCompleted: onCountdownCompleted,
      onCountdownDeadlineChanged: (DateTime? value) async =>
          deadlines?.add(value),
      wallClock: wallClock,
    ),
  );
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> _showMode(WidgetTester tester, String label) async {
  // The segmented control comes before the card in the tree, so the first
  // match is always the mode selector.
  await tester.tap(find.text(label).first);
  await tester.pump();
}

Future<void> _enterDuration(
  WidgetTester tester, {
  required String hours,
  required String minutes,
  required String seconds,
}) async {
  await tester.enterText(find.byKey(ClockPage.hoursFieldKey), hours);
  await tester.enterText(find.byKey(ClockPage.minutesFieldKey), minutes);
  await tester.enterText(find.byKey(ClockPage.secondsFieldKey), seconds);
}

void main() {
  testWidgets('shows one dominant stopwatch display and a start action', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));

    expect(find.text('00:00.0'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stopwatch'), findsNWidgets(2));
    expect(find.text('Countdown'), findsOneWidget);
    expect(find.byTooltip('Reset'), findsOneWidget);
    expect(find.byTooltip('Lap'), findsOneWidget);
    expect(find.byTooltip('Repeat'), findsNothing);
  });

  testWidgets('start, tick, pause, lap and reset use the injected clock', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    final snapshots = <String>[];

    await tester.pumpWidget(_harness(engine, snapshots: snapshots));

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(engine.isRunning, isTrue);
    expect(find.text('Pause'), findsOneWidget);
    expect(snapshots, isNotEmpty);

    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('00:02.0'), findsOneWidget);

    await tester.tap(find.byTooltip('Lap'));
    await tester.pump();
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Lap'));
    await tester.pump();
    expect(find.text('Lap 2'), findsOneWidget);
    expect(engine.laps[1].splitMicros, 1000000);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(engine.isRunning, isFalse);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(find.text('00:00.0'), findsOneWidget);
    expect(find.text('Lap 1'), findsNothing);
    expect(engine.laps, isEmpty);

    await _dispose(tester);
  });

  testWidgets('the stopwatch readout yields to the lap rows', (tester) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    Text readout() => tester.widget<Text>(find.byKey(ClockPage.timeKey));

    await tester.pumpWidget(_harness(engine));
    await tester.tap(find.text('Start'));
    await tester.pump();
    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));

    expect(readout().style?.fontSize, 64);

    await tester.tap(find.byTooltip('Lap'));
    await tester.pump();
    expect(readout().style?.fontSize, 44);

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(readout().style?.fontSize, 64);

    await _dispose(tester);
  });

  testWidgets('restores a countdown snapshot and shows remaining time', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final original = ClockEngine(
      nowMicroseconds: clock.now,
      processToken: 'shared',
    );
    original.setCountdownDuration(const Duration(minutes: 10));
    original.start();
    clock.advance(const Duration(minutes: 1));
    original.pause();

    final restored = ClockEngine(
      nowMicroseconds: clock.now,
      initialSnapshot: original.snapshot(),
      processToken: 'shared',
    );

    await tester.pumpWidget(_harness(restored));

    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('of 10:00'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Countdown'), findsNWidgets(2));
  });

  testWidgets('sets an exact one-off hours, minutes and seconds duration', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));
    await _showMode(tester, 'Countdown');

    await tester.tap(find.byKey(ClockPage.setDurationKey));
    await tester.pumpAndSettle();
    await _enterDuration(tester, hours: '1', minutes: '2', seconds: '3');
    await tester.tap(find.byKey(ClockPage.durationSubmitKey));
    await tester.pumpAndSettle();

    expect(engine.countdownDuration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(find.text('1:02:03'), findsOneWidget);
    expect(find.text('of 1:02:03'), findsOneWidget);
    expect(engine.presets, isEmpty);

    await _dispose(tester);
  });

  testWidgets('rejects invalid one-off durations without closing the editor', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));
    await _showMode(tester, 'Countdown');

    await tester.tap(find.byKey(ClockPage.setDurationKey));
    await tester.pumpAndSettle();

    await _enterDuration(tester, hours: '0', minutes: '0', seconds: '0');
    await tester.tap(find.byKey(ClockPage.durationSubmitKey));
    await tester.pump();
    expect(find.text('Choose at least 1 second.'), findsOneWidget);
    expect(find.text('Set countdown'), findsOneWidget);

    await _enterDuration(tester, hours: '24', minutes: '30', seconds: '0');
    await tester.tap(find.byKey(ClockPage.durationSubmitKey));
    await tester.pump();
    expect(find.text('Keep the duration at 24 hours or less.'), findsOneWidget);

    await _enterDuration(tester, hours: '2', minutes: '5', seconds: '0');
    await tester.tap(find.byKey(ClockPage.durationSubmitKey));
    await tester.pumpAndSettle();

    expect(engine.countdownDuration, const Duration(hours: 2, minutes: 5));
    expect(find.text('2:05:00'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('creates, edits and confirms deletion of presets', (tester) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));
    await _showMode(tester, 'Countdown');
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byKey(ClockPage.addPresetKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ClockPage.presetLabelKey), 'Study');
    await _enterDuration(tester, hours: '0', minutes: '5', seconds: '0');
    await tester.tap(find.byKey(ClockPage.presetSubmitKey));
    await tester.pumpAndSettle();

    expect(engine.presets, hasLength(1));
    expect(find.text('Study'), findsOneWidget);

    await tester.tap(find.byTooltip('Preset options for Study'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ClockPage.presetLabelKey), 'Deep work');
    await _enterDuration(tester, hours: '0', minutes: '10', seconds: '0');
    await tester.tap(find.byKey(ClockPage.presetSubmitKey));
    await tester.pumpAndSettle();

    expect(engine.presets.single.label, 'Deep work');
    expect(
      engine.presets.single.durationMicros,
      const Duration(minutes: 10).inMicroseconds,
    );
    expect(find.text('Deep work'), findsOneWidget);

    await tester.tap(find.byTooltip('Preset options for Deep work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Deep work?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(engine.presets, hasLength(1));

    await tester.tap(find.byTooltip('Preset options for Deep work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(engine.presets, isEmpty);
    expect(find.text('Deep work'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('selecting a preset sets the countdown duration', (tester) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    final preset = engine.addPreset(
      label: 'Short break',
      duration: const Duration(minutes: 5),
    );

    await tester.pumpWidget(_harness(engine));
    await _showMode(tester, 'Countdown');
    await tester.tap(find.text('Short break'));
    await tester.pumpAndSettle();

    expect(engine.selectedPresetId, preset.id);
    expect(engine.countdownDuration, const Duration(minutes: 5));
    expect(find.text('of 05:00'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('switching modes preserves a running stopwatch', (tester) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));
    await tester.tap(find.text('Start'));
    await tester.pump();
    clock.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));

    await _showMode(tester, 'Countdown');
    expect(find.text('Switch to countdown?'), findsNothing);
    expect(find.byKey(ClockPage.hiddenStopwatchKey), findsOneWidget);
    expect(engine.mode, ClockMode.countdown);
    expect(engine.isStopwatchRunning, isTrue);
    expect(engine.stopwatchElapsed, const Duration(seconds: 3));

    await _showMode(tester, 'Stopwatch');
    expect(find.text('00:03.0'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    await _dispose(tester);
  });

  testWidgets('switching modes preserves a paused stopwatch and its laps', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine));
    await tester.tap(find.text('Start'));
    await tester.pump();
    clock.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Lap'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();

    await _showMode(tester, 'Countdown');
    await _showMode(tester, 'Stopwatch');

    // The paused readout and the lap split and total all format to the same
    // text, so name the primary readout here and keep the lap row assertion.
    final readout = tester.widget<Text>(find.byKey(ClockPage.timeKey));
    expect(readout.data, '00:03.0');
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Lap 1'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('confirms before replacing a countdown with a preset', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(minutes: 10));
    engine.start();
    clock.advance(const Duration(minutes: 1));
    engine.pause();
    engine.addPreset(label: 'Short', duration: const Duration(minutes: 5));

    await tester.pumpWidget(_harness(engine));
    expect(find.text('09:00'), findsOneWidget);

    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    expect(find.text('Use Short?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(engine.countdownDuration, const Duration(minutes: 10));
    expect(engine.countdownElapsed, const Duration(minutes: 1));
    expect(find.text('09:00'), findsOneWidget);

    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use preset'));
    await tester.pumpAndSettle();

    expect(engine.countdownDuration, const Duration(minutes: 5));
    expect(engine.countdownElapsed, Duration.zero);
    expect(find.text('of 05:00'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('reports an absolute deadline on start and resume, null on pause', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    final wall = DateTime.utc(2026, 1, 1, 12);
    final deadlines = <DateTime?>[];

    await tester.pumpWidget(
      _harness(engine, deadlines: deadlines, wallClock: () => wall),
    );

    await _showMode(tester, 'Countdown');
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(deadlines.last, wall.add(const Duration(minutes: 25)));

    clock.advance(const Duration(minutes: 1));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(deadlines.last, isNull);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(deadlines.last, wall.add(const Duration(minutes: 24)));

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(deadlines.last, isNull);

    await _dispose(tester);
  });

  testWidgets('does not cancel a deadline that matured in the foreground', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(seconds: 5));
    final wall = DateTime.utc(2026, 1, 1, 12);
    final deadlines = <DateTime?>[];
    var completions = 0;

    await tester.pumpWidget(
      _harness(
        engine,
        deadlines: deadlines,
        wallClock: () => wall,
        onCountdownCompleted: () => completions++,
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(deadlines.single, wall.add(const Duration(seconds: 5)));

    clock.advance(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 100));

    expect(completions, 1);
    expect(engine.isRunning, isFalse);
    expect(deadlines.last, isNotNull);
    expect(deadlines.contains(null), isFalse);
    expect(find.text('Complete'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('Repeat restarts the original duration from the expiry state', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(seconds: 5));
    final wall = DateTime.utc(2026, 1, 1, 12);
    final deadlines = <DateTime?>[];

    await tester.pumpWidget(
      _harness(engine, deadlines: deadlines, wallClock: () => wall),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    clock.advance(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Complete'), findsOneWidget);

    await tester.tap(find.byKey(ClockPage.repeatActionKey));
    await tester.pump();

    expect(engine.isCountdownRunning, isTrue);
    expect(engine.countdownDuration, const Duration(seconds: 5));
    expect(engine.remaining, const Duration(seconds: 5));
    expect(find.text('Complete'), findsNothing);
    expect(find.text('00:05'), findsOneWidget);
    expect(deadlines.last, wall.add(const Duration(seconds: 5)));

    await _dispose(tester);
  });

  testWidgets('a countdown keeps running while the stopwatch is shown', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(seconds: 3));
    final wall = DateTime.utc(2026, 1, 1, 12);
    final deadlines = <DateTime?>[];
    var completions = 0;

    await tester.pumpWidget(
      _harness(
        engine,
        deadlines: deadlines,
        wallClock: () => wall,
        onCountdownCompleted: () => completions++,
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();

    await _showMode(tester, 'Stopwatch');
    expect(find.byKey(ClockPage.hiddenCountdownKey), findsOneWidget);
    expect(engine.isCountdownRunning, isTrue);
    expect(deadlines.last, wall.add(const Duration(seconds: 3)));

    clock.advance(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(completions, 1);
    expect(engine.isCountdownComplete, isTrue);
    expect(deadlines.contains(null), isFalse);

    await _showMode(tester, 'Countdown');
    expect(find.text('Complete'), findsOneWidget);
    await tester.tap(find.byKey(ClockPage.repeatActionKey));
    await tester.pump();
    expect(engine.isCountdownRunning, isTrue);

    await _dispose(tester);
  });

  testWidgets('recoveryNow bridges a restored running countdown', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    var wall = DateTime.utc(2026, 1, 1, 12);
    final original = ClockEngine(
      nowMicroseconds: clock.now,
      processToken: 'previous-process',
      wallClock: () => wall,
    );
    original.setCountdownDuration(const Duration(minutes: 10));
    original.start();
    clock.advance(const Duration(seconds: 30));
    wall = wall.add(const Duration(seconds: 30));
    final snapshot = original.snapshot();

    clock.advance(const Duration(minutes: 2));
    wall = wall.add(const Duration(minutes: 2));
    final deadlines = <DateTime?>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: CompanionTheme.light,
        home: ClockPage(
          initialSnapshot: snapshot,
          recoveryNow: wall,
          wallClock: () => wall,
          onSnapshot: (String value) async {},
          onCountdownDeadlineChanged: (DateTime? value) async =>
              deadlines.add(value),
        ),
      ),
    );

    expect(find.textContaining('07:'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(deadlines, hasLength(1));
    expect(deadlines.single, isNotNull);
    expect(
      deadlines.single!.isAfter(wall.add(const Duration(minutes: 7))),
      isTrue,
    );

    await _dispose(tester);
  });

  testWidgets('snapshot failures are caught and retried on the next change', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    final attempts = <String>[];
    var fail = true;

    await tester.pumpWidget(
      _harness(
        engine,
        onSnapshot: (String value) async {
          attempts.add(value);
          if (fail) {
            throw StateError('disk unavailable');
          }
        },
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(attempts, hasLength(1));
    expect(find.text('Could not save the clock. Try again.'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.pump();

    expect(attempts, hasLength(2));
    expect(attempts.last, contains('"running":false'));
    expect(find.text('Could not save the clock. Try again.'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('resuming re-emits a fresh deadline for a running countdown', (
    tester,
  ) async {
    final clock = FakeMonotonicClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(minutes: 10));
    engine.start();
    clock.advance(const Duration(minutes: 1));
    var wall = DateTime.utc(2026, 1, 1, 12);
    final deadlines = <DateTime?>[];

    await tester.pumpWidget(
      _harness(engine, deadlines: deadlines, wallClock: () => wall),
    );
    expect(deadlines.single, wall.add(const Duration(minutes: 9)));

    // Drive the real lifecycle state machine: `paused` is only reachable
    // through inactive/hidden, and `resumed` only through inactive.
    wall = wall.add(const Duration(hours: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(deadlines, hasLength(2));
    expect(deadlines.last, wall.add(const Duration(minutes: 9)));

    await _dispose(tester);
  });
}
