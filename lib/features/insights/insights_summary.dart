import '../../core/storage/session_record.dart';

/// A local calendar date without a time or time-zone component.
///
/// Dates are advanced with calendar fields rather than 24-hour durations, so a
/// daylight-saving day still covers exactly one date.
class CalendarDay implements Comparable<CalendarDay> {
  const CalendarDay(this.year, this.month, this.day);

  factory CalendarDay.fromLocal(DateTime instant) {
    final local = instant.toLocal();
    return CalendarDay(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// Monday is 1 and Sunday is 7, matching [DateTime.weekday].
  int get weekday => DateTime(year, month, day).weekday;

  /// Local midnight at the start of this date.
  DateTime get start => DateTime(year, month, day);

  CalendarDay addDays(int days) {
    final shifted = DateTime(year, month, day + days);
    return CalendarDay(shifted.year, shifted.month, shifted.day);
  }

  @override
  int compareTo(CalendarDay other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// Real recorded totals for one calendar window.
class SessionTotals {
  const SessionTotals({
    required this.sessions,
    required this.completed,
    required this.focused,
    required this.intended,
  });

  static const empty = SessionTotals(
    sessions: 0,
    completed: 0,
    focused: Duration.zero,
    intended: Duration.zero,
  );

  final int sessions;
  final int completed;
  final Duration focused;
  final Duration intended;

  Duration get averageFocused => sessions == 0
      ? Duration.zero
      : Duration(milliseconds: focused.inMilliseconds ~/ sessions);
}

/// Activity recorded on one local calendar day.
class DayActivity {
  const DayActivity({
    required this.day,
    required this.totals,
    required this.completedFocused,
    required this.uncompletedFocused,
  });

  factory DayActivity.empty(CalendarDay day) => DayActivity(
    day: day,
    totals: SessionTotals.empty,
    completedFocused: Duration.zero,
    uncompletedFocused: Duration.zero,
  );

  final CalendarDay day;
  final SessionTotals totals;
  final Duration completedFocused;
  final Duration uncompletedFocused;
}

/// Session totals for the current day, week and month plus seven-day activity.
class InsightsSummary {
  const InsightsSummary({
    required this.today,
    required this.todayTotals,
    required this.weekTotals,
    required this.monthTotals,
    required this.allTimeTotals,
    required this.lastSevenDaysTotals,
    required this.lastSevenDays,
    required this.history,
  });

  final CalendarDay today;
  final SessionTotals todayTotals;
  final SessionTotals weekTotals;
  final SessionTotals monthTotals;
  final SessionTotals allTimeTotals;
  final SessionTotals lastSevenDaysTotals;

  /// Seven consecutive days ending today, oldest first.
  final List<DayActivity> lastSevenDays;

  /// Every saved session, newest finish first.
  final List<SessionRecord> history;

  bool get isEmpty => allTimeTotals.sessions == 0;

  Duration get averageFocused => allTimeTotals.averageFocused;
}

/// Builds the Insights summary from recorded sessions.
///
/// Sessions belong to the local calendar day on which they finished. Weeks
/// start on Monday and run through today. Months are calendar months through
/// today. [localDay] can be supplied to project instants onto a simulated
/// local calendar in tests; production uses the device's local time zone.
InsightsSummary summarizeSessions(
  List<SessionRecord> sessions, {
  required DateTime now,
  CalendarDay Function(DateTime instant)? localDay,
}) {
  final projectDay = localDay ?? CalendarDay.fromLocal;
  final today = projectDay(now);
  final weekStart = today.addDays(1 - today.weekday);
  final monthStart = CalendarDay(today.year, today.month, 1);
  final chartStart = today.addDays(-6);

  final todayTotals = _TotalsBuilder();
  final weekTotals = _TotalsBuilder();
  final monthTotals = _TotalsBuilder();
  final allTotals = _TotalsBuilder();
  final chartTotals = _TotalsBuilder();
  final chartDays = <CalendarDay, _DayBuilder>{};

  for (final session in sessions) {
    final day = projectDay(session.finishedAt);
    allTotals.add(session);

    if (day == today) {
      todayTotals.add(session);
    }
    if (_within(day, weekStart, today)) {
      weekTotals.add(session);
    }
    if (_within(day, monthStart, today)) {
      monthTotals.add(session);
    }
    if (_within(day, chartStart, today)) {
      chartTotals.add(session);
      chartDays.putIfAbsent(day, _DayBuilder.new).add(session);
    }
  }

  final lastSevenDays = <DayActivity>[];
  for (var offset = 0; offset < 7; offset++) {
    final day = chartStart.addDays(offset);
    final builder = chartDays[day];
    lastSevenDays.add(builder?.build(day) ?? DayActivity.empty(day));
  }

  final history = List<SessionRecord>.of(sessions)
    ..sort((a, b) {
      final byFinish = b.finishedAt.compareTo(a.finishedAt);
      if (byFinish != 0) return byFinish;
      return b.id.compareTo(a.id);
    });

  return InsightsSummary(
    today: today,
    todayTotals: todayTotals.build(),
    weekTotals: weekTotals.build(),
    monthTotals: monthTotals.build(),
    allTimeTotals: allTotals.build(),
    lastSevenDaysTotals: chartTotals.build(),
    lastSevenDays: lastSevenDays,
    history: history,
  );
}

bool _within(CalendarDay day, CalendarDay start, CalendarDay end) =>
    day.compareTo(start) >= 0 && day.compareTo(end) <= 0;

class _TotalsBuilder {
  int _sessions = 0;
  int _completed = 0;
  int _focusedMilliseconds = 0;
  int _intendedMilliseconds = 0;

  void add(SessionRecord session) {
    _sessions += 1;
    if (session.completed) _completed += 1;
    _focusedMilliseconds += session.actual.inMilliseconds;
    _intendedMilliseconds += session.intended.inMilliseconds;
  }

  SessionTotals build() => SessionTotals(
    sessions: _sessions,
    completed: _completed,
    focused: Duration(milliseconds: _focusedMilliseconds),
    intended: Duration(milliseconds: _intendedMilliseconds),
  );
}

class _DayBuilder {
  final _totals = _TotalsBuilder();
  int _completedMilliseconds = 0;
  int _uncompletedMilliseconds = 0;

  void add(SessionRecord session) {
    _totals.add(session);
    if (session.completed) {
      _completedMilliseconds += session.actual.inMilliseconds;
    } else {
      _uncompletedMilliseconds += session.actual.inMilliseconds;
    }
  }

  DayActivity build(CalendarDay day) => DayActivity(
    day: day,
    totals: _totals.build(),
    completedFocused: Duration(milliseconds: _completedMilliseconds),
    uncompletedFocused: Duration(milliseconds: _uncompletedMilliseconds),
  );
}
