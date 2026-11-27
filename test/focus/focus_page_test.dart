import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:companion_focus/features/focus/focus_stage.dart';
import 'package:companion_focus/features/focus/slide_to_quit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required ValueNotifier<FocusSettings> settings,
  required Future<void> Function(FocusOutcome outcome, String snapshot) onOutcome,
  required Future<void> Function(String snapshot) onSnapshot,
  String? snapshot,
  DateTime? recoveryNow,
  FocusClock? clock,
  void Function(DateTime? deadline, String phaseLabel)? onTimelineChanged,
  ValueChanged<bool>? onImmersiveChanged,
  WidgetBuilder? companionStageBuilder,
  VoidCallback? onConfigureTimers,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? CompanionTheme.light,
  home: Scaffold(
    body: FocusPage(
      settings: settings,
      onOutcome: onOutcome,
      initialSnapshot: snapshot,
      onSnapshot: onSnapshot,
      onTimelineChanged: onTimelineChanged,
      recoveryNow: recoveryNow,
      clock: clock,
      onImmersiveChanged: onImmersiveChanged,
      companionStageBuilder: companionStageBuilder,
      onConfigureTimers: onConfigureTimers,
    ),
  ),
);

class _PageClock implements FocusClock {
  DateTime _wall = DateTime.utc(2026, 11, 27, 9);
  Duration _monotonic = Duration.zero;

  @override
  DateTime nowUtc() => _wall;

  @override
  Duration monotonic() => _monotonic;

  void advance(Duration duration) {
    _wall = _wall.add(duration);
    _monotonic += duration;
  }
}

Widget _largeTextHost({
  required ValueNotifier<FocusSettings> settings,
  required Future<void> Function(FocusOutcome outcome, String snapshot) onOutcome,
  required Future<void> Function(String snapshot) onSnapshot,
  ValueChanged<bool>? onImmersiveChanged,
}) => MaterialApp(
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
      onOutcome: onOutcome,
      initialSnapshot: null,
      onSnapshot: onSnapshot,
      onImmersiveChanged: onImmersiveChanged,
      companionStageBuilder: (context) => const SizedBox.expand(),
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

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('Start focus'));
  await tester.pump();
}

