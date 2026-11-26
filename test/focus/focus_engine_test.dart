import 'package:companion_focus/features/focus/focus_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock implements FocusClock {
  _FakeClock({DateTime? wall})
    : _wall = wall ?? DateTime.utc(2026, 11, 26, 9);

  DateTime _wall;
  Duration _monotonic = Duration.zero;

  @override
  DateTime nowUtc() => _wall;

  @override
  Duration monotonic() => _monotonic;

  void advance(Duration duration) {
    _monotonic += duration;
    _wall = _wall.add(duration);
  }

  void jumpWall(Duration duration) {
    _wall = _wall.add(duration);
  }
}

const _settings = FocusSettings();

FocusEngine _engine(_FakeClock clock) => FocusEngine(
  settings: _settings,
  clock: clock,
  createId: () => 'session-${clock.nowUtc().microsecondsSinceEpoch}',
);

void main() {
  group('FocusEngine', () {
    test('starts idle and prepares to ready', () {
      final engine = _engine(_FakeClock());

      expect(engine.status, FocusStatus.idle);
      expect(engine.remaining, const Duration(minutes: 25));

      engine.prepare();

      expect(engine.status, FocusStatus.ready);
      expect(engine.statusLabel, 'Ready to focus');
      expect(engine.remaining, const Duration(minutes: 25));
    });

    test('starts, pauses and resumes without counting paused time', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      expect(engine.status, FocusStatus.running);
      expect(engine.intended, const Duration(minutes: 25));

      clock.advance(const Duration(minutes: 5));
      expect(engine.remaining, const Duration(minutes: 20));

      engine.pause();
      expect(engine.status, FocusStatus.paused);
      expect(engine.remaining, const Duration(minutes: 20));

      clock.advance(const Duration(minutes: 10));
      expect(engine.remaining, const Duration(minutes: 20));

      engine.resume();
      clock.advance(const Duration(minutes: 3));
      expect(engine.remaining, const Duration(minutes: 17));
    });

    test('a wall-clock jump does not move the running timer', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 5));
      clock.jumpWall(const Duration(hours: 2));

      expect(engine.remaining, const Duration(minutes: 20));
    });

    test('snapshots re-derive the anchor from monotonic elapsed', () {
      final clock = _FakeClock();
      final startedAt = clock.nowUtc();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 5));
      clock.jumpWall(const Duration(hours: -1));

      final snapshot = engine.snapshot();
      expect(snapshot.startedAt, startedAt);
      expect(
        snapshot.anchor,
        clock.nowUtc().subtract(const Duration(minutes: 5)),
      );
      expect(
        FocusSnapshot.tryDecode(snapshot.encode())?.anchor,
        snapshot.anchor,
      );
    });

    test('pause at zero completes instead of pausing at zero', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 25));
      final outcome = engine.pause();

      expect(outcome, isNotNull);
      expect(outcome!.completed, isTrue);
      expect(engine.status, FocusStatus.completed);
      expect(engine.tick(), isNull);
    });

    test('finishedAt never precedes startedAt after a rollback', () {
      final clock = _FakeClock();
      final startedAt = clock.nowUtc();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 10));
      engine.pause();
      clock.jumpWall(const Duration(hours: -2));
      engine.resume();
      clock.advance(const Duration(minutes: 15));

      final outcome = engine.tick();
      expect(outcome, isNotNull);
      expect(outcome!.startedAt, startedAt);
      expect(outcome.finishedAt, startedAt);
      expect(outcome.finishedAt.isBefore(outcome.startedAt), isFalse);
    });

    test('a cancelled session also clamps finishedAt to startedAt', () {
      final clock = _FakeClock();
      final startedAt = clock.nowUtc();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.jumpWall(const Duration(hours: -3));
      final outcome = engine.cancel();

      expect(outcome.startedAt, startedAt);
      expect(outcome.finishedAt, startedAt);
      expect(outcome.finishedAt.isBefore(outcome.startedAt), isFalse);
    });

    test('completes once and records intended and actual time', () {
      final clock = _FakeClock();
      final startedAt = clock.nowUtc();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 25));

      final outcome = engine.tick();
      expect(outcome, isNotNull);
      expect(outcome!.completed, isTrue);
      expect(outcome.startedAt, startedAt);
      expect(outcome.finishedAt, startedAt.add(const Duration(minutes: 25)));
      expect(outcome.intended, const Duration(minutes: 25));
      expect(outcome.actual, const Duration(minutes: 25));

      expect(engine.status, FocusStatus.completed);
      expect(engine.statusLabel, 'Focus complete');
      expect(engine.remaining, Duration.zero);
      expect(engine.completedFocusSessions, 1);
      expect(engine.tick(), isNull);
    });

    test('completion after a pause uses the resumed deadline', () {
      final clock = _FakeClock();
      final startedAt = clock.nowUtc();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 10));
      engine.pause();
      clock.advance(const Duration(minutes: 20));
      engine.resume();
      clock.advance(const Duration(minutes: 15));

      final outcome = engine.tick();
      expect(outcome, isNotNull);
      expect(outcome!.actual, const Duration(minutes: 25));
      expect(
        outcome.finishedAt,
        startedAt.add(const Duration(minutes: 45)),
      );
    });

    test('cancel returns an incomplete outcome and stops the timer', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      clock.advance(const Duration(minutes: 10));
      engine.pause();
      clock.advance(const Duration(minutes: 5));

      final outcome = engine.cancel();
      expect(outcome.completed, isFalse);
      expect(outcome.actual, const Duration(minutes: 10));
      expect(outcome.finishedAt, clock.nowUtc());
      expect(engine.status, FocusStatus.cancelled);
      expect(engine.statusLabel, 'Session cancelled');
      expect(engine.tick(), isNull);
    });

    test('four completed focus sessions produce a long break', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      for (var index = 0; index < 4; index++) {
        clock.advance(const Duration(minutes: 25));
        engine.tick();

        final expected = index == 3
            ? FocusPhase.longBreak
            : FocusPhase.shortBreak;
        expect(engine.nextBreakPhase, expected);

        engine.startBreak();
        expect(engine.phase, expected);
        clock.advance(
          expected == FocusPhase.longBreak
              ? const Duration(minutes: 15)
              : const Duration(minutes: 5),
        );
        expect(engine.tick(), isNotNull);

        if (index < 3) {
          engine.startFocus();
        }
      }

      expect(engine.completedFocusSessions, 4);
    });

    test('settings presets apply to future sessions only', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();

      engine.updateSettings(
        const FocusSettings(
          focusMinutes: 50,
          shortBreakMinutes: 10,
          longBreakMinutes: 20,
        ),
      );
      expect(engine.intended, const Duration(minutes: 25));

      clock.advance(const Duration(minutes: 25));
      engine.tick();
      engine.startBreak();
      expect(engine.intended, const Duration(minutes: 10));
    });

    test('settings update a ready timer', () {
      final engine = _engine(_FakeClock())..prepare();

      engine.updateSettings(const FocusSettings(focusMinutes: 40));

      expect(engine.remaining, const Duration(minutes: 40));
      expect(engine.intended, const Duration(minutes: 40));
    });

    test('rejects invalid transitions', () {
      final engine = _engine(_FakeClock());

      expect(() => engine.pause(), throwsStateError);
      expect(() => engine.resume(), throwsStateError);
      expect(() => engine.cancel(), throwsStateError);
      expect(() => engine.startBreak(), throwsStateError);
      expect(() => engine.skipBreak(), throwsStateError);

      engine.prepare();
      engine.startFocus();
      expect(() => engine.startFocus(), throwsStateError);
      expect(() => engine.startBreak(), throwsStateError);
    });
  });

  group('FocusSnapshot', () {
    test('round trips a running session', () {
      final clock = _FakeClock();
      final engine = _engine(clock)..prepare()..startFocus();
      clock.advance(const Duration(minutes: 4));

      final decoded = FocusSnapshot.tryDecode(engine.encodeSnapshot());

      expect(decoded, isNotNull);
      expect(decoded!.id, engine.id);
      expect(decoded.phase, FocusPhase.focus);
      expect(decoded.status, FocusStatus.running);
      expect(decoded.intended, const Duration(minutes: 25));
      expect(decoded.completedFocusSessions, 0);
    });

    test('restores a running session from its wall-clock anchor', () {
      final start = DateTime.utc(2026, 11, 26, 9);
      final snapshot = FocusSnapshot(
        id: 'restored',
        phase: FocusPhase.focus,
        status: FocusStatus.running,
        startedAt: start,
        anchor: start,
        intended: const Duration(minutes: 25),
        remaining: null,
        finishedAt: null,
        completedFocusSessions: 0,
      ).encode();

      final clock = _FakeClock(wall: start.add(const Duration(minutes: 7)));
      final engine = FocusEngine(
        settings: _settings,
        clock: clock,
        restored: FocusSnapshot.tryDecode(snapshot),
      );

      expect(engine.status, FocusStatus.running);
      expect(engine.remaining, const Duration(minutes: 18));

      clock.advance(const Duration(minutes: 18));
      final outcome = engine.tick();
      expect(outcome, isNotNull);
      expect(outcome!.startedAt, start);
      expect(outcome.finishedAt, start.add(const Duration(minutes: 25)));
    });

    test('restores an overdue session and completes it once', () {
      final start = DateTime.utc(2026, 11, 26, 9);
      final snapshot = FocusSnapshot(
        id: 'overdue',
        phase: FocusPhase.focus,
        status: FocusStatus.running,
        startedAt: start,
        anchor: start,
        intended: const Duration(minutes: 25),
        remaining: null,
        finishedAt: null,
        completedFocusSessions: 2,
      ).encode();

      final clock = _FakeClock(wall: start.add(const Duration(hours: 1)));
      final engine = FocusEngine(
        settings: _settings,
        clock: clock,
        restored: FocusSnapshot.tryDecode(snapshot),
      );

      expect(engine.remaining, Duration.zero);

      final outcome = engine.tick();
      expect(outcome, isNotNull);
      expect(outcome!.completed, isTrue);
      expect(outcome.finishedAt, start.add(const Duration(minutes: 25)));
      expect(engine.completedFocusSessions, 3);
      expect(engine.tick(), isNull);
    });

    test('restores a paused session without counting paused time', () {
      final start = DateTime.utc(2026, 11, 26, 9);
      final snapshot = FocusSnapshot(
        id: 'paused',
        phase: FocusPhase.focus,
        status: FocusStatus.paused,
        startedAt: start,
        anchor: start.add(const Duration(minutes: 8)),
        intended: const Duration(minutes: 25),
        remaining: const Duration(minutes: 12),
        finishedAt: null,
        completedFocusSessions: 0,
      ).encode();

      final clock = _FakeClock(wall: start.add(const Duration(hours: 2)));
      final engine = FocusEngine(
        settings: _settings,
        clock: clock,
        restored: FocusSnapshot.tryDecode(snapshot),
      );

      expect(engine.status, FocusStatus.paused);
      expect(engine.remaining, const Duration(minutes: 12));

      engine.resume();
      clock.advance(const Duration(minutes: 12));
      expect(engine.tick(), isNotNull);
    });

    test('restored completion does not emit a second outcome', () {
      final start = DateTime.utc(2026, 11, 26, 9);
      final snapshot = FocusSnapshot(
        id: 'done',
        phase: FocusPhase.focus,
        status: FocusStatus.completed,
        startedAt: start,
        anchor: start,
        intended: const Duration(minutes: 25),
        remaining: null,
        finishedAt: start.add(const Duration(minutes: 25)),
        completedFocusSessions: 1,
      ).encode();

      final engine = FocusEngine(
        settings: _settings,
        clock: _FakeClock(wall: start.add(const Duration(hours: 3))),
        restored: FocusSnapshot.tryDecode(snapshot),
      );

      expect(engine.status, FocusStatus.completed);
      expect(engine.completedFocusSessions, 1);
      expect(engine.lastOutcome?.id, 'done');
      expect(engine.tick(), isNull);
    });

    test('rejects malformed snapshots', () {
      expect(FocusSnapshot.tryDecode(null), isNull);
      expect(FocusSnapshot.tryDecode(''), isNull);
      expect(FocusSnapshot.tryDecode('not json'), isNull);
      expect(FocusSnapshot.tryDecode('{"version":99}'), isNull);
      expect(
        FocusSnapshot.tryDecode(
          '{"version":1,"id":"","phase":"focus","status":"running",'
          '"startedAt":1,"anchor":1,"intendedMs":1500000,'
          '"completedFocusSessions":0}',
        ),
        isNull,
      );
      expect(
        FocusSnapshot.tryDecode(
          '{"version":1,"id":"x","phase":"focus","status":"paused",'
          '"startedAt":1,"anchor":1,"intendedMs":1500000,'
          '"remainingMs":1600000,"completedFocusSessions":0}',
        ),
        isNull,
      );
    });
  });
}
