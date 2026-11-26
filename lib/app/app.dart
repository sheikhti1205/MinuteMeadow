import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../features/clock/clock_page.dart';
import '../features/companion/companion_page.dart';
import '../features/focus/focus_page.dart';
import '../features/insights/insights_page.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_page.dart';
import 'bootstrap.dart';
import 'branding.dart';
import 'installed_companion_view.dart';

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

MaterialApp _app(Widget home, {AppSettings settings = const AppSettings()}) =>
    MaterialApp(
      title: Branding.name,
      theme: CompanionTheme.light,
      darkTheme: CompanionTheme.dark,
      themeMode: settings.themeMode,
      builder: (context, child) {
        if (!settings.reducedMotion) return child!;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(disableAnimations: true, accessibleNavigation: true),
          child: child!,
        );
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
  final _elapsedClock = SuspendAwareClock();
  late final _focusClock = _AppFocusClock(_elapsedClock);
  late final _clockProcessToken = DateTime.now().microsecondsSinceEpoch.toString();
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
    super.dispose();
  }

  FocusSettings _focusDefaults(AppSettings settings) => FocusSettings(
    focusMinutes: settings.focusMinutes,
    shortBreakMinutes: settings.shortBreakMinutes,
    longBreakMinutes: settings.longBreakMinutes,
  );

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
    await widget.database.replaceData(
      settings.encode(),
      backup.sessions,
      clearPacks: clearPacks,
    );
    final records = await widget.database.sessions();
    if (!mounted) return;
    setState(() {
      _timerGeneration++;
      _focus = null;
      _clock = null;
      _focusDeadline = null;
      _countdownDeadline = null;
      _sessions = records;
      if (clearPacks) {
        _packGeneration++;
        _companion = null;
      }
    });
    _applySettings(settings);
    _companionClip.value = null;
    await _setAlarm(TimerNotifications.focusId, null, '', settings);
    await _setAlarm(TimerNotifications.countdownId, null, '', settings);
  });

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
    if (deadline == null && (previous == null || !previous.isAfter(DateTime.now()))) {
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
          focus: FocusPage(
            key: ValueKey(('focus', generation)),
            settings: _focusSettings,
            initialSnapshot: _focus,
            recoveryNow: widget.data.focusRecoveryNow,
            clock: _focusClock,
            resumeClock: _elapsedClock.resume,
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
              key: ValueKey((pack.id, pack.version)),
              pack: pack,
              lowPower: _settings.value.lowPower,
              ambientClip: _companionClip,
            ),
          ),
          insights: InsightsPage(sessions: _sessions),
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
            animationLab: kDebugMode ? (_) => const AnimationLabPage() : null,
          ),
        ),
        settings: settings,
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
    required this.focus,
    required this.clock,
    required this.companion,
    required this.insights,
    required this.settings,
    super.key,
  });

  final Widget focus;
  final Widget clock;
  final Widget companion;
  final Widget insights;
  final Widget settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  static const _titles = ['Focus', 'Clock', 'Companion', 'Insights'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_selected == 0 ? Branding.name : _titles[_selected]),
      actions: [
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => widget.settings),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: IndexedStack(
        index: _selected,
        children: [widget.focus, widget.clock, widget.companion, widget.insights],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
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
    ),
  );
}
