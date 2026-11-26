import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/insights/insights_summary.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRecord _session({
  required String id,
  required DateTime finishedAt,
  Duration intended = const Duration(minutes: 25),
  Duration? actual,
  bool completed = true,
}) {
  final focused = actual ?? (completed ? intended : Duration.zero);
  return SessionRecord(
    id: id,
    startedAt: finishedAt.subtract(focused),
    finishedAt: finishedAt,
    intended: intended,
    actual: focused,
    completed: completed,
  );
}

void main() {
  test('empty history has zero totals and seven days ending today', () {
    final summary = summarizeSessions(
      const <SessionRecord>[],
      now: DateTime(2026, 11, 26, 15, 30),
    );

    expect(summary.isEmpty, isTrue);
    expect(summary.today, const CalendarDay(2026, 11, 26));
    expect(summary.todayTotals.sessions, 0);
    expect(summary.weekTotals.focused, Duration.zero);
    expect(summary.monthTotals.sessions, 0);
    expect(summary.allTimeTotals.sessions, 0);
    expect(summary.averageFocused, Duration.zero);
    expect(summary.lastSevenDays, hasLength(7));
    expect(summary.lastSevenDays.first.day, const CalendarDay(2026, 11, 20));
    expect(summary.lastSevenDays.last.day, const CalendarDay(2026, 11, 26));
    expect(
      summary.lastSevenDays.every((day) => day.totals.sessions == 0),
      isTrue,
    );
    expect(summary.lastSevenDaysTotals.sessions, 0);
    expect(summary.history, isEmpty);
  });

  test('splits sessions into today, calendar week and calendar month', () {
    final sessions = <SessionRecord>[
      _session(
        id: 'today-a',
        finishedAt: DateTime(2026, 11, 26, 9),
      ),
      _session(
        id: 'today-b',
        finishedAt: DateTime(2026, 11, 26, 14),
        actual: const Duration(minutes: 10),
        completed: false,
      ),
      _session(
        id: 'week',
        finishedAt: DateTime(2026, 11, 23, 9),
      ),
      _session(
        id: 'previous-week',
        finishedAt: DateTime(2026, 11, 22, 23, 59),
      ),
      _session(
        id: 'previous-month',
        finishedAt: DateTime(2026, 10, 31, 23, 59),
      ),
      _session(
        id: 'tomorrow',
        finishedAt: DateTime(2026, 11, 27, 9),
      ),
    ];
    final summary = summarizeSessions(
      sessions,
      now: DateTime(2026, 11, 26, 15, 30),
    );

    expect(summary.todayTotals.sessions, 2);
    expect(summary.todayTotals.completed, 1);
    expect(summary.todayTotals.focused, const Duration(minutes: 35));

    expect(summary.weekTotals.sessions, 3);
    expect(summary.weekTotals.completed, 2);
    expect(summary.weekTotals.focused, const Duration(minutes: 60));

    expect(summary.monthTotals.sessions, 4);
    expect(summary.monthTotals.completed, 3);
    expect(summary.monthTotals.focused, const Duration(minutes: 85));

    expect(summary.allTimeTotals.sessions, 6);
    expect(summary.allTimeTotals.completed, 5);
    expect(summary.allTimeTotals.focused, const Duration(minutes: 135));
    expect(summary.allTimeTotals.intended, const Duration(minutes: 150));
    expect(
      summary.averageFocused,
      const Duration(minutes: 22, seconds: 30),
    );

    expect(summary.lastSevenDaysTotals.sessions, 4);
    expect(summary.lastSevenDaysTotals.focused, const Duration(minutes: 85));
    expect(summary.lastSevenDays[2].day, const CalendarDay(2026, 11, 22));
    expect(summary.lastSevenDays[2].totals.sessions, 1);
    expect(summary.lastSevenDays[6].totals.sessions, 2);
    expect(
      summary.lastSevenDays[6].completedFocused,
      const Duration(minutes: 25),
    );
    expect(
      summary.lastSevenDays[6].uncompletedFocused,
      const Duration(minutes: 10),
    );

    expect(
      summary.history.map((session) => session.id),
      [
        'tomorrow',
        'today-b',
        'today-a',
        'week',
        'previous-week',
        'previous-month',
      ],
    );
  });

  test('assigns a session to the local day on which it finished', () {
    final summary = summarizeSessions(
      [
        _session(
          id: 'crosses-midnight',
          finishedAt: DateTime(2026, 11, 26, 0, 10),
          intended: const Duration(minutes: 30),
        ),
      ],
      now: DateTime(2026, 11, 26, 1),
    );

    expect(summary.todayTotals.sessions, 1);
    expect(
      summary.history.single.startedAt,
      DateTime(2026, 11, 25, 23, 40),
    );
  });

  test('uses calendar boundaries instead of fixed 24-hour windows', () {
    final sessions = <SessionRecord>[
      _session(
        id: 'sunday-night',
        finishedAt: DateTime(2026, 11, 22, 23, 59, 59),
        intended: const Duration(minutes: 62),
      ),
      _session(
        id: 'monday-morning',
        finishedAt: DateTime(2026, 11, 23),
        intended: const Duration(minutes: 63),
      ),
      _session(
        id: 'yesterday-night',
        finishedAt: DateTime(2026, 11, 25, 23, 59, 59),
        intended: const Duration(minutes: 60),
      ),
      _session(
        id: 'today-midnight',
        finishedAt: DateTime(2026, 11, 26),
        intended: const Duration(minutes: 61),
      ),
      _session(
        id: 'october-night',
        finishedAt: DateTime(2026, 10, 31, 23, 59, 59),
        intended: const Duration(minutes: 64),
      ),
      _session(
        id: 'november-first',
        finishedAt: DateTime(2026, 11, 1),
        intended: const Duration(minutes: 65),
      ),
    ];
    final summary = summarizeSessions(
      sessions,
      now: DateTime(2026, 11, 26, 12),
    );

    expect(summary.todayTotals.sessions, 1);
    expect(summary.todayTotals.focused, const Duration(minutes: 61));
    expect(summary.weekTotals.sessions, 3);
    expect(summary.weekTotals.focused, const Duration(minutes: 184));
    expect(summary.monthTotals.sessions, 5);
    expect(summary.monthTotals.focused, const Duration(minutes: 311));
    expect(summary.allTimeTotals.sessions, 6);
    expect(summary.allTimeTotals.focused, const Duration(minutes: 375));
  });

  test('groups a simulated 23-hour local day by calendar date', () {
    CalendarDay simulatedEasternDay(DateTime instant) {
      final utc = instant.toUtc();
      final offsetHours = utc.isBefore(DateTime.utc(2026, 3, 8, 7)) ? -5 : -4;
      final wall = utc.add(Duration(hours: offsetHours));
      return CalendarDay(wall.year, wall.month, wall.day);
    }

    final sessions = <SessionRecord>[
      _session(
        id: 'week-start',
        finishedAt: DateTime.utc(2026, 3, 3, 12),
        intended: const Duration(minutes: 15),
      ),
      _session(
        id: 'after-gap',
        finishedAt: DateTime.utc(2026, 3, 8, 7, 30),
        intended: const Duration(minutes: 20),
      ),
      _session(
        id: 'before-midnight',
        finishedAt: DateTime.utc(2026, 3, 9, 3, 30),
      ),
      _session(
        id: 'after-midnight',
        finishedAt: DateTime.utc(2026, 3, 9, 5, 30),
        intended: const Duration(minutes: 30),
      ),
    ];
    final summary = summarizeSessions(
      sessions,
      now: DateTime.utc(2026, 3, 9, 16),
      localDay: simulatedEasternDay,
    );

    expect(summary.today, const CalendarDay(2026, 3, 9));
    expect(summary.todayTotals.sessions, 1);
    expect(summary.todayTotals.focused, const Duration(minutes: 30));

    expect(
      summary.lastSevenDays.map((day) => day.day),
      const [
        CalendarDay(2026, 3, 3),
        CalendarDay(2026, 3, 4),
        CalendarDay(2026, 3, 5),
        CalendarDay(2026, 3, 6),
        CalendarDay(2026, 3, 7),
        CalendarDay(2026, 3, 8),
        CalendarDay(2026, 3, 9),
      ],
    );
    final transitionDay = summary.lastSevenDays[5];
    expect(transitionDay.totals.sessions, 2);
    expect(transitionDay.totals.focused, const Duration(minutes: 45));
    expect(
      transitionDay.completedFocused,
      const Duration(minutes: 45),
    );
    expect(transitionDay.uncompletedFocused, Duration.zero);

    expect(summary.weekTotals.sessions, 1);
    expect(summary.monthTotals.sessions, 4);
    expect(summary.lastSevenDaysTotals.sessions, 4);
    expect(
      summary.lastSevenDaysTotals.focused,
      const Duration(minutes: 90),
    );
  });

  test('keeps intended and actual durations in totals', () {
    final summary = summarizeSessions(
      [
        _session(
          id: 'complete',
          finishedAt: DateTime(2026, 11, 26, 9),
          intended: const Duration(minutes: 50),
        ),
        _session(
          id: 'partial',
          finishedAt: DateTime(2026, 11, 26, 11),
          intended: const Duration(minutes: 50),
          actual: const Duration(minutes: 20),
          completed: false,
        ),
      ],
      now: DateTime(2026, 11, 26, 12),
    );

    expect(summary.todayTotals.intended, const Duration(minutes: 100));
    expect(summary.todayTotals.focused, const Duration(minutes: 70));
    expect(summary.todayTotals.completed, 1);
    expect(summary.averageFocused, const Duration(minutes: 35));
  });

  test('history is newest first and breaks ties by descending id', () {
    final finishedAt = DateTime(2026, 11, 26, 10);
    final summary = summarizeSessions(
      [
        _session(id: 'a', finishedAt: finishedAt),
        _session(id: 'c', finishedAt: finishedAt),
        _session(id: 'b', finishedAt: finishedAt),
      ],
      now: finishedAt,
    );

    expect(
      summary.history.map((session) => session.id),
      ['c', 'b', 'a'],
    );
  });

  test('calendar days advance across month and year boundaries', () {
    expect(
      const CalendarDay(2026, 12, 31).addDays(1),
      const CalendarDay(2027, 1, 1),
    );
    expect(
      const CalendarDay(2026, 3, 1).addDays(-1),
      const CalendarDay(2026, 2, 28),
    );
    expect(
      const CalendarDay(2028, 2, 28).addDays(1),
      const CalendarDay(2028, 2, 29),
    );
  });
}
