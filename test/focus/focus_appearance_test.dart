import 'package:companion_focus/design/appearance_preferences.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/design/watch_timer_dial.dart';
import 'package:companion_focus/features/focus/background/wallpapers.dart';
import 'package:companion_focus/features/focus/cards/cards.dart';
import 'package:companion_focus/features/focus/focus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required ValueNotifier<FocusSettings> settings,
  required Future<void> Function(FocusOutcome outcome, String snapshot) onOutcome,
  required Future<void> Function(String snapshot) onSnapshot,
  String? snapshot,
  AppearancePreferences appearance = const AppearancePreferences(),
  bool lowPower = false,
  bool? reducedMotion,
  Future<void> Function(FocusOutcome outcome, String snapshot)?
  onRecoveredOutcome,
  WallpaperSelection wallpaperSelection = const NoWallpaperSelection(),
  WallpaperLocation wallpaperLocation = WallpaperLocation.both,
  FocusClock? clock,
  ValueChanged<bool>? onImmersiveChanged,
}) => MaterialApp(
  theme: CompanionTheme.light,
  home: Scaffold(
    body: FocusPage(
      settings: settings,
      onOutcome: onOutcome,
      initialSnapshot: snapshot,
      onSnapshot: onSnapshot,
      appearance: appearance,
      lowPower: lowPower,
      reducedMotion: reducedMotion,
      onRecoveredOutcome: onRecoveredOutcome,
      wallpaperSelection: wallpaperSelection,
      wallpaperLocation: wallpaperLocation,
      clock: clock,
      onImmersiveChanged: onImmersiveChanged,
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

String _overdueSnapshot() {
  final now = DateTime.now().toUtc();
  final start = now.subtract(const Duration(minutes: 30));
  return FocusSnapshot(
    id: 'overdue-appearance',
    phase: FocusPhase.focus,
    status: FocusStatus.running,
    startedAt: start,
    anchor: start,
    intended: const Duration(minutes: 25),
    remaining: null,
    finishedAt: null,
    completedFocusSessions: 0,
  ).encode();
}

void main() {
  testWidgets('default appearance keeps the original setup composition', (
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

    expect(find.byType(FocusCardSurface), findsNothing);
    expect(find.byKey(FocusPage.refinedRingKey), findsNothing);
    expect(find.byKey(FocusPage.studioDialKey), findsNothing);
    expect(find.byKey(FocusPage.watchDialKey), findsNothing);
    expect(find.byKey(FocusPage.wallpaperKey), findsNothing);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.runNameFieldKey), findsOneWidget);
    expect(find.byKey(FocusPage.planPreviewKey), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a chosen card style mounts the shared surface with timer state', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        appearance: const AppearancePreferences(
          cardStyle: FocusCardStyle.glass,
          cardEffect: FocusCardEffect.dunes,
        ),
        lowPower: true,
        reducedMotion: true,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    final surface = tester.widget<FocusCardSurface>(
      find.byKey(FocusPage.cardSurfaceKey),
    );
    expect(surface.appearance.cardStyle, FocusCardStyle.glass);
    expect(surface.appearance.cardEffect, FocusCardEffect.dunes);
    expect(surface.lowPower, isTrue);
    expect(surface.reducedMotion, isTrue);
    expect(surface.progress, 0);
    expect(surface.isBreak, isFalse);
    expect(surface.running, isFalse);
    expect(find.text('Start focus'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the active focus surface follows the chosen card', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        appearance: const AppearancePreferences(
          cardStyle: FocusCardStyle.outlined,
          cardEffect: FocusCardEffect.rain,
        ),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start focus'));
    await tester.pump();

    final surface = tester.widget<FocusCardSurface>(
      find.byKey(FocusPage.cardSurfaceKey),
    );
    expect(surface.isBreak, isFalse);
    expect(surface.running, isTrue);
    expect(surface.progress, 0);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refined and studio keep the real controls and change hierarchy', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    Future<void> pumpAppearance(AppearancePreferences appearance) async {
      await tester.pumpWidget(
        _host(
          settings: settings,
          appearance: appearance,
          onOutcome: (outcome, snapshot) async {},
          onSnapshot: (snapshot) async {},
        ),
      );
      await tester.pump();
    }

    await pumpAppearance(
      const AppearancePreferences(homeLayout: HomeLayout.refined),
    );
    expect(find.byKey(FocusPage.refinedRingKey), findsOneWidget);
    expect(find.byKey(FocusPage.studioDialKey), findsNothing);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.runNameFieldKey), findsOneWidget);
    expect(find.byKey(FocusPage.planPreviewKey), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);

    await pumpAppearance(
      const AppearancePreferences(homeLayout: HomeLayout.studio),
    );
    expect(find.byKey(FocusPage.studioDialKey), findsOneWidget);
    expect(find.byKey(FocusPage.refinedRingKey), findsNothing);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.runNameFieldKey), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a configured wallpaper mounts behind the live UI without new controls', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        wallpaperSelection: const LiveWallpaperSelection(WallpaperType.aurora),
        wallpaperLocation: WallpaperLocation.active,
        lowPower: true,
        reducedMotion: true,
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    final backdrop = tester.widget<FocusWallpaperBackdrop>(
      find.byKey(FocusPage.wallpaperKey),
    );
    expect(backdrop.liveType, WallpaperType.aurora);
    expect(backdrop.photo, isNull);
    expect(backdrop.location, WallpaperLocation.active);
    expect(backdrop.active, isFalse);
    expect(backdrop.lowPower, isTrue);
    expect(backdrop.reducedMotion, isTrue);
    expect(backdrop.overlay, isTrue);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.runNameFieldKey), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);

    await tester.tap(find.text('Start focus'));
    await tester.pump();

    final activeBackdrop = tester.widget<FocusWallpaperBackdrop>(
      find.byKey(FocusPage.wallpaperKey),
    );
    expect(activeBackdrop.active, isTrue);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.byKey(FocusPage.slideToQuitKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the watch dial keeps the exact readout and follows consumed time', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final clock = _PageClock();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        clock: clock,
        appearance: const AppearancePreferences(watchDial: true),
        onOutcome: (outcome, snapshot) async {},
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();

    // Setup has no session, so no hand is painted over the estimate.
    expect(find.byKey(FocusPage.watchDialKey), findsNothing);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);

    await tester.tap(find.text('Start focus'));
    await tester.pump();

    final started = tester.widget<WatchTimerDial>(
      find.byKey(FocusPage.watchDialKey),
    );
    expect(started.progress, 0);
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(milliseconds: 600));

    final elapsed = tester.widget<WatchTimerDial>(
      find.byKey(FocusPage.watchDialKey),
    );
    expect(elapsed.progress, closeTo(0.2, 0.001));
    expect(find.byKey(FocusPage.timeKey), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a recovered cold-start outcome uses its own callback once', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    final recovered = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _overdueSnapshot(),
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
        onRecoveredOutcome: (outcome, snapshot) async =>
            recovered.add((outcome, snapshot)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(outcomes, isEmpty);
    expect(recovered, hasLength(1));
    expect(recovered.single.$1.completed, isTrue);
    expect(
      FocusSnapshot.tryDecode(recovered.single.$2)?.status,
      FocusStatus.completed,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(recovered, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a recovered outcome still falls back to onOutcome', (
    tester,
  ) async {
    final settings = ValueNotifier(const FocusSettings());
    final outcomes = <(FocusOutcome, String)>[];
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _host(
        settings: settings,
        snapshot: _overdueSnapshot(),
        onOutcome: (outcome, snapshot) async =>
            outcomes.add((outcome, snapshot)),
        onSnapshot: (snapshot) async {},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.$1.completed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
