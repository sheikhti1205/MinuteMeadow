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
      onImmersiveChanged: onImmersiveChanged,
      companionStageBuilder: companionStageBuilder,
      onConfigureTimers: onConfigureTimers,
    ),
  ),
);

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
    expect(find.text('Focus 25m · Short 5m · Long 15m'), findsOneWidget);
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
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);
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
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

    await tester.tap(action);
    await tester.pump();
    expect(configured, 1);

    await _start(tester);
    expect(find.byKey(FocusPage.configureTimersKey), findsNothing);
    expect(find.text('Edit timers'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uses the active color scheme in light and dark', (tester) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    for (final theme in [CompanionTheme.light, CompanionTheme.dark]) {
      await tester.pumpWidget(
        _host(
          settings: settings,
          theme: theme,
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
    await tester.tap(find.text('Deep work'));
    await tester.pump();
    expect(find.text('50:00'), findsOneWidget);
    expect(find.text('Focus 50m · Short 10m · Long 20m'), findsOneWidget);
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
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);
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
    expect(slideNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final detector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byType(SlideToQuit),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    expect(detector.enabled, isTrue);
    expect(detector.shortcuts, isNotEmpty);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(
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
}
