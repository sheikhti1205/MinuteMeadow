import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../companion_engine/debug/animation_lab_page.dart';
import '../core/notifications/timer_notifications.dart';
import '../core/storage/backup_file_transport.dart';
import '../core/storage/data_backup.dart';
import '../core/storage/local_database.dart';
import '../core/storage/session_record.dart';
import '../core/time/suspend_aware_clock.dart';
import '../core/time/timer_checkpoint.dart';
import '../design/appearance_preferences.dart';
import '../design/companion_theme.dart';
import '../features/clock/clock_engine.dart';
import '../features/clock/clock_page.dart';
import '../features/companion/companion_page.dart';
import '../features/companion/companion_scope.dart';
import '../features/companion/companion_session.dart';
import '../features/focus/ambience/ambience.dart';
import '../features/focus/background/focus_wallpaper.dart';
import '../features/focus/background/focus_wallpaper_codec.dart';
import '../features/focus/background/focus_wallpaper_store.dart';
import '../features/focus/cards/cards.dart';
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

/// Registers the adapted card-effect notice once for the process.
bool _cardEffectLicenseRegistered = false;

void _registerCardEffectLicenseOnce() {
  if (_cardEffectLicenseRegistered) return;
  _cardEffectLicenseRegistered = true;
  registerCardEffectLicense();
}

/// The settings an ordinary restore stores for the imported document.
///
/// A photo is device media and is never carried by a backup, and it is only
/// adopted after its bytes validated. When one wins, the restored settings
/// store `none` instead of a live type that is not in use; otherwise the
/// imported live choice is kept exactly as it arrived. A full reset discards
/// the photo and needs no normalization.
@visibleForTesting
AppSettings restoredWallpaperSettings(
  AppSettings imported, {
  required bool photoWins,
}) => photoWins
    ? imported.copyWith(
        appearance: imported.appearance.copyWith(
          wallpaper: WallpaperType.none,
        ),
      )
    : imported;

class CompanionFocusApp extends ConsumerWidget {
  const CompanionFocusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _registerCardEffectLicenseOnce();
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
  theme: CompanionTheme.forAppearance(
    settings.appearance,
    brightness: Brightness.light,
  ),
  darkTheme: CompanionTheme.forAppearance(
    settings.appearance,
    brightness: Brightness.dark,
  ),
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
  final _alertNotice = ValueNotifier<String?>(null);
  final _ambienceActive = ValueNotifier<bool>(false);
  bool _ambienceWanted = false;
  final _elapsedClock = SuspendAwareClock();
  late final FocusWallpaperStore _wallpaperStore = FocusWallpaperStore(
    widget.database,
  );
  late WallpaperSelection _wallpaperSelection = WallpaperSelection.fromAppearance(
    widget.data.settings.appearance.wallpaper,
  );
  WallpaperLocation _wallpaperLocation = WallpaperLocation.both;
  int _wallpaperGeneration = 0;
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
  _TimerArm? _focusArm;
  _TimerArm? _countdownArm;
  String _focusAlarmTitle = 'Focus session complete';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _companionSession = _newCompanionSession(widget.data.companion);
    unawaited(_loadWallpaper());
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
    _alertNotice.dispose();
    _ambienceActive.dispose();
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

  /// Runs one data operation after every earlier write has settled.
  ///
  /// Timer snapshots, outcomes, settings, restores and label edits all share
  /// this single queue, so an export always sees a committed document and a
  /// restore cannot interleave with a save. The returned future carries the
  /// operation's own error to its caller; the queue itself keeps going.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final pending = _writes.then((_) => operation());
    _writes = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<void> _write(Future<void> Function() operation) =>
      _serialize<void>(operation);

  void _applySettings(AppSettings settings) {
    _settings.value = settings;
    _focusSettings.value = _focusDefaults(settings);
    if (!settings.notifications) _alertNotice.value = null;
  }

  static const _wallpaperLocationKey = 'focus_wallpaper_location';

