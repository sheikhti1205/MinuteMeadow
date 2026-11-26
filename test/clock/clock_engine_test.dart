import 'dart:convert';

import 'package:companion_focus/features/clock/clock_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonotonicClock {
  int micros = 0;

  int now() => micros;

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
  }
}

void main() {
  group('stopwatch', () {
    test('measures elapsed time between start and pause', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      expect(engine.elapsed, Duration.zero);

      engine.start();
      clock.advance(const Duration(milliseconds: 1500));
      expect(engine.elapsed, const Duration(milliseconds: 1500));

      engine.pause();
      clock.advance(const Duration(seconds: 10));
      expect(engine.elapsed, const Duration(milliseconds: 1500));

      engine.start();
      clock.advance(const Duration(milliseconds: 500));
      expect(engine.elapsed, const Duration(seconds: 2));
    });

    test('reset clears elapsed time and laps', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.addLap();
      engine.reset();

      expect(engine.elapsed, Duration.zero);
      expect(engine.laps, isEmpty);
      expect(engine.isRunning, isFalse);
    });

    test('records laps with split durations', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.start();
      clock.advance(const Duration(seconds: 1));
      engine.addLap();
      clock.advance(const Duration(seconds: 2));
      engine.addLap();

      expect(engine.laps, hasLength(2));
      expect(engine.laps[0].index, 1);
      expect(engine.laps[0].totalMicros, 1000000);
      expect(engine.laps[0].splitMicros, 1000000);
      expect(engine.laps[1].index, 2);
      expect(engine.laps[1].totalMicros, 3000000);
      expect(engine.laps[1].splitMicros, 2000000);

      engine.pause();
      expect(engine.addLap(), isNull);
    });
  });

  group('countdown', () {
    test('counts down and completes exactly once', () {
      final clock = FakeMonotonicClock();
      var completions = 0;
      final engine = ClockEngine(
        nowMicroseconds: clock.now,
        onCountdownComplete: () => completions++,
      );

      engine.setCountdownDuration(const Duration(seconds: 2));
      engine.start();
      clock.advance(const Duration(milliseconds: 1500));

      expect(engine.remaining, const Duration(milliseconds: 500));
      engine.update();
      expect(completions, 0);
      expect(engine.isRunning, isTrue);

      clock.advance(const Duration(milliseconds: 600));
      engine.update();

      expect(completions, 1);
      expect(engine.completionCount, 1);
      expect(engine.isRunning, isFalse);
      expect(engine.elapsed, const Duration(seconds: 2));
      expect(engine.remaining, Duration.zero);

      engine.update();
      expect(completions, 1);
    });

    test('pauses and resumes with the remaining time intact', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.setCountdownDuration(const Duration(minutes: 1));
      engine.start();
      clock.advance(const Duration(seconds: 20));
      engine.pause();
      clock.advance(const Duration(minutes: 5));

      expect(engine.remaining, const Duration(seconds: 40));

      engine.start();
      clock.advance(const Duration(seconds: 10));
      expect(engine.remaining, const Duration(seconds: 30));
    });

    test('starts again from the full duration after completion', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.setCountdownDuration(const Duration(seconds: 5));
      engine.start();
      clock.advance(const Duration(seconds: 6));
      engine.update();
      expect(engine.isRunning, isFalse);

      engine.start();
      expect(engine.isRunning, isTrue);
      expect(engine.remaining, const Duration(seconds: 5));
    });

    test('repeat restarts the original duration after expiry', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.setCountdownDuration(const Duration(seconds: 5));
      engine.start();
      clock.advance(const Duration(seconds: 6));
      engine.update();

      expect(engine.isCountdownComplete, isTrue);
      expect(engine.repeatCountdown(), isTrue);
      expect(engine.isCountdownRunning, isTrue);
      expect(engine.countdownDuration, const Duration(seconds: 5));
      expect(engine.remaining, const Duration(seconds: 5));

      clock.advance(const Duration(seconds: 1));
      expect(engine.remaining, const Duration(seconds: 4));
    });

    test('repeat refuses to discard remaining time', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.setCountdownDuration(const Duration(seconds: 5));
      engine.start();
      clock.advance(const Duration(seconds: 1));

      expect(engine.repeatCountdown(), isFalse);
      expect(engine.remaining, const Duration(seconds: 4));
    });
  });

  group('mode state', () {
    test('switching modes preserves the stopwatch and its laps', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.start();
      clock.advance(const Duration(seconds: 3));
      engine.addLap();
      engine.pause();

      engine.setMode(ClockMode.countdown);
      expect(engine.elapsed, Duration.zero);
      expect(engine.stopwatchElapsed, const Duration(seconds: 3));
      expect(engine.laps, hasLength(1));

      engine.setMode(ClockMode.stopwatch);
      expect(engine.elapsed, const Duration(seconds: 3));
      expect(engine.hasProgress, isTrue);
      expect(engine.laps, hasLength(1));
    });

    test('switching modes preserves countdown progress', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.setCountdownDuration(const Duration(minutes: 10));
      engine.start();
      clock.advance(const Duration(minutes: 1));
      engine.pause();

      engine.setMode(ClockMode.stopwatch);
      expect(engine.countdownElapsed, const Duration(minutes: 1));
      expect(engine.remaining, const Duration(minutes: 9));

      engine.setMode(ClockMode.countdown);
      expect(engine.elapsed, const Duration(minutes: 1));
      expect(engine.remaining, const Duration(minutes: 9));
    });

    test('a hidden running countdown still completes exactly once', () {
      final clock = FakeMonotonicClock();
      var completions = 0;
      final engine = ClockEngine(
        nowMicroseconds: clock.now,
        onCountdownComplete: () => completions++,
      );

      engine.start();
      clock.advance(const Duration(seconds: 2));
      engine.setMode(ClockMode.countdown);
      engine.setCountdownDuration(const Duration(seconds: 5));
      engine.start();
      clock.advance(const Duration(seconds: 6));

      expect(engine.isStopwatchRunning, isTrue);
      engine.update();

      expect(completions, 1);
      expect(engine.isCountdownRunning, isFalse);
      expect(engine.isCountdownComplete, isTrue);
      expect(engine.stopwatchElapsed, const Duration(seconds: 8));

      engine.setMode(ClockMode.stopwatch);
      expect(engine.elapsed, const Duration(seconds: 8));
      engine.update();
      expect(completions, 1);
    });

    test('reset only clears the visible measurement', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      engine.start();
      clock.advance(const Duration(seconds: 4));
      engine.setMode(ClockMode.countdown);
      engine.setCountdownDuration(const Duration(minutes: 5));
      engine.start();
      clock.advance(const Duration(seconds: 2));
      engine.reset();

      expect(engine.countdownElapsed, Duration.zero);
      expect(engine.countdownHasProgress, isFalse);
      expect(engine.stopwatchElapsed, const Duration(seconds: 6));
      expect(engine.isStopwatchRunning, isTrue);
    });
  });

  group('presets', () {
    test('adds, selects, deletes and restores presets', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final preset = engine.addPreset(
        label: 'Deep work',
        duration: const Duration(minutes: 10),
      );
      expect(engine.presets, hasLength(1));

      engine.selectPreset(preset.id);
      expect(engine.mode, ClockMode.countdown);
      expect(engine.countdownDuration, const Duration(minutes: 10));
      expect(engine.selectedPresetId, preset.id);

      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: engine.snapshot(),
      );
      expect(restored.presets, hasLength(1));
      expect(restored.presets.single.label, 'Deep work');
      expect(restored.selectedPresetId, preset.id);

      restored.deletePreset(preset.id);
      expect(restored.presets, isEmpty);
      expect(restored.selectedPresetId, isNull);
    });

    test('renames and re-times a preset', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final preset = engine.addPreset(
        label: 'Focus',
        duration: const Duration(minutes: 5),
      );
      expect(
        engine.updatePreset(
          id: preset.id,
          label: 'Deep work',
          duration: const Duration(hours: 1, minutes: 30),
        ),
        isTrue,
      );

      expect(engine.presets.single.label, 'Deep work');
      expect(
        engine.presets.single.durationMicros,
        const Duration(hours: 1, minutes: 30).inMicroseconds,
      );
    });

    test('a ready selected preset adopts an edited duration', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final preset = engine.addPreset(
        label: 'Focus',
        duration: const Duration(minutes: 5),
      );
      engine.selectPreset(preset.id);
      engine.updatePreset(
        id: preset.id,
        label: 'Focus',
        duration: const Duration(minutes: 15),
      );

      expect(engine.countdownDuration, const Duration(minutes: 15));
      expect(engine.selectedPresetId, preset.id);
    });

    test('an active selected preset keeps its duration when edited', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final preset = engine.addPreset(
        label: 'Focus',
        duration: const Duration(minutes: 5),
      );
      engine.selectPreset(preset.id);
      engine.start();
      clock.advance(const Duration(minutes: 1));

      engine.updatePreset(
        id: preset.id,
        label: 'Long focus',
        duration: const Duration(minutes: 20),
      );

      expect(engine.countdownDuration, const Duration(minutes: 5));
      expect(engine.countdownElapsed, const Duration(minutes: 1));
      expect(engine.selectedPresetId, isNull);
      expect(engine.presets.single.label, 'Long focus');
    });

    test('deleting a selected preset leaves the countdown running intact', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final preset = engine.addPreset(
        label: 'Focus',
        duration: const Duration(minutes: 5),
      );
      engine.selectPreset(preset.id);
      engine.start();
      clock.advance(const Duration(seconds: 30));

      expect(engine.deletePreset(preset.id), isTrue);
      expect(engine.selectedPresetId, isNull);
      expect(engine.isCountdownRunning, isTrue);
      expect(engine.remaining, const Duration(minutes: 4, seconds: 30));
    });

    test('builds readable default labels for long durations', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(nowMicroseconds: clock.now);

      final hours = engine.addPreset(
        label: '',
        duration: const Duration(hours: 1, minutes: 30),
      );
      expect(hours.label, '1 h 30 min');

      final seconds = engine.addPreset(
        label: '   ',
        duration: const Duration(seconds: 45),
      );
      expect(seconds.label, '45 sec');
    });
  });

  group('snapshot recovery', () {
    test('continues a running timer across an in-process background gap', () {
      final clock = FakeMonotonicClock();
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
      );

      running.start();
      clock.advance(const Duration(seconds: 1));
      final snapshot = running.snapshot();

      clock.advance(const Duration(seconds: 2));
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-a',
      );

      expect(restored.isRunning, isTrue);
      expect(restored.elapsed, const Duration(seconds: 3));

      clock.advance(const Duration(seconds: 1));
      expect(restored.elapsed, const Duration(seconds: 4));
    });

    test('restores a paused timer without adding dead time', () {
      final clock = FakeMonotonicClock();
      final paused = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
      );

      paused.start();
      clock.advance(const Duration(seconds: 4));
      paused.pause();
      final snapshot = paused.snapshot();

      clock.advance(const Duration(hours: 2));
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-a',
      );

      expect(restored.isRunning, isFalse);
      expect(restored.elapsed, const Duration(seconds: 4));
    });

    test('resumes a restarted process without guessing at dead time', () {
      final clock = FakeMonotonicClock();
      var wall = DateTime.utc(2026, 1, 1, 12);
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
        wallClock: () => wall,
      );

      running.start();
      clock.advance(const Duration(seconds: 5));
      wall = wall.add(const Duration(seconds: 5));
      final snapshot = running.snapshot();

      clock.advance(const Duration(hours: 1));
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-b',
      );

      expect(restored.isRunning, isTrue);
      expect(restored.elapsed, const Duration(seconds: 5));

      clock.advance(const Duration(seconds: 1));
      expect(restored.elapsed, const Duration(seconds: 6));
    });

    test('uses recoveryNow to bridge a restarted process', () {
      final clock = FakeMonotonicClock();
      var wall = DateTime.utc(2026, 1, 1, 12);
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
        wallClock: () => wall,
      );

      running.setCountdownDuration(const Duration(minutes: 10));
      running.start();
      clock.advance(const Duration(minutes: 1));
      wall = wall.add(const Duration(minutes: 1));
      final snapshot = running.snapshot();

      clock.advance(const Duration(minutes: 2));
      final recoveryNow = wall.add(const Duration(minutes: 2));
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-b',
        recoveryNow: recoveryNow,
      );

      expect(restored.isRunning, isTrue);
      expect(restored.elapsed, const Duration(minutes: 3));
      expect(restored.remaining, const Duration(minutes: 7));
    });

    test('recoveryNow clamps a countdown that expired while dead', () {
      final clock = FakeMonotonicClock();
      var wall = DateTime.utc(2026, 1, 1, 12);
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
        wallClock: () => wall,
      );

      running.setCountdownDuration(const Duration(minutes: 2));
      running.start();
      clock.advance(const Duration(minutes: 1));
      wall = wall.add(const Duration(minutes: 1));
      final snapshot = running.snapshot();

      clock.advance(const Duration(minutes: 5));
      var completions = 0;
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-b',
        recoveryNow: wall.add(const Duration(minutes: 2)),
        onCountdownComplete: () => completions++,
      );

      expect(restored.isRunning, isFalse);
      expect(restored.isComplete, isTrue);
      expect(restored.elapsed, const Duration(minutes: 2));
      expect(completions, 0);
    });

    test('restores countdown completion without firing another callback', () {
      final clock = FakeMonotonicClock();
      var completions = 0;
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
      );

      running.setCountdownDuration(const Duration(seconds: 10));
      running.start();
      clock.advance(const Duration(seconds: 4));
      final snapshot = running.snapshot();

      clock.advance(const Duration(seconds: 20));
      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-a',
        onCountdownComplete: () => completions++,
      );

      expect(restored.isRunning, isFalse);
      expect(restored.isComplete, isTrue);
      expect(restored.elapsed, const Duration(seconds: 10));
      expect(completions, 0);
      restored.update();
      expect(completions, 0);
    });

    test('restores saved laps with their own indices and splits', () {
      final clock = FakeMonotonicClock();
      final running = ClockEngine(nowMicroseconds: clock.now);

      running.start();
      clock.advance(const Duration(seconds: 1));
      running.addLap();
      clock.advance(const Duration(seconds: 2));
      running.addLap();
      final snapshot = running.snapshot();

      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
      );

      expect(restored.laps, hasLength(2));
      expect(restored.laps[0].index, 1);
      expect(restored.laps[0].splitMicros, 1000000);
      expect(restored.laps[1].index, 2);
      expect(restored.laps[1].totalMicros, 3000000);
      expect(restored.laps[1].splitMicros, 2000000);
    });

    test('a version 2 snapshot keeps both modes', () {
      final clock = FakeMonotonicClock();
      final running = ClockEngine(
        nowMicroseconds: clock.now,
        processToken: 'session-a',
      );

      running.start();
      clock.advance(const Duration(seconds: 2));
      running.addLap();
      running.setMode(ClockMode.countdown);
      running.setCountdownDuration(const Duration(minutes: 1));
      running.start();
      clock.advance(const Duration(seconds: 3));
      final snapshot = running.snapshot();

      final restored = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: snapshot,
        processToken: 'session-a',
      );

      expect(restored.mode, ClockMode.countdown);
      expect(restored.stopwatchElapsed, const Duration(seconds: 5));
      expect(restored.isStopwatchRunning, isTrue);
      expect(restored.laps, hasLength(1));
      expect(restored.countdownElapsed, const Duration(seconds: 3));
      expect(restored.isCountdownRunning, isTrue);
    });

    test('a version 1 countdown snapshot still restores', () {
      final clock = FakeMonotonicClock();
      final legacy = jsonEncode(<String, Object?>{
        'version': 1,
        'mode': 'countdown',
        'running': false,
        'accumulatedMicros': 120000000,
        'savedAtMicros': 0,
        'savedAtUtcMicros': 0,
        'process': 'legacy',
        'countdownMicros': 600000000,
        'selectedPresetId': null,
        'laps': <Object?>[],
        'presets': <Object?>[],
      });

      final engine = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: legacy,
      );

      expect(engine.mode, ClockMode.countdown);
      expect(engine.countdownDuration, const Duration(minutes: 10));
      expect(engine.remaining, const Duration(minutes: 8));
      expect(engine.isCountdownRunning, isFalse);
      expect(engine.stopwatchElapsed, Duration.zero);
    });

    test('a version 1 stopwatch snapshot still restores', () {
      final clock = FakeMonotonicClock();
      final legacy = jsonEncode(<String, Object?>{
        'version': 1,
        'mode': 'stopwatch',
        'running': false,
        'accumulatedMicros': 5000000,
        'savedAtMicros': 0,
        'savedAtUtcMicros': 0,
        'process': 'legacy',
        'countdownMicros': 1500000000,
        'laps': <Object?>[
          <String, Object?>{
            'index': 1,
            'totalMicros': 5000000,
            'splitMicros': 5000000,
          },
        ],
        'presets': <Object?>[],
      });

      final engine = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: legacy,
      );

      expect(engine.mode, ClockMode.stopwatch);
      expect(engine.elapsed, const Duration(seconds: 5));
      expect(engine.laps, hasLength(1));
      expect(engine.countdownElapsed, Duration.zero);
    });

    test('ignores malformed snapshots', () {
      final clock = FakeMonotonicClock();
      final engine = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: '{"mode":"stopwatch","accumulatedMicros":',
      );

      expect(engine.mode, ClockMode.stopwatch);
      expect(engine.elapsed, Duration.zero);
      expect(engine.presets, isEmpty);

      final empty = ClockEngine(
        nowMicroseconds: clock.now,
        initialSnapshot: '{"mode":"unknown"}',
      );
      expect(empty.mode, ClockMode.stopwatch);
    });
  });
}
