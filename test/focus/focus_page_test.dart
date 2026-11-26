import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required ValueNotifier<FocusSettings> settings,
  required Future<void> Function(FocusOutcome outcome, String snapshot) onOutcome,
  required Future<void> Function(String snapshot) onSnapshot,
  String? snapshot,
  DateTime? recoveryNow,
  void Function(DateTime? deadline, String phaseLabel)? onTimelineChanged,
}) => MaterialApp(
  theme: CompanionTheme.light,
  home: Scaffold(
    body: FocusPage(
      settings: settings,
      onOutcome: onOutcome,
      initialSnapshot: snapshot,
      onSnapshot: onSnapshot,
      onTimelineChanged: onTimelineChanged,
      recoveryNow: recoveryNow,
    ),
  ),
);

String _completedSnapshot({int count = 1}) {
  final finished = DateTime.now().toUtc();
  final start = finished.subtract(const Duration(minutes: 25));
  return FocusSnapshot(
    id: 'completed-$count',
    phase: FocusPhase.focus,
    status: FocusStatus.completed,
    startedAt: start,
    anchor: start,
    intended: const Duration(minutes: 25),
    remaining: null,
    finishedAt: finished,
    completedFocusSessions: count,
  ).encode();
}

String _runningSnapshot({Duration ago = Duration.zero, int count = 0}) {
  final now = DateTime.now().toUtc();
  final start = now.subtract(ago);
  return FocusSnapshot(
    id: 'running',
    phase: FocusPhase.focus,
    status: FocusStatus.running,
    startedAt: start,
    anchor: start,
    intended: const Duration(minutes: 25),
    remaining: null,
    finishedAt: null,
    completedFocusSessions: count,
  ).encode();
}

void main() {
  testWidgets('shows the ready state with one primary action', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Ready to focus'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byKey(FocusPage.primaryActionKey), findsOneWidget);
    expect(find.text('0 of 4 focus sessions'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starts focus and persists a running snapshot', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Start focus'));
    await tester.pump();

    expect(find.text('Focusing'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(snapshots, hasLength(1));
    final decoded = FocusSnapshot.tryDecode(snapshots.single);
    expect(decoded?.status, FocusStatus.running);
    expect(decoded?.phase, FocusPhase.focus);
    expect(decoded?.intended, const Duration(minutes: 25));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pauses and resumes the same session', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start focus'));
    await tester.pump();

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(FocusSnapshot.tryDecode(snapshots.last)?.status, FocusStatus.paused);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.text('Focusing'), findsOneWidget);
    expect(
      FocusSnapshot.tryDecode(snapshots.last)?.status,
      FocusStatus.running,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirms cancellation and finalizes exactly once', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {
          outcomes.add((outcome, snapshot));
        },
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(snapshots, hasLength(1));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Cancel this focus session?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(outcomes, isEmpty);
    expect(find.text('Focusing'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isFalse);
    final terminal = FocusSnapshot.tryDecode(outcomes.single.$2);
    expect(terminal?.status, FocusStatus.cancelled);
    expect(terminal?.id, isNotEmpty);
    expect(snapshots, hasLength(1));
    expect(
      snapshots.where(
        (snapshot) =>
            FocusSnapshot.tryDecode(snapshot)?.status == FocusStatus.cancelled,
      ),
      isEmpty,
    );
    expect(find.text('Session cancelled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starts the suggested short break after a focus', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async {
          outcomes.add((outcome, snapshot));
        },
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('Start short break'), findsOneWidget);
    expect(find.text('Skip break'), findsOneWidget);
    expect(find.byKey(FocusPage.primaryActionKey), findsOneWidget);
    expect(outcomes, isEmpty);

    await tester.tap(find.text('Start short break'));
    await tester.pump();

    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    final decoded = FocusSnapshot.tryDecode(snapshots.last);
    expect(decoded?.phase, FocusPhase.shortBreak);
    expect(decoded?.status, FocusStatus.running);
    expect(decoded?.intended, const Duration(minutes: 5));
    expect(outcomes, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offers a long break after the fourth focus', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(count: 4),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    expect(find.text('Start long break'), findsOneWidget);

    await tester.tap(find.text('Start long break'));
    await tester.pump();
    final decoded = FocusSnapshot.tryDecode(snapshots.last);
    expect(decoded?.phase, FocusPhase.longBreak);
    expect(decoded?.intended, const Duration(minutes: 15));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('skipping a break returns to ready and persists', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async {
          outcomes.add((outcome, snapshot));
        },
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Skip break'));
    await tester.pump();

    expect(find.text('Ready to focus'), findsOneWidget);
    expect(FocusSnapshot.tryDecode(snapshots.last)?.status, FocusStatus.ready);
    expect(outcomes, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('finalizes an overdue restored session once', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _runningSnapshot(ago: const Duration(minutes: 30)),
        onOutcome: (outcome, snapshot) async {
          outcomes.add((outcome, snapshot));
        },
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isTrue);
    expect(
      FocusSnapshot.tryDecode(outcomes.single.$2)?.status,
      FocusStatus.completed,
    );
    expect(snapshots, isEmpty);
    expect(find.text('Focus complete'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(outcomes, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uses recoveryNow only for the initial snapshot', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    final now = DateTime.now().toUtc();
    final anchor = now.subtract(const Duration(hours: 1));
    final snapshot = FocusSnapshot(
      id: 'recovered',
      phase: FocusPhase.focus,
      status: FocusStatus.running,
      startedAt: anchor,
      anchor: anchor,
      intended: const Duration(minutes: 25),
      remaining: null,
      finishedAt: null,
      completedFocusSessions: 0,
    ).encode();

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: snapshot,
        recoveryNow: anchor.add(const Duration(minutes: 10)),
        onOutcome: (outcome, terminal) async {
          outcomes.add((outcome, terminal));
        },
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Focusing'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(outcomes, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reports deadline and phase changes for scheduling', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final events = <(DateTime?, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
        onTimelineChanged: (deadline, label) => events.add((deadline, label)),
      ),
    );
    await tester.pump();

    expect(events.last, (null, 'Focus'));

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(events.last.$1, isNotNull);
    expect(events.last.$2, 'Focus');

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(events.last, (null, 'Focus'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('updates a ready timer when settings change', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    settings.value = const FocusSettings(focusMinutes: 40);
    await tester.pump();

    expect(find.text('40:00'), findsOneWidget);
    final decoded = FocusSnapshot.tryDecode(snapshots.last);
    expect(decoded?.intended, const Duration(minutes: 40));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: CompanionTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: FocusPage(
            settings: settings,
            onOutcome: (outcome, snapshot) async {},
            initialSnapshot: null,
            onSnapshot: (snapshot) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(FocusPage.primaryActionKey), findsOneWidget);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