  /// Reads the device-local wallpaper beside [fallback]'s built-in choice.
  ///
  /// The stored location and photo are not part of a settings backup, so they
  /// are read beside it. A photo takes precedence over the built-in choice; an
  /// unreadable photo keeps [fallback]'s built-in wallpaper instead of clearing
  /// it. A selection is only a photo after its exact bytes validated, so the
  /// caller can treat `selection.isPhoto` as a usable local photo.
  Future<({
    WallpaperSelection selection,
    WallpaperLocation location,
  })> _resolveWallpaper(AppSettings fallback) async {
    var location = WallpaperLocation.both;
    var selection = WallpaperSelection.fromAppearance(
      fallback.appearance.wallpaper,
    );
    try {
      location = _wallpaperLocationFrom(
        await widget.database.readState(_wallpaperLocationKey),
      );
      final saved = await _wallpaperStore.read();
      if (saved != null) {
        final candidate = await FocusWallpaperCandidate.validate(saved.bytes);
        selection = PhotoWallpaperSelection(
          candidate,
          focal: Alignment(saved.alignmentX, saved.alignmentY),
        );
      }
    } catch (_) {
      // A missing or unreadable photo falls back to the built-in choice.
    }
    return (selection: selection, location: location);
  }

  /// Loads the device-local wallpaper once at startup.
  ///
  /// A restore or reset that replaced the data in between bumps the generation
  /// and rejects this late adoption.
  Future<void> _loadWallpaper() async {
    final generation = _wallpaperGeneration;
    final resolved = await _resolveWallpaper(_settings.value);
    if (!mounted || generation != _wallpaperGeneration) return;
    setState(() {
      _wallpaperLocation = resolved.location;
      _wallpaperSelection = resolved.selection;
    });
  }

  static WallpaperLocation _wallpaperLocationFrom(String? stored) {
    for (final location in WallpaperLocation.values) {
      if (location.name == stored) return location;
    }
    return WallpaperLocation.both;
  }

  /// Commits one wallpaper draft and adopts it only after the commit.
  ///
  /// The built-in preference, the device-local photo and the location are
  /// written in one transaction, so Cancel leaves all three untouched and a
  /// failure cannot leave a half-saved wallpaper. A newer Apply or a full reset
  /// bumps the generation and rejects a late adoption.
  Future<void> _applyWallpaper(WallpaperDraft draft) => _write(() async {
    final generation = ++_wallpaperGeneration;
    final latest = _settings.value;
    final next = latest.copyWith(
      appearance: latest.appearance.copyWith(wallpaper: draft.appearanceType),
    );
    await widget.database.transaction(() async {
      await widget.database.writeState('settings', next.encode());
      final bytes = draft.photoBytes;
      if (draft.usesPhoto && bytes != null) {
        await _wallpaperStore.write(
          FocusWallpaperPhoto(
            bytes: bytes,
            alignmentX: draft.focal.x,
            alignmentY: draft.focal.y,
          ),
        );
      } else {
        await _wallpaperStore.clear();
      }
      await widget.database.writeState(
        _wallpaperLocationKey,
        draft.location.name,
      );
    });
    if (!mounted || generation != _wallpaperGeneration) return;
    _applySettings(next);
    setState(() {
      _wallpaperSelection = draft.selection;
      _wallpaperLocation = draft.location;
    });
  });

