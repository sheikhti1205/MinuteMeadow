import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../companion_engine/debug/animation_lab_page.dart';
import '../core/notifications/timer_notifications.dart';
import '../core/storage/data_backup.dart';
import '../core/storage/local_database.dart';
import '../core/storage/session_record.dart';
import '../core/time/suspend_aware_clock.dart';
import '../core/time/timer_checkpoint.dart';
import '../design/companion_theme.dart';
import '../features/clock/clock_engine.dart';
import '../features/clock/clock_page.dart';
import '../features/companion/companion_page.dart';
import '../features/companion/companion_scope.dart';
import '../features/companion/companion_session.dart';
import '../features/focus/focus_page.dart';
import '../features/insights/insights_page.dart';
import '../features/marketplace/marketplace_page.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_page.dart';
import 'bootstrap.dart';
import 'branding.dart';
import 'development_catalogue.dart';
import 'installed_companion_view.dart';

/// Development tools are opt-in at build time. A debug build alone never
/// exposes the animation laboratory or the generated catalogue.
const _showDevelopmentTools =
    bool.fromEnvironment('COMPANION_FOCUS_DEVELOPMENT_TOOLS');

class CompanionFocusApp extends ConsumerWidget {
  const CompanionFocusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupProvider);
    return startup.when(
      data: (data) => _RunningApp(data: data, database: ref.watch(databaseProvider)),
      loading: () => const _LaunchScreen(
        child: Text('Opening local data…', semanticsLabel: 'Opening local data'),
      ),
      error: (_, _) => _LaunchScreen(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not open local data.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(startupProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

MaterialApp _app(
  Widget home, {
  AppSettings settings = const AppSettings(),
  CompanionSession? companionSession,
  RouteObserver<ModalRoute<dynamic>>? routeObserver,
}) => MaterialApp(
  title: Branding.name,
  theme: CompanionTheme.light,
  darkTheme: CompanionTheme.dark,
  themeMode: settings.themeMode,
  navigatorObservers: [if (routeObserver != null) routeObserver],
  builder: (context, child) {
    Widget content = child!;
    if (settings.reducedMotion) {
      final media = MediaQuery.of(context);
      content = MediaQuery(
        data: media.copyWith(
          disableAnimations: true,
          accessibleNavigation: true,
        ),
        child: content,
      );
    }
    final session = companionSession;
    if (session == null) return content;
    // Above the navigator so every route, including settings and marketplace,
    // shares the one authoritative library.
    return CompanionSessionScope(session: session, child: content);
  },
  home: home,
);

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _app(Scaffold(
    appBar: AppBar(title: const Text(Branding.name)),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CompanionTheme.pageInset),
          child: child,
        ),
      ),
    ),
  ));
}

class _RunningApp extends StatefulWidget {
  const _RunningApp({required this.data, required this.database});

  final StartupData data;
  final LocalDatabase database;

  @override
  State<_RunningApp> createState() => _RunningAppState();
}

