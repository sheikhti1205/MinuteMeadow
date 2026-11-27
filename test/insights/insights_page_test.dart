import 'dart:async';

import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/insights/insights_page.dart';
import 'package:companion_focus/features/insights/insights_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 26, 15, 30);

CalendarDay _localDay(DateTime instant) =>
    CalendarDay(instant.year, instant.month, instant.day);

SessionRecord _session({
  required String id,
  required DateTime finishedAt,
  Duration intended = const Duration(minutes: 25),
  Duration? actual,
  bool completed = true,
  String? label,
  String? note,
}) {
  final focused = actual ?? (completed ? intended : Duration.zero);
  return SessionRecord(
    id: id,
    startedAt: finishedAt.subtract(focused),
    finishedAt: finishedAt,
    intended: intended,
    actual: focused,
    completed: completed,
    label: label,
    note: note,
  );
}

List<SessionRecord> _sessions() => [
  _session(
    id: 'today-complete',
    finishedAt: DateTime(2026, 11, 26, 9),
    label: 'Deep work',
    note: 'Kept the phone away.',
  ),
  _session(
    id: 'today-partial',
    finishedAt: DateTime(2026, 11, 26, 11),
    actual: const Duration(minutes: 10),
    completed: false,
  ),
  _session(
    id: 'yesterday-complete',
    finishedAt: DateTime(2026, 11, 25, 20),
    intended: const Duration(minutes: 30),
  ),
];

Widget _host({
  required List<SessionRecord> sessions,
  SessionDetailsUpdater? onUpdateDetails,
  SessionsDeleter? onDeleteSessions,
}) => MaterialApp(
  theme: CompanionTheme.light,
  home: Scaffold(
    body: InsightsPage(
      sessions: sessions,
      onUpdateDetails: onUpdateDetails,
      onDeleteSessions: onDeleteSessions,
      now: () => _now,
      localDay: _localDay,
    ),
  ),
);

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(find.byKey(InsightsPage.historyButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _openDetails(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(InsightsHistoryPage.sessionRowKey(id)));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Scrolls the page until the text is built, then brings it fully on screen.
Future<void> _revealText(WidgetTester tester, String text) async {
  final target = find.text(text);
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pump();
  }
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump();
  }
}

/// Anything that would present the Leaderboard as something to operate.
bool _isActionable(Widget widget) => switch (widget) {
  ButtonStyleButton() => true,
  IconButton() => true,
  FloatingActionButton() => true,
  SwitchListTile() => true,
  CheckboxListTile() => true,
  InkWell(:final onTap) => onTap != null,
  GestureDetector(:final onTap) => onTap != null,
  ListTile(:final onTap) => onTap != null,
  _ => false,
};