  /// Publishes whether quiet Focus ambience may play.
  ///
  /// FocusPage reports its timeline from initState, during our build, so the
  /// value changes after the frame. The wanted flag is updated immediately so a
  /// pause arriving in the same frame cannot leave a stale `true` behind, and
  /// the captured timer generation rejects a report from a page that a restore
  /// or reset has already replaced.
  void _publishAmbienceActive(int generation, bool running) {
    if (generation != _timerGeneration) return;
    if (_ambienceWanted == running) return;
    _ambienceWanted = running;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _timerGeneration) return;
      _ambienceActive.value = _ambienceWanted;
    });
  }

  /// Persists the user's alert intent.
  ///
  /// This never asks Android for a permission: a generic save is not consent.
  /// The Settings opt-in path owns the contextual request, and a restore copies
  /// the saved intent without manufacturing or revoking access.
  Future<void> _saveSettings(AppSettings settings) => _write(() async {
    final previous = _settings.value;
    await widget.database.writeState('settings', settings.encode());
    if (mounted) _applySettings(settings);
    if (settings.notifications != previous.notifications ||
        settings.sound != previous.sound ||
        settings.completionVibration != previous.completionVibration) {
      await _refreshNotifications(settings);
    }
  });

  Future<void> _refreshNotifications(AppSettings settings) async {
    for (final (id, deadline, title) in [
      (TimerNotifications.focusId, _focusDeadline, _focusAlarmTitle),
      (TimerNotifications.countdownId, _countdownDeadline, 'Countdown complete'),
    ]) {
      if (deadline != null || !settings.notifications) {
        await _setAlarm(
          id: id,
          deadline: deadline,
          title: title,
          settings: settings,
        );
      }
    }
  }

  /// Schedules or withdraws one timer kind and records what Android accepted.
  ///
  /// [deadline] null withdraws pending arms of the kind without touching an
  /// alert that already posted. The last armed identity is intentionally kept
  /// on a withdrawal so a live completion can match exactly the schedule the
  /// timer had; a new timer replaces it.
  ///
  /// Alert failures never throw: the timer keeps working, and the state is
  /// reported to Settings through [_alertNotice].
  Future<TimerScheduleResult?> _setAlarm({
    required int id,
    required DateTime? deadline,
    required String title,
    required AppSettings settings,
  }) async {
    final isFocus = id == TimerNotifications.focusId;
    try {
      final result = await _notifications.schedule(
        id: id,
        deadline: deadline,
        title: title,
        enabled: settings.notifications,
        sound: settings.sound,
        vibration: settings.completionVibration,
      );
      if (deadline != null) {
        _TimerArm arm;
        if (result.isScheduled) {
          arm = _TimerArm(
            deadline: result.scheduledAt ?? deadline.toUtc(),
            notificationId: result.notificationId,
          );
        } else {
          // The requested deadline still identifies this timer's completion
          // even when Android refused to arm it.
          arm = _TimerArm(deadline: deadline.toUtc());
        }
        if (isFocus) {
          _focusArm = arm;
        } else {
          _countdownArm = arm;
        }
      }
      _reportAlert(result);
      return result;
    } catch (_) {
      // Platform bridges, mocked hosts and plugin decoding can all fail here.
      // None of them may break the timer or its saved outcome.
      _alertNotice.value = 'Timer alerts could not be scheduled.';
      return null;
    }
  }

  void _reportAlert(TimerScheduleResult result) {
    if (result.needsAttention) {
      _alertNotice.value =
          result.message ?? 'Timer alerts need attention in Settings.';
    } else if (result.outcome == TimerScheduleOutcome.scheduledExact ||
        result.outcome == TimerScheduleOutcome.cleared ||
        result.outcome == TimerScheduleOutcome.testPosted) {
      _alertNotice.value = null;
    }
  }

  Future<String> _export() => _serialize(() async {
    final sessions = await widget.database.sessions();
    return DataBackup(
      settings: _settings.value,
      sessions: sessions,
    ).encode();
  });

  /// Builds the exact document a file save writes.
  ///
  /// The read happens inside the write queue, so presets and history come from
  /// one committed snapshot. With [includePresets] false the preset sections are
  /// omitted, not emptied: a later restore preserves what it does not carry.
  Future<DataBackup> _buildBackup({required bool includePresets}) =>
      _serialize(() => _buildBackupNow(includePresets: includePresets));

  Future<DataBackup> _buildBackupNow({required bool includePresets}) async {
    final settings = _settings.value;
    final sessions = await widget.database.sessions();
    FocusPresetsDocument? focusPresets;
    ClockPresetsDocument? clockPresets;
    if (includePresets) {
      final storedFocus = await _storedSnapshot('focus');
      final plan = FocusSnapshot.tryDecode(storedFocus)?.plan;
      if (plan != null) {
        focusPresets = FocusPresetsDocument.fromPlan(
          plan,
          fallback: _focusDefaults(settings),
        );
      }
      final storedClock = await _storedSnapshot('clock');
      final clock = ClockEngine(
        nowMicroseconds: () => 0,
        initialSnapshot: storedClock,
        processToken: _clockProcessToken,
      );
      final presets = ClockPresetsDocument.fromPresets(clock.presets);
      if (presets.presets.isNotEmpty) clockPresets = presets;
    }
    return DataBackup.portable(
      settings: settings,
      sessions: sessions,
      focusPresets: focusPresets,
      clockPresets: clockPresets,
    );
  }

  /// Counts the saved presets a file save could include.
  ///
  /// Returns null when the stored documents cannot be read, so the export
  /// dialog keeps the opt-in available instead of claiming there are none.
  Future<({int focus, int clock})?> _presetCounts() => _serialize(() async {
    try {
      final backup = await _buildBackupNow(includePresets: true);
      return (
        focus: backup.focusPresets?.presets.length ?? 0,
        clock: backup.clockPresets?.presets.length ?? 0,
      );
    } catch (_) {
      return null;
    }
  });

  Future<String?> _storedSnapshot(String name) async {
    final stored = await widget.database.readState(name);
    return TimerCheckpoint.decode(stored)?.snapshot ?? stored;
  }

  Future<void> _replace(DataBackup backup, {bool clearPacks = false}) =>
      _write(() async {
        final imported = backup.settings;
        // A photo is device media and is never carried by a backup. When one is
        // present and usable it is what Focus shows, so the restored settings
        // store `none` instead of a live type that is not in use.
        final wallpaper = clearPacks
            ? null
            : await _resolveWallpaper(imported);
        final settings = wallpaper == null
            ? imported
            : restoredWallpaperSettings(
                imported,
                photoWins: wallpaper.selection.isPhoto,
              );
        // A restore replaces settings and history, not the saved timer plans.
        // The current checkpoints are read here, inside the serialized queue, so
        // a timer that saved after startup is not replaced by a stale field.
        // A schema 2 document may also carry preset sections; only those
        // sections are replaced, and only after both timers are reset.
        final retained = clearPacks
            ? null
            : await _retainedTimers(
                settings,
                focusPresets: backup.focusPresets,
                clockPresets: backup.clockPresets,
              );
        final records =
            await widget.database.transaction<List<SessionRecord>>(() async {
              await widget.database.replaceData(
                settings.encode(),
                backup.sessions,
                clearPacks: clearPacks,
              );
              if (retained != null) {
                await widget.database.writeState(
                  'focus',
                  retained.focusCheckpoint,
                );
                await widget.database.writeState(
                  'clock',
                  retained.clockCheckpoint,
                );
              }
              // The rows this commit wrote are read inside it. A read after the
              // commit could fault on a replacement that is already durable,
              // report it as failed, and invite the user to repeat a
              // destructive restore.
              return await widget.database.sessions();
            });
        if (!mounted) return;
        final previousSession = clearPacks ? _companionSession : null;
        setState(() {
          _timerGeneration++;
          _focus = retained?.focusSnapshot;
          _clock = retained?.clockSnapshot;
          _focusDeadline = null;
          _countdownDeadline = null;
          _focusArm = null;
          _countdownArm = null;
          _sessions = records;
          _wallpaperGeneration++;
          if (wallpaper == null) {
            _wallpaperSelection = const NoWallpaperSelection();
            _wallpaperLocation = WallpaperLocation.both;
          } else {
            _wallpaperSelection = wallpaper.selection;
            _wallpaperLocation = wallpaper.location;
          }
          if (clearPacks) {
            _packGeneration++;
            _companion = null;
            _companionSession = _newCompanionSession(null);
          }
        });
        _ambienceActive.value = false;
        _ambienceWanted = false;
        _applySettings(settings);
        _companionClip.value = null;
        // The commit has already happened. A platform cleanup failure here must
        // not report the restore as failed or invite a second replacement.
        try {
          await _setAlarm(
            id: TimerNotifications.focusId,
            deadline: null,
            title: '',
            settings: _settings.value,
          );
          await _setAlarm(
            id: TimerNotifications.countdownId,
            deadline: null,
            title: '',
            settings: _settings.value,
          );
        } catch (_) {
          // Alerts are reconciled best effort after a successful restore.
        }
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
  /// its presets and countdown duration intact. A schema 2 restore additionally
  /// replaces the preset sections it carries, after both timers are reset.
  /// Nothing here schedules an alert or calls back into a page.
  Future<({
    String focusSnapshot,
    String clockSnapshot,
    String focusCheckpoint,
    String clockCheckpoint,
  })> _retainedTimers(
    AppSettings settings, {
    FocusPresetsDocument? focusPresets,
    ClockPresetsDocument? clockPresets,
  }) async {
    final focusSource = await _storedSnapshot('focus');
    final clockSource = await _storedSnapshot('clock');

    final plan =
        focusPresets?.toPlanState(fallback: _focusDefaults(settings)) ??
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
    var clockSnapshot = clock.snapshot();
    if (clockPresets != null) {
      clockSnapshot = _withClockPresets(clockSnapshot, clockPresets);
    }

    final focusCheckpoint = await TimerCheckpoint.capture(focusSnapshot);
    final clockCheckpoint = await TimerCheckpoint.capture(clockSnapshot);
    return (
      focusSnapshot: focusSnapshot,
      clockSnapshot: clockSnapshot,
      focusCheckpoint: focusCheckpoint.encode(),
      clockCheckpoint: clockCheckpoint.encode(),
    );
  }

  /// Replaces only the saved preset list of an already-idle Clock snapshot.
  ///
  /// The selection is cleared so a restored preset cannot leave a stale
  /// selection pointing at a removed id. Measured time, laps and completion
  /// state are not present in the idle snapshot this is applied to.
  String _withClockPresets(String snapshot, ClockPresetsDocument document) {
    document.validate();
    final decoded = jsonDecode(snapshot);
    if (decoded is! Map<String, Object?>) return snapshot;
    return jsonEncode(<String, Object?>{
      ...decoded,
      'selectedPresetId': null,
      'presets': <Object>[
        for (final preset in document.presets) preset.toJson(),
      ],
    });
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

  Future<void> _record(
    int generation,
    FocusOutcome outcome,
    String snapshot, {
    bool recovered = false,
  }) async {
    _TimerArm? completionArm;
    var playCompletion = false;
    await _write(() async {
      if (generation != _timerGeneration) return;
      final parsed = FocusSnapshot.tryDecode(snapshot);
      final phase = parsed?.phase;
      final label = parsed?.label;
      final records = await widget.database
          .transaction<List<SessionRecord>?>(() async {
            if (phase == FocusPhase.focus) {
              await widget.database.record(SessionRecord(
                id: outcome.id,
                startedAt: outcome.startedAt,
                finishedAt: outcome.finishedAt,
                intended: outcome.intended,
                actual: outcome.actual,
                completed: outcome.completed,
                // Descriptive only: the same label the snapshot holds, never a
                // duration or outcome change.
                label: label,
              ));
            }
            final checkpoint = await TimerCheckpoint.capture(snapshot);
            await widget.database.writeState('focus', checkpoint.encode());
            // The fresh rows are read inside the commit. A read after it could
            // fault on an outcome that is already saved, report the save as
            // failed and invite a retry that records the same session twice.
            if (phase != FocusPhase.focus) return null;
            return await widget.database.sessions();
          });
      if (records != null && mounted) {
        final saved = records;
        setState(() => _sessions = saved);
      }
      // A session that finished while the app was closed was delivered by
      // Android already. Keep its record, retire the stale arm and never
      // replay the chime. Only the Focus arm is retired: a Clock countdown is
      // its own timer and a recovered Focus outcome must not disturb it.
      if (recovered) {
        _focusArm = null;
        _focusDeadline = null;
        if (_settings.value.notifications) {
          await _setAlarm(
            id: TimerNotifications.focusId,
            deadline: null,
            title: '',
            settings: _settings.value,
          );
        }
        return;
      }
      if (outcome.completed) {
        // Consume the exact arm with the committed outcome, then play the
        // feedback outside this write, so a platform failure can neither fail
        // the saved outcome nor repeat on a retry.
        completionArm = _focusArm;
        _focusArm = null;
        _focusDeadline = null;
        playCompletion = true;
      } else {
        // A cancelled or skipped run never alerts. Its arm is already
        // withdrawn by the timeline; drop the identity so it cannot match a
        // later completion.
        _focusArm = null;
      }
    });
    if (!playCompletion || !mounted) return;
    await _completeTimer(
      id: TimerNotifications.focusId,
      sound: _settings.value.sound,
      vibration: _settings.value.completionVibration,
      arm: completionArm,
      consumeState: false,
    );
  }

  /// Plays the countdown completion after its committed state is checked.
  Future<void> _finishCountdown(int generation) async {
    _TimerArm? arm;
    var play = false;
    await _write(() async {
      if (generation != _timerGeneration) return;
      arm = _countdownArm;
      _countdownArm = null;
      _countdownDeadline = null;
      play = true;
    });
    if (!play || !mounted) return;
    await _completeTimer(
      id: TimerNotifications.countdownId,
      sound: _settings.value.sound,
      vibration: _settings.value.completionVibration,
      arm: arm,
      consumeState: false,
    );
  }

  /// Plays the one live completion alert for a timer kind.
  ///
  /// The arm is consumed before the native call, so a retried save cannot play
  /// the same completion twice, and a failure is reported in Settings instead
  /// of failing the saved outcome. Android's host compares the exact
  /// kind/deadline/id before withdrawing or suppressing anything, so an alert
  /// that already posted is never removed and never played twice.
  Future<void> _completeTimer({
    required int id,
    required bool sound,
    required bool vibration,
    _TimerArm? arm,
    bool consumeState = true,
  }) async {
    final isFocus = id == TimerNotifications.focusId;
    final _TimerArm? armed;
    if (consumeState) {
      armed = isFocus ? _focusArm : _countdownArm;
      if (isFocus) {
        _focusArm = null;
        _focusDeadline = null;
      } else {
        _countdownArm = null;
        _countdownDeadline = null;
      }
    } else {
      armed = arm;
    }
    if (!TimerNotifications.available) {
      try {
        await _platformCompletionFeedback(sound: sound, vibration: vibration);
      } catch (_) {
        // Feedback is best effort. It must not fail the already saved outcome
        // or invite a retry that would play it again.
      }
      return;
    }
    try {
      final result = await _notifications.completeInForeground(
        id: id,
        deadline: armed?.deadline,
        scheduledId: armed?.notificationId,
        sound: sound,
        vibration: vibration,
      );
      if (result.needsAttention) {
        _alertNotice.value =
            result.message ?? 'The completion alert could not be confirmed.';
      } else {
        _alertNotice.value = null;
      }
    } catch (_) {
      // The saved outcome is already committed; feedback is best effort.
      _alertNotice.value = 'The completion alert could not be played.';
    }
  }

  /// Non-Android completion feedback for web and desktop runners.
  ///
  /// Android always uses the runner host, even when notifications are blocked,
  /// so a denied permission never falls back to the legacy system click.
  Future<void> _platformCompletionFeedback({
    required bool sound,
    required bool vibration,
  }) async {
    try {
      if (sound) await SystemSound.play(SystemSoundType.click);
      if (vibration) await HapticFeedback.mediumImpact();
    } on PlatformException {
      // Some platforms do not provide system sound or haptic feedback.
    }
  }

  /// Sends the Settings test alert on the real completion channel.
  Future<({bool ok, String message})> _sendTestAlert({
    required bool sound,
    required bool vibration,
  }) async {
    final result = await _notifications.showTestNotification(
      sound: sound,
      vibration: vibration,
    );
    _reportAlert(result);
    final ok = result.outcome == TimerScheduleOutcome.testPosted;
    return (
      ok: ok,
      message: result.message ??
          (ok ? 'Test alert sent.' : 'The test alert could not be shown.'),
    );
  }

  /// Plays the completion chime through the same host a finished timer uses.
  Future<({bool ok, String message})> _previewCompletionChime({
    required bool sound,
    required bool vibration,
  }) async {
    if (!sound && !vibration) {
      return (ok: false, message: 'Turn on sound or completion vibration first.');
    }
    final played = await _notifications.playCompletion(
      sound: sound,
      vibration: vibration,
    );
    return played
        ? (ok: true, message: 'Completion chime played.')
        : (ok: false, message: 'The completion chime could not play here.');
  }

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

  /// Applies a timeline change from the Focus page.
  ///
  /// A null deadline withdraws pending arms of the kind but keeps the armed
  /// identity, because the same signal is sent when a session completes and
  /// when it is cancelled or paused. A live completion then matches the exact
  /// schedule it is finishing; a new timer replaces the identity.
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
    final settings = _settings.value;

    if (deadline == null) {
      if (isFocus) {
        _focusDeadline = null;
        if (mounted) _companionClip.value = null;
      } else {
        _countdownDeadline = null;
      }
      if (!settings.notifications) return;
      await _setAlarm(
        id: id,
        deadline: null,
        title: '',
        settings: settings,
      );
      return;
    }

    if (isFocus) {
      _focusDeadline = deadline;
      _focusAlarmTitle = title;
      if (mounted) {
        _companionClip.value = title == 'Focus session complete'
            ? 'focus'
            : 'break';
      }
    } else {
      _countdownDeadline = deadline;
    }
    if (!settings.notifications) return;
    if (previous != null &&
        previousTitle == title &&
        deadline.difference(previous).inMilliseconds.abs() < 500) {
      return;
    }
    await _setAlarm(
      id: id,
      deadline: deadline,
      title: title,
      settings: settings,
    );
  });

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
          focusBuilder: (openSettings) => ValueListenableBuilder<bool>(
            valueListenable: _ambienceActive,
            builder: (context, ambienceActive, child) => FocusAmbienceRunner(
              preferences: settings.focusAmbience,
              active: ambienceActive,
              routeObserver: _routeObserver,
              child: child!,
            ),
            child: FocusPage(
              key: ValueKey(('focus', generation)),
              settings: _focusSettings,
              initialSnapshot: _focus,
              recoveryNow: widget.data.focusRecoveryNow,
              clock: _focusClock,
              resumeClock: _elapsedClock.resume,
              appearance: settings.appearance,
              lowPower: settings.lowPower,
              reducedMotion: settings.reducedMotion,
              wallpaperSelection: _wallpaperSelection,
              wallpaperLocation: _wallpaperLocation,
              onImmersiveChanged: (value) => _immersive.value = value,
              onConfigureTimers: openSettings,
              onSnapshot: (payload) => _saveTimer(generation, 'focus', payload),
              onOutcome: (outcome, snapshot) =>
                  _record(generation, outcome, snapshot),
              // A session recovered at boot keeps its history record but never
              // replays a completion chime the user did not hear finish.
              onRecoveredOutcome: (outcome, snapshot) =>
                  _record(generation, outcome, snapshot, recovered: true),
              onTimelineChanged: (deadline, phase) {
                final isFocus = phase == FocusPhase.focus.label;
                // Ambience may play only for a running focus block, never a
                // break or a paused session. The callback runs during build.
                _publishAmbienceActive(
                  generation,
                  deadline != null && isFocus,
                );
                unawaited(
                  _updateAlarm(
                    generation,
                    id: TimerNotifications.focusId,
                    deadline: deadline,
                    title: isFocus
                        ? 'Focus session complete'
                        : '$phase complete',
                  ),
                );
              },
            ),
          ),
          clock: ClockPage(
            key: ValueKey(('clock', generation)),
            initialSnapshot: _clock,
            recoveryNow: widget.data.clockRecoveryNow,
            monotonicNow: () => _elapsedClock.elapsed.inMicroseconds,
            processToken: _clockProcessToken,
            resumeClock: _elapsedClock.resume,
            watchDial: settings.appearance.watchDial,
            onSnapshot: (payload) => _saveTimer(generation, 'clock', payload),
            onCountdownDeadlineChanged: (deadline) => _updateAlarm(
              generation,
              id: TimerNotifications.countdownId,
              deadline: deadline,
              title: 'Countdown complete',
            ),
            // Clock completion is live only: ClockPage never calls this from a
            // restored checkpoint, so a cold start stays silent.
            onCountdownCompleted: () =>
                unawaited(_finishCountdown(generation)),
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
            // the page only requests access when the user opts in.
            checkNotificationPermission: TimerNotifications.available
                ? _notifications.hasPermission
                : null,
            requestNotificationPermission: TimerNotifications.available
                ? _notifications.requestPermission
                : null,
            checkExactAlarmPermission: TimerNotifications.available
                ? _notifications.canScheduleExact
                : null,
            onRequestExactAlarmPermission: TimerNotifications.available
                ? _notifications.requestExactAlarmPermission
                : null,
            onOpenNotificationSettings: TimerNotifications.available
                ? _notifications.openNotificationSettings
                : null,
            onSendTestAlert: TimerNotifications.available
                ? _sendTestAlert
                : null,
            onPreviewCompletionChime: TimerNotifications.available
                ? _previewCompletionChime
                : null,
            alertNotice: _alertNotice,
            readPresetCounts: _presetCounts,
            onBuildBackup: _buildBackup,
            fileTransport: BackupFileTransport.instance,
            wallpaperSelection: _wallpaperSelection,
            wallpaperLocation: _wallpaperLocation,
            onApplyWallpaper: _applyWallpaper,
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

/// The exact schedule a running timer was armed with.
///
/// [deadline] is the wall-clock deadline requested for the arm (or the actual
/// scheduled instant Android reported). [notificationId] is present only when
/// Android accepted a schedule, so a completion can match a posted alert by ID
/// before falling back to the kind/deadline payload.
class _TimerArm {
  const _TimerArm({required this.deadline, this.notificationId});

  final DateTime deadline;
  final int? notificationId;
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