/// The preset strip scrolls horizontally, so a chip near its end is laid out
/// but clipped. Reveal it the way a user would before tapping it.
Future<void> _selectPreset(WidgetTester tester, String name) async {
  final chip = find.text(name);
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

/// Opens a preset manager row menu and lets the route settle. A menu is laid
/// out with the size of its opening animation, so on its first frame it is
/// neither painted nor hit-testable; a row near the sheet's fold has to be
/// scrolled into view before its button can be tapped.
Future<void> _openPresetMenu(WidgetTester tester, String presetId) async {
  await tester.ensureVisible(
    find.byKey(ValueKey('focus-preset-row-$presetId')),
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('focus-preset-menu-$presetId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapPresetMenuAction(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Advances the page clock and lets the 500 ms ticker deliver the outcome and
/// any single auto-advance transition.
Future<void> _elapse(
  WidgetTester tester,
  _PageClock clock,
  Duration duration,
) async {
  clock.advance(duration);
  for (var step = 0; step < 5; step++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
  await tester.pump();
}

void main() {
  testWidgets('home is stage first, neutral, and has no placeholder stats', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);
    final stage = GlobalKey();

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
        companionStageBuilder: (context) =>
            SizedBox.expand(key: stage, child: const SizedBox()),
      ),
    );
    await tester.pump();

    expect(find.byKey(FocusPage.stageKey), findsOneWidget);
    expect(find.byKey(stage), findsOneWidget);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.byKey(FocusPage.configGridKey), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('4 sessions'), findsOneWidget);
    expect(find.byKey(FocusPage.autoAdvanceKey), findsOneWidget);
    expect(find.text('Auto-start next phase'), findsOneWidget);
    expect(find.byKey(FocusPage.managePresetsKey), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
    expect(find.byKey(FocusPage.configureTimersKey), findsNothing);
    expect(find.text('Edit timers'), findsNothing);
    expect(
      tester.getSize(find.byKey(FocusPage.primaryActionKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getTopLeft(find.byKey(FocusPage.stageKey)).dy,
      lessThan(tester.getTopLeft(find.byKey(FocusPage.timeKey)).dy),
    );
    expect(find.textContaining('Today'), findsNothing);
    expect(find.textContaining('focus sessions'), findsNothing);

    final button = tester.widget<FilledButton>(
      find.byKey(FocusPage.primaryActionKey),
    );
    final background = button.style?.backgroundColor?.resolve(<WidgetState>{});
    expect(background, isNotNull);
    expect(background!.computeLuminance(), lessThan(0.05));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home offers timer configuration only when the host wires it', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);
    final handle = tester.ensureSemantics();
    try {
      var configured = 0;

      await tester.pumpWidget(
        _host(
          settings: settings,
          onOutcome: (outcome, snapshot) async {},
          onSnapshot: (snapshot) async {},
          onConfigureTimers: () => configured += 1,
        ),
      );
      await tester.pump();

      final action = find.byKey(FocusPage.configureTimersKey);
      expect(action, findsOneWidget);
      expect(find.text('Edit timers'), findsOneWidget);
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.label, 'Edit focus and break durations in settings');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

      await tester.tap(action);
      await tester.pump();
      expect(configured, 1);

      await _start(tester);
      expect(find.byKey(FocusPage.configureTimersKey), findsNothing);
      expect(find.text('Edit timers'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      handle.dispose();
    }
  });

  testWidgets('uses the active color scheme in light and dark', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    for (final theme in [CompanionTheme.light, CompanionTheme.dark]) {
      await tester.pumpWidget(
        _host(
          settings: settings,
          theme: theme,
          companionStageBuilder: (context) => const SizedBox.expand(),
          onOutcome: (outcome, snapshot) async {},
          onSnapshot: (snapshot) async {},
        ),
      );
      await tester.pump();

      final scheme = theme.colorScheme;
      final button = tester.widget<FilledButton>(
        find.byKey(FocusPage.primaryActionKey),
      );
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        scheme.primary,
      );
      expect(
        tester.widget<Text>(find.byKey(FocusPage.timeKey)).style?.color,
        scheme.onSurface,
      );
      final stage = tester.widget<FocusStage>(
        find.byKey(FocusPage.stageKey),
      );
      expect(stage.background, scheme.surfaceContainerLow);
      expect(stage.highlight, scheme.surfaceBright);
      expect(stage.border, scheme.outlineVariant);

      await _start(tester);
      final slide = tester.widget<SlideToQuit>(
        find.byKey(FocusPage.slideToQuitKey),
      );
      expect(slide.trackColor, scheme.surfaceContainerHighest);
      expect(slide.thumbColor, scheme.primary);
      expect(slide.labelColor, scheme.onSurfaceVariant);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('selects a focus preset and restores it from the snapshot', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);
    String? saved;
    Widget host({String? initial}) => _host(
      settings: settings,
      snapshot: initial,
      onOutcome: (outcome, snapshot) async {},
      onSnapshot: (snapshot) async => saved = snapshot,
    );

    await tester.pumpWidget(host());
    await _selectPreset(tester, 'Deep work');
    expect(find.text('50:00'), findsOneWidget);
    expect(find.text('50 min'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('20 min'), findsOneWidget);
    expect(FocusSnapshot.tryDecode(saved)?.preset, FocusPreset.deepWork);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(initial: saved));
    await tester.pump();
    expect(find.text('50:00'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Deep work'))
          .selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reports immersive state and starts focus with sparse controls', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
        onImmersiveChanged: events.add,
        companionStageBuilder: (context) => const SizedBox.expand(),
      ),
    );
    await tester.pump();
    expect(events, [false]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);

    await _start(tester);

    expect(events, [false, true]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    expect(find.byKey(FocusPage.closeActionKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(FocusPage.primaryActionKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(FocusPage.closeActionKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Pause'), findsOneWidget);
    expect(find.byTooltip('End focus session'), findsOneWidget);
    expect(find.text('Focus in progress. Keep going.'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(FocusSnapshot.tryDecode(snapshots.single)?.status, FocusStatus.running);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active copy describes the session, not an unwired companion', (
    tester,
  ) async {
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
    expect(find.textContaining('companion'), findsNothing);
    expect(find.textContaining('Companion'), findsNothing);

    await _start(tester);
    expect(find.text('Focus in progress. Keep going.'), findsOneWidget);
    expect(find.textContaining('companion'), findsNothing);
    expect(find.textContaining('Companion'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start short break'));
    await tester.pump();

    expect(find.text('Rest your eyes. This is break time.'), findsOneWidget);
    expect(find.textContaining('companion'), findsNothing);
    expect(find.textContaining('Companion'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pause and resume stay immersive and persist each state', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();
    await _start(tester);

    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    expect(find.text('Paused. Continue when you are ready.'), findsOneWidget);
    expect(FocusSnapshot.tryDecode(snapshots.last)?.status, FocusStatus.paused);
    expect(events, [false, true]);

    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    expect(find.text('Focus in progress. Keep going.'), findsOneWidget);
    expect(FocusSnapshot.tryDecode(snapshots.last)?.status, FocusStatus.running);
    expect(events, [false, true]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('close confirms one cancellation and returns non-immersive', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async => outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();
    await _start(tester);

    await tester.tap(find.byKey(FocusPage.closeActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel this focus session?'), findsOneWidget);
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isFalse);
    expect(
      FocusSnapshot.tryDecode(outcomes.single.$2)?.status,
      FocusStatus.cancelled,
    );
    expect(events, [false, true, false]);
    expect(find.text('Session cancelled'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);
    expect(find.text('Start focus'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored running session reports immersive and keeps its time', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final events = <bool>[];
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
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();

    expect(find.text('15:00'), findsOneWidget);
    expect(events, [true]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored completed session reports non-immersive', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();

    expect(events, [false]);
    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('1 of 4 focus sessions'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restores an overdue session once and clears immersive', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _runningSnapshot(ago: const Duration(minutes: 30)),
        onOutcome: (outcome, snapshot) async => outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
        onImmersiveChanged: events.add,
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
    expect(events, [false]);
    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(outcomes, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide aborts below threshold and quits above it', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async => outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();
    await _start(tester);

    final slide = find.byKey(FocusPage.slideToQuitKey);
    final thumb = find.byKey(SlideToQuit.thumbKey);
    final width = tester.getSize(slide).width;

    await tester.drag(thumb, Offset(width * 0.2, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Cancel this focus session?'), findsNothing);
    expect(outcomes, isEmpty);
    expect(find.text('Slide to quit focus'), findsOneWidget);
    expect(events, [false, true]);

    await tester.drag(thumb, Offset(width * 0.9, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel this focus session?'), findsOneWidget);
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isFalse);
    expect(events, [false, true, false]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide result follows release distance, not fling speed', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        onOutcome: (outcome, snapshot) async => outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();
    await _start(tester);

    await tester.fling(
      find.byKey(SlideToQuit.thumbKey),
      const Offset(60, 0),
      3000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Cancel this focus session?'), findsNothing);
    expect(outcomes, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide exposes a confirmable screen-reader and keyboard path', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          settings: settings,
          onOutcome: (outcome, snapshot) async {},
          onSnapshot: (snapshot) async {},
        ),
      );
      await tester.pump();
      await _start(tester);

      expect(
        tester
            .getSemantics(find.byKey(FocusPage.timeSemanticsKey))
            .getSemanticsData()
            .label,
        contains('Time remaining'),
      );
      expect(find.byTooltip('End focus session'), findsOneWidget);

      final slideNode = tester.getSemantics(
        find.byKey(SlideToQuit.semanticsKey),
      );
      expect(
        slideNode.getSemanticsData().label,
        'Slide to quit focus',
      );
      expect(
        slideNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      final detector = tester.widget<FocusableActionDetector>(
        find.descendant(
          of: find.byType(SlideToQuit),
          matching: find.byType(FocusableActionDetector),
        ),
      );
      expect(detector.enabled, isTrue);
      expect(detector.shortcuts, isNotEmpty);

      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        slideNode.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cancel this focus session?'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      handle.dispose();
    }
  });

  testWidgets('break flow keeps shell chrome and can cancel', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async => outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();
    expect(events, [false]);

    await tester.tap(find.text('Start short break'));
    await tester.pump();
    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('Rest your eyes. This is break time.'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);
    expect(events, [false]);
    expect(
      FocusSnapshot.tryDecode(snapshots.last)?.phase,
      FocusPhase.shortBreak,
    );

    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    expect(find.text('Break paused'), findsOneWidget);

    await tester.tap(find.text('Cancel break'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel this break?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel break'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isFalse);
    expect(
      FocusSnapshot.tryDecode(outcomes.single.$2)?.phase,
      FocusPhase.shortBreak,
    );
    expect(find.text('Break cancelled'), findsOneWidget);
    expect(events, [false]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reflows at 320 x 620 with large text without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = ValueNotifier(const FocusSettings());
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _largeTextHost(
        settings: settings,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(FocusPage.stageKey), findsOneWidget);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);

    await tester.ensureVisible(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(events, [false, true]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    expect(find.byKey(FocusPage.closeActionKey), findsOneWidget);
    expect(find.byKey(FocusPage.primaryActionKey), findsOneWidget);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the timer action reachable at 320 x 640 under the shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = ValueNotifier(const FocusSettings());
    final events = <bool>[];
    addTearDown(settings.dispose);

    // The shell leaves the page 320 x 640 minus its header and navigation,
    // which is where the action used to sit below the fold.
    await tester.pumpWidget(
      MaterialApp(
        theme: CompanionTheme.light,
        home: Scaffold(
          appBar: AppBar(title: const Text('MinuteMeadow')),
          body: FocusPage(
            settings: settings,
            initialSnapshot: null,
            onOutcome: (outcome, snapshot) async {},
            onSnapshot: (snapshot) async {},
            onImmersiveChanged: events.add,
            onConfigureTimers: () {},
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.hourglass_empty),
                label: 'Focus',
              ),
              NavigationDestination(
                icon: Icon(Icons.schedule_outlined),
                label: 'Clock',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final action = find.byKey(FocusPage.primaryActionKey);
    final page = tester.getRect(find.byType(FocusPage));
    final actionRect = tester.getRect(action);
    expect(actionRect.top, greaterThanOrEqualTo(page.top));
    expect(actionRect.bottom, lessThanOrEqualTo(page.bottom));
    expect(action.hitTestable(), findsOneWidget);

    // Setup and history scroll above the bar; the action itself stays put.
    final time = find.byKey(FocusPage.timeKey);
    final timeRect = tester.getRect(time);
    await tester.dragFrom(tester.getCenter(time), const Offset(0, -120));
    await tester.pump();
    expect(tester.getRect(time).top, lessThan(timeRect.top));
    expect(tester.getRect(action), actionRect);

    await tester.tap(action);
    await tester.pump();
    expect(events, [false, true]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabled slide ignores drags until re-enabled', (tester) async {
    var calls = 0;
    Widget build({required bool enabled}) => MaterialApp(
      theme: CompanionTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SlideToQuit(
              enabled: enabled,
              onQuit: () async {
                calls += 1;
                return true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(enabled: false));
    expect(find.text('Finish saving first'), findsOneWidget);
    await tester.drag(
      find.byKey(SlideToQuit.thumbKey),
      const Offset(240, 0),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 0);

    await tester.pumpWidget(build(enabled: true));
    await tester.pump();
    expect(find.text('Slide to quit focus'), findsOneWidget);
    await tester.drag(
      find.byKey(SlideToQuit.thumbKey),
      const Offset(240, 0),
    );
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('slide removes implicit motion under reduced motion', (
    tester,
  ) async {
    var calls = 0;
    Widget build({required bool disableAnimations}) => MaterialApp(
      theme: CompanionTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SlideToQuit(
              onQuit: () async {
                calls += 1;
                return false;
              },
            ),
          ),
        ),
      ),
    );

    AnimatedPositioned thumb() => tester.widget<AnimatedPositioned>(
      find.ancestor(
        of: find.byKey(SlideToQuit.thumbKey),
        matching: find.byType(AnimatedPositioned),
      ),
    );

    await tester.pumpWidget(build(disableAnimations: false));
    expect(
      tester
          .widget<AnimatedContainer>(find.byKey(SlideToQuit.trackKey))
          .duration,
      const Duration(milliseconds: 120),
    );
    expect(thumb().duration, const Duration(milliseconds: 160));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(build(disableAnimations: true));

    expect(
      tester
          .widget<AnimatedContainer>(find.byKey(SlideToQuit.trackKey))
          .duration,
      Duration.zero,
    );
    expect(thumb().duration, Duration.zero);

    final start = tester.getTopLeft(find.byKey(SlideToQuit.thumbKey)).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(SlideToQuit.thumbKey)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(SlideToQuit.thumbKey)).dx,
      greaterThan(start),
    );
    expect(find.text('Keep sliding'), findsOneWidget);
    expect(thumb().duration, Duration.zero);

    await gesture.moveBy(const Offset(220, 0));
    await tester.pump();
    expect(find.text('Release to quit'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(thumb().duration, Duration.zero);
  });

  testWidgets('slide reversal snaps back without confirming', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CompanionTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SlideToQuit(
                onQuit: () async {
                  calls += 1;
                  return false;
                },
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(SlideToQuit.thumbKey)),
    );
    for (var step = 0; step < 5; step++) {
      await gesture.moveBy(const Offset(50, 0));
    }
    await tester.pump();
    expect(find.text('Release to quit'), findsOneWidget);
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(calls, 0);
    expect(find.text('Slide to quit focus'), findsOneWidget);
  });

  testWidgets('setup omits the stage when no companion builder is supplied', (
    tester,
  ) async {
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

    expect(find.byKey(FocusPage.stageKey), findsNothing);
    expect(find.byType(FocusStage), findsNothing);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.configGridKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('duration editor validates and applies a one-off plan', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(FocusPage.focusDurationKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(FocusPage.durationEditorKey), findsOneWidget);

    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '0');
    await tester.pump();
    expect(find.text('Use 1-180'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(FocusPage.applyOneOffKey))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '32');
    await tester.pump();
    expect(find.text('Use 1-180'), findsNothing);
    await tester.tap(find.byKey(FocusPage.applyOneOffKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(FocusPage.durationEditorKey), findsNothing);
    expect(find.text('32 min'), findsOneWidget);
    expect(find.byKey(FocusPage.oneOffPlanKey), findsOneWidget);
    final saved = FocusSnapshot.tryDecode(snapshots.last);
    expect(saved?.plan?.isOneOff, isTrue);
    expect(saved?.plan?.oneOffSettings?.focusMinutes, 32);

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(find.text('32:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saves an edited plan as a default named preset', (tester) async {
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

    await tester.tap(find.byKey(FocusPage.focusDurationKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '45');
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.savePresetActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(FocusPage.presetNameFieldKey), findsOneWidget);
    await tester.enterText(find.byKey(FocusPage.presetNameFieldKey), 'Writing');
    await tester.pump();
    await tester.tap(find.text('Make this the default'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save preset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.widgetWithText(ChoiceChip, 'Writing'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Writing'))
          .selected,
      isTrue,
    );
    expect(find.text('45 min'), findsOneWidget);
    final saved = FocusSnapshot.tryDecode(snapshots.last)?.plan;
    expect(saved?.defaultPreset.name, 'Writing');
    expect(saved?.selectedPreset.name, 'Writing');
    expect(saved?.isOneOff, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manages presets, duplicate/delete and protects the default', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(FocusPage.managePresetsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(FocusPage.presetManagerKey), findsOneWidget);
    expect(find.text('Default: Default'), findsOneWidget);

    await tester.tap(find.byKey(FocusPage.newPresetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(FocusPage.presetNameFieldKey), 'Writing');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create preset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(FocusPage.managePresetsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(
        of: find.byKey(FocusPage.presetManagerKey),
        matching: find.text('Writing'),
      ),
      findsOneWidget,
    );

    await _openPresetMenu(tester, 'custom-3');
    await _tapPresetMenuAction(tester, 'Set as default');
    expect(find.text('Default: Writing'), findsOneWidget);

    await _openPresetMenu(tester, 'custom-3');
    expect(find.text('Delete'), findsNothing);
    await _tapPresetMenuAction(tester, 'Duplicate');
    expect(
      find.descendant(
        of: find.byKey(FocusPage.presetManagerKey),
        matching: find.text('Writing copy'),
      ),
      findsOneWidget,
    );

    await _openPresetMenu(tester, 'custom-4');
    await _tapPresetMenuAction(tester, 'Delete');
    expect(find.text('Delete Writing copy?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Writing copy'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(FocusPage.presetManagerKey),
        matching: find.text('Writing'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edits and renames a built-in preset from the manager', (
    tester,
  ) async {
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

    await tester.tap(find.text('Sprint'));
    await tester.pump();

    await tester.tap(find.byKey(FocusPage.managePresetsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _openPresetMenu(tester, 'sprint');
    await _tapPresetMenuAction(tester, 'Edit values');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(FocusPage.updatePresetKey), findsOneWidget);
    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '20');
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.updatePresetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('20 min'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Sprint'))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(FocusPage.managePresetsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _openPresetMenu(tester, 'sprint');
    await _tapPresetMenuAction(tester, 'Rename');
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byKey(FocusPage.presetNameFieldKey), 'Quick');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.widgetWithText(ChoiceChip, 'Quick'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('auto-advance starts a break only after the outcome is stored', (
    tester,
  ) async {
    final clock = _PageClock();
    final settings = ValueNotifier(const FocusSettings());
    final snapshots = <String>[];
    final outcomes = <(FocusOutcome, String)>[];
    final events = <bool>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        clock: clock,
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
        onImmersiveChanged: events.add,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(FocusPage.autoAdvanceKey));
    await tester.pump();
    expect(
      FocusSnapshot.tryDecode(snapshots.last)?.plan?.autoAdvance,
      isTrue,
    );

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(events, [false, true]);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isTrue);
    expect(find.text('Short break'), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsNothing);
    expect(events, [false, true, false]);

    await tester.pump(const Duration(seconds: 2));
    expect(outcomes, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completion offers a break and a completed break ends the plan', (
    tester,
  ) async {
    final clock = _PageClock();
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        clock: clock,
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('Start short break'), findsOneWidget);
    expect(find.text('Skip break'), findsOneWidget);

    await tester.tap(find.text('Start short break'));
    await tester.pump();
    expect(find.text('Short break'), findsOneWidget);

    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(find.text('Break complete'), findsOneWidget);
    expect(find.text('Start next focus'), findsOneWidget);
    expect(find.text('End plan'), findsOneWidget);

    await tester.tap(find.text('End plan'));
    await tester.pump();
    expect(find.text('Ready to focus'), findsOneWidget);
    expect(find.byKey(FocusPage.configGridKey), findsOneWidget);
    expect(outcomes, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed focus stays on the result by default', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _completedSnapshot(),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('Skip break'), findsOneWidget);
    expect(find.text('Short break'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a two-block plan offers the next block then Done', (
    tester,
  ) async {
    final clock = _PageClock();
    final settings = ValueNotifier(
      const FocusSettings(sessionsPerCycle: 2),
    );
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        clock: clock,
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    await _elapse(tester, clock, const Duration(minutes: 25));

    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('1 of 2 focus sessions'), findsOneWidget);
    expect(find.text('Start short break'), findsOneWidget);
    expect(find.text('Skip break'), findsOneWidget);

    await tester.tap(find.text('Skip break'));
    await tester.pump();
    expect(find.text('Break skipped'), findsOneWidget);
    expect(find.text('Start next focus'), findsOneWidget);
    expect(find.text('End plan'), findsOneWidget);
    expect(outcomes, hasLength(1));

    await tester.tap(find.text('Start next focus'));
    await tester.pump();
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await _elapse(tester, clock, const Duration(minutes: 25));
    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('2 of 2 focus sessions'), findsOneWidget);
    expect(find.text('Start long break'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Start next focus'), findsNothing);

    await tester.tap(find.text('Start long break'));
    await tester.pump();
    await _elapse(tester, clock, const Duration(minutes: 15));

    expect(find.text('Break complete'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Start next focus'), findsNothing);
    expect(outcomes, hasLength(3));

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Ready to focus'), findsOneWidget);
    expect(find.byKey(FocusPage.configGridKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('auto-advance stops after a two-block plan', (tester) async {
    final clock = _PageClock();
    final settings = ValueNotifier(
      const FocusSettings(sessionsPerCycle: 2),
    );
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        clock: clock,
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(FocusPage.autoAdvanceKey));
    await tester.pump();
    await tester.tap(find.text('Start focus'));
    await tester.pump();

    await _elapse(tester, clock, const Duration(minutes: 25));
    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await _elapse(tester, clock, const Duration(minutes: 5));
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await _elapse(tester, clock, const Duration(minutes: 25));
    expect(find.text('Long break'), findsOneWidget);

    await _elapse(tester, clock, const Duration(minutes: 15));
    expect(find.text('Break complete'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Start next focus'), findsNothing);

    final finished = FocusSnapshot.tryDecode(outcomes.last.$2);
    expect(finished?.status, FocusStatus.completed);
    expect(finished?.phase, FocusPhase.longBreak);
    expect(finished?.planTarget, 2);
    expect(finished?.planCompleted, 2);

    final count = outcomes.length;
    await _elapse(tester, clock, const Duration(minutes: 30));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Start next focus'), findsNothing);
    expect(outcomes, hasLength(count));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a one-off covers one whole plan and clears at its end', (
    tester,
  ) async {
    final clock = _PageClock();
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    final snapshots = <String>[];
    final defaultsBefore = settings.value;
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        clock: clock,
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async => snapshots.add(snapshot),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(FocusPage.focusDurationKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '30');
    await tester.enterText(find.byKey(FocusPage.sessionsFieldKey), '2');
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.applyOneOffKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(FocusPage.oneOffPlanKey), findsOneWidget);
    expect(find.text('Applies to the next plan only'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('2 sessions'), findsOneWidget);
    expect(settings.value, defaultsBefore);

    await tester.tap(find.text('Start focus'));
    await tester.pump();

    final running = FocusSnapshot.tryDecode(snapshots.last);
    expect(running?.planTarget, 2);
    expect(running?.planCompleted, 0);
    expect(running?.planSettings?.focusMinutes, 30);
    expect(running?.plan?.isOneOff, isTrue);

    await _elapse(tester, clock, const Duration(minutes: 30));
    expect(find.text('Start short break'), findsOneWidget);
    expect(find.text('1 of 2 focus sessions'), findsOneWidget);
    expect(outcomes, hasLength(1));

    final stored = FocusSnapshot.tryDecode(outcomes.last.$2);
    expect(stored?.planTarget, 2);
    expect(stored?.planSettings?.focusMinutes, 30);
    expect(stored?.plan?.isOneOff, isTrue);
    expect(stored?.plan?.defaultId, FocusPreset.defaultsId);

    await tester.tap(find.text('Skip break'));
    await tester.pump();
    await tester.tap(find.text('End plan'));
    await tester.pump();

    expect(find.byKey(FocusPage.oneOffPlanKey), findsNothing);
    expect(find.text('25 min'), findsOneWidget);
    expect(settings.value, defaultsBefore);

    final ended = FocusSnapshot.tryDecode(snapshots.last);
    expect(ended?.planTarget, 0);
    expect(ended?.plan?.isOneOff, isFalse);
    expect(ended?.plan?.defaultId, FocusPreset.defaultsId);
    expect(ended?.plan?.presets.length, FocusPreset.builtIns.length);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an active plan and its one-off survive recovery', (
    tester,
  ) async {
    final clock = _PageClock();
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    final snapshots = <String>[];
    final defaultsBefore = settings.value;
    addTearDown(settings.dispose);

    Future<void> pumpHost({String? snapshot}) async {
      await tester.pumpWidget(
        _host(
          settings: settings,
          clock: clock,
          snapshot: snapshot,
          onOutcome: (outcome, value) async =>
              outcomes.add((outcome, value)),
          onSnapshot: (value) async => snapshots.add(value),
        ),
      );
      await tester.pump();
    }

    await pumpHost();
    await tester.tap(find.byKey(FocusPage.focusDurationKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(FocusPage.focusMinutesFieldKey), '30');
    await tester.enterText(find.byKey(FocusPage.sessionsFieldKey), '2');
    await tester.pump();
    await tester.tap(find.byKey(FocusPage.applyOneOffKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Start focus'));
    await tester.pump();
    await _elapse(tester, clock, const Duration(minutes: 5));
    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();

    final paused = snapshots.last;
    final pausedSnapshot = FocusSnapshot.tryDecode(paused);
    expect(pausedSnapshot?.status, FocusStatus.paused);
    expect(pausedSnapshot?.planTarget, 2);
    expect(pausedSnapshot?.planSettings?.focusMinutes, 30);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHost(snapshot: paused);

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byKey(FocusPage.primaryActionKey));
    await tester.pump();
    await _elapse(tester, clock, const Duration(minutes: 25));
    expect(find.text('Start short break'), findsOneWidget);
    expect(find.text('1 of 2 focus sessions'), findsOneWidget);

    await tester.tap(find.text('Skip break'));
    await tester.pump();
    await tester.tap(find.text('Start next focus'));
    await tester.pump();
    expect(find.text('30:00'), findsOneWidget);

    await tester.tap(find.byKey(FocusPage.closeActionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final abandoned = FocusSnapshot.tryDecode(outcomes.last.$2);
    expect(abandoned?.planTarget, 0);
    expect(abandoned?.plan?.isOneOff, isFalse);
    expect(abandoned?.plan?.defaultId, FocusPreset.defaultsId);
    expect(settings.value, defaultsBefore);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