void main() {
  testWidgets('empty overview shows no sample statistics', (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: const []));
    await tester.pump();

    expect(find.byKey(InsightsPage.emptyStateKey), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Focused'), findsNothing);
    expect(find.text('50%'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('overview uses recorded totals and period tabs', (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: _sessions()));
    await tester.pump();

    expect(find.text('Focused'), findsOneWidget);
    expect(find.text('35 min'), findsWidgets);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Deep work'), findsOneWidget);
    expect(find.textContaining('Kept the phone away.'), findsOneWidget);

    await tester.tap(find.byKey(InsightsPage.periodKey(InsightsPeriod.week)));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('1h 5m'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('overview shows a Leaderboard section marked Coming soon', (
    tester,
  ) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: _sessions()));
    await tester.pump();
    await _revealText(tester, 'Leaderboard');

    expect(
      find.descendant(
        of: find.byType(InsightsPage),
        matching: find.text('Leaderboard'),
      ),
      findsOneWidget,
    );
    expect(find.text('Coming soon'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('Leaderboard coming soon reads as one accessible statement', (
    tester,
  ) async {
    _useTallPhone(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host(sessions: _sessions()));
      await tester.pump();
      await _revealText(tester, 'Leaderboard');

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Leaderboard[\s\S]*Coming soon|Coming soon[\s\S]*Leaderboard',
          ),
        ),
        findsOneWidget,
      );

      await _dispose(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Leaderboard coming soon is informational, not an action', (
    tester,
  ) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: _sessions()));
    await tester.pump();
    await _revealText(tester, 'Leaderboard');

    final leaderboard = find.text('Leaderboard');
    expect(leaderboard, findsOneWidget);
    expect(
      find.ancestor(
        of: leaderboard,
        matching: find.byWidgetPredicate(_isActionable),
      ),
      findsNothing,
    );

    await tester.tap(leaderboard);
    await tester.pumpAndSettle();

    expect(find.byType(InsightsHistoryPage), findsNothing);
    expect(find.text('Coming soon'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('history filters by outcome and local date', (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: _sessions()));
    await tester.pump();
    await _openHistory(tester);

    expect(find.text('History'), findsOneWidget);
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-partial')),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('yesterday-complete')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(InsightsHistoryPage.outcomeFilterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not completed').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-partial')),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsNothing,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('yesterday-complete')),
      findsNothing,
    );

    await tester.tap(find.byKey(InsightsHistoryPage.outcomeFilterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All outcomes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsightsHistoryPage.dateFilterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-partial')),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('yesterday-complete')),
      findsNothing,
    );

    await _dispose(tester);
  });

  testWidgets('details compare intended with actual and edit only text', (
    tester,
  ) async {
    _useTallPhone(tester);
    String? updatedId;
    SessionDetails? updatedDetails;
    await tester.pumpWidget(
      _host(
        sessions: _sessions(),
        onUpdateDetails: (id, details) async {
          updatedId = id;
          updatedDetails = details;
        },
      ),
    );
    await tester.pump();
    await _openHistory(tester);
    await _openDetails(tester, 'today-complete');

    expect(find.text('Intended'), findsOneWidget);
    expect(find.text('Focused'), findsOneWidget);
    expect(find.text('25 min of 25 min'), findsOneWidget);
    expect(find.text('Deep work'), findsWidgets);
    expect(find.text('Kept the phone away.'), findsWidgets);

    await tester.tap(find.text('Edit label or note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(InsightsHistoryPage.editorLabelKey),
      'Planning',
    );
    await tester.enterText(
      find.byKey(InsightsHistoryPage.editorNoteKey),
      'Outlined the next milestone.',
    );
    await tester.tap(find.byKey(InsightsHistoryPage.editorSaveKey));
    await tester.pumpAndSettle();

    expect(updatedId, 'today-complete');
    expect(updatedDetails?.label, 'Planning');
    expect(updatedDetails?.note, 'Outlined the next milestone.');
    expect(find.text('Planning'), findsOneWidget);
    expect(find.textContaining('25 min · Completed'), findsOneWidget);
    expect(find.text('Session updated.'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('single delete confirms the explicit count and updates rows', (
    tester,
  ) async {
    _useTallPhone(tester);
    Set<String>? deleted;
    await tester.pumpWidget(
      _host(
        sessions: _sessions(),
        onDeleteSessions: (ids) async => deleted = ids,
      ),
    );
    await tester.pump();
    await _openHistory(tester);
    await _openDetails(tester, 'today-complete');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 session?'), findsOneWidget);

    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await tester.pumpAndSettle();

    expect(deleted, {'today-complete'});
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsNothing,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-partial')),
      findsOneWidget,
    );

    await _dispose(tester);
  });

  testWidgets('selected delete confirms the number of sessions', (tester) async {
    _useTallPhone(tester);
    Set<String>? deleted;
    await tester.pumpWidget(
      _host(
        sessions: _sessions(),
        onDeleteSessions: (ids) async => deleted = ids,
      ),
    );
    await tester.pump();
    await _openHistory(tester);

    await tester.tap(find.byKey(InsightsHistoryPage.selectButtonKey));
    await tester.pump();
    await tester.tap(
      find.byKey(InsightsHistoryPage.sessionCheckKey('today-complete')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(InsightsHistoryPage.sessionCheckKey('yesterday-complete')),
    );
    await tester.pump();

    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(InsightsHistoryPage.deleteSelectedKey));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 sessions?'), findsOneWidget);

    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await tester.pumpAndSettle();

    expect(deleted, {'today-complete', 'yesterday-complete'});
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsNothing,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-partial')),
      findsOneWidget,
    );

    await _dispose(tester);
  });

  testWidgets('shows a saving state while a delete is in flight', (
    tester,
  ) async {
    _useTallPhone(tester);
    final gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        sessions: _sessions(),
        onDeleteSessions: (ids) => gate.future,
      ),
    );
    await tester.pump();
    await _openHistory(tester);

    await tester.tap(find.byKey(InsightsHistoryPage.selectButtonKey));
    await tester.pump();
    await tester.tap(
      find.byKey(InsightsHistoryPage.sessionCheckKey('today-complete')),
    );
    await tester.pump();
    await tester.tap(find.byKey(InsightsHistoryPage.deleteSelectedKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    await _dispose(tester);
  });

  testWidgets('failed delete shows an error and keeps the sessions', (
    tester,
  ) async {
    _useTallPhone(tester);
    await tester.pumpWidget(
      _host(
        sessions: _sessions(),
        onDeleteSessions: (ids) async => throw StateError('offline'),
      ),
    );
    await tester.pump();
    await _openHistory(tester);
    await _openDetails(tester, 'today-complete');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsightsHistoryPage.confirmDeleteKey));
    await tester.pumpAndSettle();

    expect(find.byKey(InsightsHistoryPage.errorBannerKey), findsOneWidget);
    expect(
      find.text('Could not update saved sessions. Try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(InsightsHistoryPage.sessionRowKey('today-complete')),
      findsOneWidget,
    );

    await _dispose(tester);
  });

  testWidgets('history is read only without write callbacks', (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(_host(sessions: _sessions()));
    await tester.pump();
    await _openHistory(tester);

    expect(find.byKey(InsightsHistoryPage.selectButtonKey), findsNothing);
    await _openDetails(tester, 'today-complete');
    expect(find.text('Edit label or note'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await _dispose(tester);
  });
}
