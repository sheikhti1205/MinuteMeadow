import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/design/watch_timer_dial.dart';
import 'package:companion_focus/features/clock/clock_engine.dart';
import 'package:companion_focus/features/clock/clock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock {
  int micros = 0;

  int now() => micros;

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
  }
}

Widget _harness(ClockEngine engine, {required bool watchDial}) {
  return MaterialApp(
    theme: CompanionTheme.light,
    home: ClockPage(
      initialSnapshot: null,
      engine: engine,
      watchDial: watchDial,
      onSnapshot: (String value) async {},
    ),
  );
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

WatchTimerDial _dial(WidgetTester tester) =>
    tester.widget<WatchTimerDial>(find.byKey(ClockPage.watchDialKey));

void main() {
  testWidgets('the digital default keeps the existing readout and no dial', (
    tester,
  ) async {
    final clock = _FakeClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine, watchDial: false));

    expect(find.byType(WatchTimerDial), findsNothing);
    expect(find.byKey(ClockPage.watchDialKey), findsNothing);

    final readout = tester.widget<Text>(find.byKey(ClockPage.timeKey));
    expect(readout.data, '00:00.0');
    expect(readout.style?.fontSize, 64);
    expect(
      find.ancestor(
        of: find.byKey(ClockPage.timeKey),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Lap'));
    await tester.pump();

    expect(tester.widget<Text>(find.byKey(ClockPage.timeKey)).style?.fontSize, 44);
    expect(find.byType(WatchTimerDial), findsNothing);
    expect(find.text('Lap 1'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('opting into the dial keeps the exact readout and its controls', (
    tester,
  ) async {
    final clock = _FakeClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine, watchDial: true));

    expect(find.byKey(ClockPage.watchDialKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ClockPage.watchDialKey),
        matching: find.byKey(ClockPage.timeKey),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(ClockPage.timeKey)).style?.fontSize, 64);

    await tester.ensureVisible(find.byKey(ClockPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(ClockPage.primaryActionKey));
    await tester.pump();

    expect(engine.isRunning, isTrue);
    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(find.byKey(ClockPage.timeKey)).data, '00:02.0');

    await tester.ensureVisible(find.byKey(ClockPage.lapActionKey));
    await tester.pump();
    await tester.tap(find.byKey(ClockPage.lapActionKey));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Lap 1'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.byKey(ClockPage.watchDialKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ClockPage.watchDialKey),
        matching: find.byKey(ClockPage.timeKey),
      ),
      findsOneWidget,
    );

    await _dispose(tester);
  });

  testWidgets('stopwatch progress repeats each minute', (tester) async {
    final clock = _FakeClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);

    await tester.pumpWidget(_harness(engine, watchDial: true));
    expect(_dial(tester).progress, 0);

    await tester.tap(find.byKey(ClockPage.primaryActionKey));
    await tester.pump();
    clock.advance(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_dial(tester).progress, closeTo(0.25, 1e-9));

    clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.elapsed, const Duration(minutes: 1, seconds: 15));
    expect(_dial(tester).progress, closeTo(0.25, 1e-9));

    await _dispose(tester);
  });

  testWidgets('countdown progress follows consumed time and stays Repeat-able', (
    tester,
  ) async {
    final clock = _FakeClock();
    final engine = ClockEngine(nowMicroseconds: clock.now);
    engine.setCountdownDuration(const Duration(minutes: 10));

    await tester.pumpWidget(_harness(engine, watchDial: true));
    expect(_dial(tester).progress, 0);
    expect(find.byKey(ClockPage.setDurationKey), findsOneWidget);
    expect(find.byKey(ClockPage.repeatActionKey), findsOneWidget);

    await tester.ensureVisible(find.byKey(ClockPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(ClockPage.primaryActionKey));
    await tester.pump();
    clock.advance(const Duration(minutes: 2, seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_dial(tester).progress, closeTo(0.25, 1e-9));
    expect(tester.widget<Text>(find.byKey(ClockPage.timeKey)).data, '07:30');

    clock.advance(const Duration(minutes: 8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.isCountdownComplete, isTrue);
    expect(_dial(tester).progress, 1);
    expect(find.text('Complete'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ClockPage.repeatActionKey));
    await tester.pump();
    await tester.tap(find.byKey(ClockPage.repeatActionKey));
    await tester.pump();

    expect(engine.isCountdownRunning, isTrue);
    expect(_dial(tester).progress, 0);

    await _dispose(tester);
  });

  test('progress clamps to one revolution and never yields NaN', () {
    expect(WatchTimerDial.clampProgress(-0.5), 0);
    expect(WatchTimerDial.clampProgress(0), 0);
    expect(WatchTimerDial.clampProgress(0.4), 0.4);
    expect(WatchTimerDial.clampProgress(1), 1);
    expect(WatchTimerDial.clampProgress(1.4), 1);
    expect(WatchTimerDial.clampProgress(double.infinity), 1);
    expect(WatchTimerDial.clampProgress(double.negativeInfinity), 0);
    expect(WatchTimerDial.clampProgress(double.nan), 0);
  });

  testWidgets('the dial fits compact widths and large text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.5),
          ),
          child: Center(
            child: SizedBox(
              width: 180,
              child: WatchTimerDial(
                progress: 0.5,
                child: Text('1:02:03.4'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1:02:03.4'), findsOneWidget);
    final size = tester.getSize(find.byType(WatchTimerDial));
    expect(size.width, 180);
    expect(size.height, 180);
  });

  testWidgets('a wide short slot paints a centered square face', (tester) async {
    const slotKey = Key('wide-slot');

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            key: slotKey,
            width: 320,
            height: 80,
            child: WatchTimerDial(
              progress: 0.5,
              child: Text('00:00.0'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dial = find.byType(WatchTimerDial);
    final face = find.descendant(
      of: dial,
      matching: find.byType(CustomPaint),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('00:00.0'), findsOneWidget);
    expect(tester.getSize(dial), const Size(320, 80));
    expect(tester.getSize(face), const Size(80, 80));
    expect(
      tester.getRect(face).center,
      tester.getCenter(find.byKey(slotKey)),
    );
  });
}