class _RunningAppState extends State<_RunningApp> with WidgetsBindingObserver {
  late final _settings = ValueNotifier(widget.data.settings);
  late final _focusSettings = ValueNotifier(_focusDefaults(widget.data.settings));
  final _companionClip = ValueNotifier<String?>(null);
  final _immersive = ValueNotifier<bool>(false);
  final _elapsedClock = SuspendAwareClock();
  late final _focusClock = _AppFocusClock(_elapsedClock);
  late final _clockProcessToken = DateTime.now().microsecondsSinceEpoch.toString();
  late final _routeObserver = RouteObserver<ModalRoute<dynamic>>();
  late CompanionSession _companionSession;
  late List<SessionRecord> _sessions = widget.data.sessions;
  late String? _focus = widget.data.focus;
  late String? _clock = widget.data.clock;
  late String? _companion = widget.data.companion;
  Future<void> _writes = Future<void>.value();
  int _timerGeneration = 0;
  int _packGeneration = 0;
  final _notifications = TimerNotifications();
  DateTime? _focusDeadline;
  DateTime? _countdownDeadline;
  String _focusAlarmTitle = 'Focus session complete';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _companionSession = _newCompanionSession(widget.data.companion);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_elapsedClock.resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _elapsedClock.markBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.dispose();
    _focusSettings.dispose();
    _companionClip.dispose();
    _immersive.dispose();
    _companionSession.dispose();
    super.dispose();
  }

  FocusSettings _focusDefaults(AppSettings settings) => FocusSettings(
    focusMinutes: settings.focusMinutes,
    shortBreakMinutes: settings.shortBreakMinutes,
    longBreakMinutes: settings.longBreakMinutes,
  );

  CompanionSession _newCompanionSession(String? snapshot) {
    // Capture the generation so a write still in flight from a replaced
    // session cannot commit after a reset has cleared the library.
    final generation = _packGeneration;
    return CompanionSession(
      initialSnapshot: snapshot,
      onSnapshot: (payload) => _savePacks(generation, payload),
    );
  }

  Future<void> _write(Future<void> Function() operation) {
    final pending = _writes.then((_) => operation());
    _writes = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  void _applySettings(AppSettings settings) {
    _settings.value = settings;
    _focusSettings.value = _focusDefaults(settings);
  }

  Future<void> _saveSettings(AppSettings settings) => _write(() async {
    final previous = _settings.value;
    if (settings.notifications && !previous.notifications) {
      if (!await _notifications.requestPermission()) {
        throw const FormatException('Allow notifications in Android settings to enable alerts.');
      }
    }
    await widget.database.writeState('settings', settings.encode());
    if (mounted) _applySettings(settings);
    if (settings.notifications != previous.notifications ||
        settings.sound != previous.sound) {
      await _refreshNotifications(settings);
    }
  });

  Future<void> _refreshNotifications(AppSettings settings) async {
    for (final (id, deadline, title) in [
      (TimerNotifications.focusId, _focusDeadline, _focusAlarmTitle),
      (TimerNotifications.countdownId, _countdownDeadline, 'Countdown complete'),
    ]) {
      if (deadline != null || !settings.notifications) {
        await _setAlarm(id, deadline, title, settings);
      }
    }
  }

  Future<void> _setAlarm(
    int id,
    DateTime? deadline,
    String title,
    AppSettings settings,
  ) async {
    try {
      await _notifications.schedule(
        id: id,
        deadline: deadline,
        title: title,
        enabled: settings.notifications,
        sound: settings.sound,
      );
    } on PlatformException {
      // The timer remains available when Android rejects an alert.
    } on MissingPluginException {
      // A platform bridge is not present in all runners.
    }
  }

  Future<String> _export() async {
    await _writes;
    return DataBackup(settings: _settings.value, sessions: _sessions).encode();
  }

  Future<void> _replace(DataBackup backup, {bool clearPacks = false}) => _write(() async {
    var settings = backup.settings;
    if (settings.notifications && TimerNotifications.available) {
      try {
        settings = settings.copyWith(notifications: await _notifications.hasPermission());
      } on PlatformException {
        settings = settings.copyWith(notifications: false);
      }
    }
    // A restore replaces settings and history, not the saved timer plans. The
    // current checkpoints are read here, inside the serialized queue, so a
    // timer that saved after startup is not replaced by a stale field.
    final retained = clearPacks ? null : await _retainedTimers(settings);
    await widget.database.transaction(() async {
      await widget.database.replaceData(
        settings.encode(),
        backup.sessions,
        clearPacks: clearPacks,
      );
      if (retained != null) {
        await widget.database.writeState('focus', retained.focusCheckpoint);
        await widget.database.writeState('clock', retained.clockCheckpoint);
      }
    });
    final records = await widget.database.sessions();
    if (!mounted) return;
    final previousSession = clearPacks ? _companionSession : null;
    setState(() {
      _timerGeneration++;
      _focus = retained?.focusSnapshot;
      _clock = retained?.clockSnapshot;
      _focusDeadline = null;
      _countdownDeadline = null;
      _sessions = records;
      if (clearPacks) {
        _packGeneration++;
        _companion = null;
        _companionSession = _newCompanionSession(null);
      }
    });
    _applySettings(settings);
    _companionClip.value = null;
    await _setAlarm(TimerNotifications.focusId, null, '', settings);
    await _setAlarm(TimerNotifications.countdownId, null, '', settings);
    if (previousSession != null) {
      // Widgets detach from the replaced notifier during this rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) => previousSession.dispose());
    }
  });

  /// Builds idle timer snapshots that keep the saved plans for a restore.
  ///
  /// An ordinary restore replaces shared settings and history, not the Focus or
  /// Clock setup. Only the plan documents survive: a pending one-off plan, a
  /// running or paused session, stopwatch laps and terminal outcomes are
  /// dropped. Focus resumes ready, with the restored timer settings as the
  /// Default preset's fallback, and Clock resumes in its last visible mode with
  /// its presets and countdown duration intact. Nothing here schedules an
  /// alert or calls back into a page.
  Future<({
    String focusSnapshot,
    String clockSnapshot,
    String focusCheckpoint,
    String clockCheckpoint,
  })> _retainedTimers(AppSettings settings) async {
    final storedFocus = await widget.database.readState('focus');
    final storedClock = await widget.database.readState('clock');
    final focusSource =
        TimerCheckpoint.decode(storedFocus)?.snapshot ?? storedFocus;
    final clockSource =
        TimerCheckpoint.decode(storedClock)?.snapshot ?? storedClock;

    final plan =
        (FocusSnapshot.tryDecode(focusSource)?.plan ?? FocusPlanState.initial)
            .clearOneOff();
    final focus = FocusEngine(
      settings: plan.resolve(_focusDefaults(settings)),
    )..prepare();
    final focusSnapshot = focus.snapshot().encode(
      selectedPreset: plan.presetById(plan.selectedId),
      plan: plan,
    );

    final clock = ClockEngine(
      nowMicroseconds: () => _elapsedClock.elapsed.inMicroseconds,
      initialSnapshot: clockSource,
      processToken: _clockProcessToken,
    );
    final idleMode = clock.mode;
    clock
      ..setMode(ClockMode.stopwatch)
      ..reset()
      ..setMode(ClockMode.countdown)
      ..reset()
      ..setMode(idleMode);
    final clockSnapshot = clock.snapshot();

    final focusCheckpoint = await TimerCheckpoint.capture(focusSnapshot);
    final clockCheckpoint = await TimerCheckpoint.capture(clockSnapshot);
    return (
      focusSnapshot: focusSnapshot,
      clockSnapshot: clockSnapshot,
      focusCheckpoint: focusCheckpoint.encode(),
      clockCheckpoint: clockCheckpoint.encode(),
    );
  }

  Future<void> _saveTimer(int generation, String name, String payload) {
    final checkpoint = TimerCheckpoint.capture(payload);
    return _write(() async {
        if (generation == _timerGeneration) {
          await widget.database.writeState(name, (await checkpoint).encode());
        }
      });
  }

  Future<void> _savePacks(int generation, String payload) => _write(() async {
    if (generation == _packGeneration) {
      await widget.database.writeState('companion', payload);
      _companion = payload;
    }
  });

  Future<void> _record(int generation, FocusOutcome outcome, String snapshot) =>
      _write(() async {
        if (generation != _timerGeneration) return;
        final phase = FocusSnapshot.tryDecode(snapshot)?.phase;
        await widget.database.transaction(() async {
          if (phase == FocusPhase.focus) {
            await widget.database.record(SessionRecord(
              id: outcome.id,
              startedAt: outcome.startedAt,
              finishedAt: outcome.finishedAt,
              intended: outcome.intended,
              actual: outcome.actual,
              completed: outcome.completed,
            ));
          }
          final checkpoint = await TimerCheckpoint.capture(snapshot);
          await widget.database.writeState('focus', checkpoint.encode());
        });
        if (phase == FocusPhase.focus) {
          final records = await widget.database.sessions();
          if (mounted) setState(() => _sessions = records);
        }
        if (!mounted) return;
        if (outcome.completed) await _completionFeedback();
      });

  /// Persists label and note text for one saved session.
  ///
  /// The timer generation captured when the page was built rejects an edit
  /// that arrives after data has been restored or cleared. A missing row is
  /// rejected too, so the history page never reports success for a session
  /// that is no longer saved. Only the fresh records are adopted; labels and
  /// notes never reach a log.
  Future<void> _updateSessionDetails(
    int generation,
    String id,
    SessionDetails details,
  ) => _write(() async {
    if (generation != _timerGeneration) {
      throw StateError('The saved sessions changed.');
    }
    if (!_sessions.any((session) => session.id == id)) {
      throw StateError('That session is no longer saved.');
    }
    await widget.database.updateSessionDetails(id, details);
    final records = await widget.database.sessions();
    if (generation != _timerGeneration) {
      throw StateError('The saved sessions changed.');
    }
    if (!records.any((record) => record.id == id)) {
      throw StateError('That session is no longer saved.');
    }
    if (!mounted) return;
    setState(() => _sessions = records);
  });

  /// Deletes saved sessions in one transaction and adopts the fresh records.
  ///
  /// The generation and membership checks reject a stale selection before a
  /// row is touched: a session that the current library no longer holds cannot
  /// be deleted. The delete and its row-count check then share one outer
  /// transaction, so if the count still disagrees the nested deletion is rolled
  /// back instead of leaving a partial write behind. Fresh records are adopted
  /// only after the transaction commits and the generation still matches.
  Future<void> _deleteSessions(int generation, Set<String> ids) =>
      _write(() async {
        if (generation != _timerGeneration) {
          throw StateError('The saved sessions changed.');
        }
        if (ids.isEmpty) return;
        final saved = _sessions.map((session) => session.id).toSet();
        if (!ids.every(saved.contains)) {
          throw StateError('Some sessions are no longer saved.');
        }
        final records = await widget.database.transaction(() async {
          final removed = await widget.database.deleteSessions(ids);
          if (removed != ids.length) {
            throw StateError('Some sessions were already removed.');
          }
          return widget.database.sessions();
        });
        if (generation != _timerGeneration) {
          throw StateError('The saved sessions changed.');
        }
        if (mounted) setState(() => _sessions = records);
      });

  Future<void> _updateAlarm(
    int generation, {
    required int id,
    required DateTime? deadline,
    required String title,
  }) => _write(() async {
    if (generation != _timerGeneration) return;
    final isFocus = id == TimerNotifications.focusId;
    final previous = isFocus ? _focusDeadline : _countdownDeadline;
    final previousTitle = isFocus ? _focusAlarmTitle : title;
    if (isFocus) {
      _focusDeadline = deadline;
      _focusAlarmTitle = title;
      if (mounted) {
        _companionClip.value = deadline == null
            ? null
            : title == 'Focus session complete' ? 'focus' : 'break';
      }
    } else {
      _countdownDeadline = deadline;
    }
    final settings = _settings.value;
    if (!settings.notifications) return;
    // Focus also sends null on completion; keep its already-due alert.
    // Countdown sends null only when the user clears or changes the timer.
    if (isFocus && deadline == null &&
        (previous == null || !previous.isAfter(DateTime.now()))) {
      return;
    }
    if (deadline != null && previous != null &&
        previousTitle == title && deadline.difference(previous).inMilliseconds.abs() < 500) {
      return;
    }
    await _setAlarm(id, deadline, title, settings);
  });

  Future<void> _completionFeedback() async {
    final settings = _settings.value;
    try {
      if (settings.sound && (!settings.notifications || !TimerNotifications.available)) {
        await SystemSound.play(SystemSoundType.click);
      }
      if (settings.haptics) await HapticFeedback.mediumImpact();
    } on PlatformException {
      // Some platforms do not provide system sound or haptic feedback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _timerGeneration;
    final packGeneration = _packGeneration;
    return ValueListenableBuilder<AppSettings>(
      valueListenable: _settings,
      builder: (context, settings, _) => _app(
        AppShell(
          immersive: _immersive,
          routeObserver: _routeObserver,
          focusBuilder: (openSettings) => FocusPage(
            key: ValueKey(('focus', generation)),
            settings: _focusSettings,
            initialSnapshot: _focus,
            recoveryNow: widget.data.focusRecoveryNow,
            clock: _focusClock,
            resumeClock: _elapsedClock.resume,
            onImmersiveChanged: (value) => _immersive.value = value,
            onConfigureTimers: openSettings,
            onSnapshot: (payload) => _saveTimer(generation, 'focus', payload),
            onOutcome: (outcome, snapshot) => _record(generation, outcome, snapshot),
            onTimelineChanged: (deadline, phase) => unawaited(_updateAlarm(
              generation,
              id: TimerNotifications.focusId,
              deadline: deadline,
              title: phase == FocusPhase.focus.label
                  ? 'Focus session complete'
                  : '$phase complete',
            )),
          ),
          clock: ClockPage(
            key: ValueKey(('clock', generation)),
            initialSnapshot: _clock,
            recoveryNow: widget.data.clockRecoveryNow,
            monotonicNow: () => _elapsedClock.elapsed.inMicroseconds,
            processToken: _clockProcessToken,
            resumeClock: _elapsedClock.resume,
            onSnapshot: (payload) => _saveTimer(generation, 'clock', payload),
            onCountdownDeadlineChanged: (deadline) => _updateAlarm(
              generation,
              id: TimerNotifications.countdownId,
              deadline: deadline,
              title: 'Countdown complete',
            ),
            onCountdownCompleted: () => unawaited(_write(() async {
              if (generation != _timerGeneration || !mounted) return;
              _countdownDeadline = null;
              await _completionFeedback();
            })),
          ),
          companion: CompanionPage(
            key: ValueKey(('companion', packGeneration)),
            initialSnapshot: _companion,
            onSnapshot: (payload) => _savePacks(packGeneration, payload),
            previewBuilder: (context, pack) => InstalledCompanionView(
              key: ValueKey(('companion-preview', pack.id, pack.version)),
              pack: pack,
              useDevelopmentFixture: false,
              stageHeight: 240,
              showInteractionControls: true,
              lowPower: _settings.value.lowPower,
              sound: _settings.value.sound,
              ambientClip: _companionClip,
            ),
          ),
          insights: InsightsPage(
            sessions: _sessions,
            // Both mutations run through the one serialized queue, so a
            // restored or cleared library rejects a stale edit instead of
            // writing into the replacement, and the page only reports success
            // once fresh records have been adopted.
            onUpdateDetails: (id, details) =>
                _updateSessionDetails(generation, id, details),
            onDeleteSessions: (ids) => _deleteSessions(generation, ids),
          ),
          settings: SettingsPage(
            settings: _settings,
            onSave: _saveSettings,
            onExport: _export,
            onReplace: _replace,
            onClear: () => _replace(
              const DataBackup(settings: AppSettings(), sessions: []),
              clearPacks: true,
            ),
            notificationsAvailable: TimerNotifications.available,
            // Report the real Android permission state instead of guessing;
            // the page only requests access when the user enables alerts.
            checkNotificationPermission: TimerNotifications.available
                ? _notifications.hasPermission
                : null,
            animationLab: _showDevelopmentTools ? (_) => const AnimationLabPage() : null,
            // The marketplace resolves the shared session from the scope, so a
            // reset before opening it is always reflected.
            developmentPacks: _showDevelopmentTools
                ? (_) => MarketplacePage(
                    initialSnapshot: _companion,
                    onSnapshot: (payload) => _savePacks(_packGeneration, payload),
                    repository: const DevelopmentCatalogueRepository(),
                  )
                : null,
          ),
        ),
        settings: settings,
        companionSession: _companionSession,
        routeObserver: _routeObserver,
      ),
    );
  }
}

class _AppFocusClock implements FocusClock {
  const _AppFocusClock(this.elapsedClock);

  final SuspendAwareClock elapsedClock;

  @override
  Duration monotonic() => elapsedClock.elapsed;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.focusBuilder,
    required this.clock,
    required this.companion,
    required this.insights,
    required this.settings,
    required this.immersive,
    required this.routeObserver,
    super.key,
  });

  final Widget Function(VoidCallback openSettings) focusBuilder;
  final Widget clock;
  final Widget companion;
  final Widget insights;
  final Widget settings;
  final ValueListenable<bool> immersive;
  final RouteObserver<ModalRoute<dynamic>> routeObserver;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with RouteAware {
  int _selected = 0;
  bool _routeVisible = true;
  ModalRoute<dynamic>? _route;
  static const _titles = ['Focus', 'Clock', 'Companion', 'Insights'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<dynamic>(context);
    if (route != _route) {
      if (_route != null) widget.routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) {
        widget.routeObserver.subscribe(this, route);
        _routeVisible = route.isCurrent;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeObserver != widget.routeObserver) {
      oldWidget.routeObserver.unsubscribe(this);
      final route = _route;
      if (route != null) widget.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (_routeVisible) setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    if (!_routeVisible) setState(() => _routeVisible = true);
  }

  @override
  void dispose() {
    widget.routeObserver.unsubscribe(this);
    super.dispose();
  }

  Widget _tab(int index, Widget child) => TickerMode(
    key: ValueKey('tab-ticker-$index'),
    enabled: _selected == index && _routeVisible,
    child: child,
  );

  /// The one settings route for the shell. The AppBar and the Focus timer
  /// configuration link both push this route from the Navigator below
  /// MaterialApp, so returning lands on the same tab and no second editor
  /// exists.
  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => widget.settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.immersive,
      builder: (context, immersive, _) {
        final showChrome = !immersive;
        return PopScope(
          // A running or paused session must not be ended by the system back
          // gesture; quitting stays an explicit, confirmable action.
          canPop: showChrome,
          child: Scaffold(
            appBar: showChrome
                ? AppBar(
                    title: Text(
                      _selected == 0 ? Branding.name : _titles[_selected],
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: _openSettings,
                      ),
                    ],
                  )
                : null,
            body: SafeArea(
              top: false,
              bottom: false,
              child: IndexedStack(
                index: _selected,
                children: [
                  _tab(0, widget.focusBuilder(_openSettings)),
                  _tab(1, widget.clock),
                  _tab(2, widget.companion),
                  _tab(3, widget.insights),
                ],
              ),
            ),
            bottomNavigationBar: showChrome
                ? NavigationBar(
                    selectedIndex: _selected,
                    onDestinationSelected: (index) =>
                        setState(() => _selected = index),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.hourglass_empty),
                        selectedIcon: Icon(Icons.hourglass_full),
                        label: 'Focus',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.schedule_outlined),
                        selectedIcon: Icon(Icons.watch_later),
                        label: 'Clock',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2),
                        label: 'Companion',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bar_chart_outlined),
                        selectedIcon: Icon(Icons.bar_chart),
                        label: 'Insights',
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}
