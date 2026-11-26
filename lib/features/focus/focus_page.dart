import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/time/timer_defaults.dart';
import '../../design/companion_theme.dart';
import 'focus_engine.dart';

export 'focus_engine.dart';

/// Focus and break timer surface for the shell.
///
/// The page owns only its engine and ticker. Session records and persisted
/// snapshots belong to the host through [onOutcome] and [onSnapshot].
class FocusPage extends StatefulWidget {
  const FocusPage({
    required this.settings,
    required this.onOutcome,
    required this.initialSnapshot,
    required this.onSnapshot,
    this.onTimelineChanged,
    this.recoveryNow,
    this.clock,
    this.resumeClock,
    super.key,
  });

  final ValueNotifier<FocusSettings> settings;

  /// Terminal session and its snapshot, delivered together for the host's
  /// atomic record-and-persist transaction. Do not also persist this snapshot
  /// through [onSnapshot].
  final Future<void> Function(FocusOutcome outcome, String snapshot) onOutcome;

  final String? initialSnapshot;
  final Future<void> Function(String snapshot) onSnapshot;

  /// Called when the scheduled deadline or phase label changes. The deadline
  /// is null whenever no timer is running.
  final void Function(DateTime? deadline, String phaseLabel)? onTimelineChanged;

  /// Optional wall-clock instant used only while restoring [initialSnapshot].
  /// Android bootstrap can pass a same-boot, elapsed-realtime-adjusted value.
  final DateTime? recoveryNow;
  final FocusClock? clock;
  final Future<void> Function()? resumeClock;

  static const timeKey = Key('focus-time');
  static const primaryActionKey = Key('focus-primary-action');

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> with WidgetsBindingObserver {
  late final FocusEngine _engine;
  late FocusPreset _preset;
  Timer? _ticker;
  ({FocusOutcome outcome, String snapshot})? _pendingOutcome;
  bool _savingOutcome = false;
  bool _snapshotFailed = false;

  FocusSettings get _selectedSettings => _preset.settings(widget.settings.value);
  String _snapshot() => _engine.snapshot().encode(selectedPreset: _preset);

  @override
  void initState() {
    super.initState();
    final saved = FocusSnapshot.tryDecode(widget.initialSnapshot);
    _preset = saved?.preset ?? FocusPreset.defaults;
    _engine = FocusEngine(
      settings: _selectedSettings,
      clock: widget.clock,
      restored: saved,
      recoveredAt: widget.recoveryNow,
    )..prepare();
    widget.settings.addListener(_handleSettingsChanged);
    WidgetsBinding.instance.addObserver(this);

    final overdue = _engine.tick();
    if (overdue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_finish(overdue));
      });
    }
    _syncTicker();
    _notifyTimeline();
  }

  @override
  void didUpdateWidget(covariant FocusPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_handleSettingsChanged);
      widget.settings.addListener(_handleSettingsChanged);
      _handleSettingsChanged();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.settings.removeListener(_handleSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeFromBackground());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_engine.isRunning) _persist();
      _stopTicker();
    }
  }

  Future<void> _resumeFromBackground() async {
    await widget.resumeClock?.call();
    if (!mounted) return;
    _tick();
    _syncTicker();
    _notifyTimeline();
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    setState(() => _engine.updateSettings(_selectedSettings));
    if (_engine.status == FocusStatus.idle ||
        _engine.status == FocusStatus.ready) {
      _persist();
    }
    _notifyTimeline();
  }

  void _startFocus() {
    if (_engine.hasActiveSession) return;
    setState(_engine.startFocus);
    _afterChange();
  }

  void _startBreak() {
    if (_engine.status != FocusStatus.completed ||
        _engine.phase != FocusPhase.focus) {
      return;
    }
    setState(_engine.startBreak);
    _afterChange();
  }

  void _skipBreak() {
    if (_engine.status != FocusStatus.completed ||
        _engine.phase != FocusPhase.focus) {
      return;
    }
    setState(_engine.skipBreak);
    _afterChange();
  }

  void _pause() {
    if (!_engine.isRunning) return;
    final outcome = _engine.pause();
    setState(() {});
    if (outcome != null) {
      unawaited(_finish(outcome));
      return;
    }
    _afterChange();
  }

  void _resume() {
    if (!_engine.isPaused) return;
    setState(_engine.resume);
    _afterChange();
  }

  void _afterChange() {
    _syncTicker();
    _notifyTimeline();
    _persist();
  }

  void _syncTicker() {
    if (_engine.isRunning) {
      _ticker ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _tick(),
      );
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final outcome = _engine.tick();
    if (outcome != null) {
      unawaited(_finish(outcome));
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish(FocusOutcome outcome) async {
    if (!mounted) return;
    setState(() => _pendingOutcome = (outcome: outcome, snapshot: _snapshot()));
    _syncTicker();
    _notifyTimeline();
    await _saveOutcome();
  }

  Future<void> _saveOutcome() async {
    final pending = _pendingOutcome;
    if (pending == null || _savingOutcome) return;
    setState(() => _savingOutcome = true);
    try {
      await widget.onOutcome(pending.outcome, pending.snapshot);
      if (mounted) {
        setState(() {
          _pendingOutcome = null;
          _snapshotFailed = false;
        });
      }
    } catch (_) {
      // Keep the terminal snapshot and offer to retry before starting another session.
    } finally {
      if (mounted) setState(() => _savingOutcome = false);
    }
  }

  Future<void> _confirmCancel() async {
    final isBreak = _engine.phase.isBreak;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isBreak ? 'Cancel this break?' : 'Cancel this focus session?',
        ),
        content: Text(
          isBreak
              ? 'You can start another focus session when you are ready.'
              : 'You have focused for ${_formatDuration(_engine.elapsed)}. '
                    'The session will be recorded as cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isBreak ? 'Cancel break' : 'Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_engine.hasActiveSession) return;

    final outcome = _engine.cancel();
    setState(() {});
    unawaited(_finish(outcome));
  }

  void _selectPreset(FocusPreset preset) {
    if (_pendingOutcome != null || _engine.hasActiveSession || _preset == preset) return;
    setState(() {
      _preset = preset;
      _engine.updateSettings(_selectedSettings);
    });
    _persist(allowTerminal: true);
  }

  void _persist({bool allowTerminal = false}) {
    if (_pendingOutcome != null ||
        (!allowTerminal && (_engine.status == FocusStatus.completed ||
            _engine.status == FocusStatus.cancelled))) {
      return;
    }
    unawaited(_writeSnapshot(_snapshot()));
  }

  Future<void> _writeSnapshot(String snapshot) async {
    try {
      await widget.onSnapshot(snapshot);
      if (mounted && _snapshotFailed) setState(() => _snapshotFailed = false);
    } catch (_) {
      if (mounted && !_snapshotFailed) setState(() => _snapshotFailed = true);
    }
  }

  void _notifyTimeline() {
    widget.onTimelineChanged?.call(_engine.deadline, _engine.phase.label);
  }

  ({String label, IconData icon, VoidCallback onPressed}) get _primaryAction {
    switch (_engine.status) {
      case FocusStatus.idle:
      case FocusStatus.ready:
      case FocusStatus.cancelled:
        return (
          label: 'Start focus',
          icon: Icons.play_arrow,
          onPressed: _startFocus,
        );
      case FocusStatus.running:
        return (label: 'Pause', icon: Icons.pause, onPressed: _pause);
      case FocusStatus.paused:
        return (label: 'Resume', icon: Icons.play_arrow, onPressed: _resume);
      case FocusStatus.completed:
        if (_engine.phase == FocusPhase.focus) {
          final nextBreak = _engine.nextBreakPhase;
          return (
            label: nextBreak == FocusPhase.longBreak
                ? 'Start long break'
                : 'Start short break',
            icon: Icons.local_cafe_outlined,
            onPressed: _startBreak,
          );
        }
        return (
          label: 'Start next focus',
          icon: Icons.play_arrow,
          onPressed: _startFocus,
        );
    }
  }

  ({String label, VoidCallback onPressed})? get _secondaryAction {
    if (_engine.status == FocusStatus.completed &&
        _engine.phase == FocusPhase.focus) {
      return (label: 'Skip break', onPressed: _skipBreak);
    }
    if (_engine.hasActiveSession) {
      return (
        label: _engine.phase.isBreak ? 'Cancel break' : 'Cancel',
        onPressed: _confirmCancel,
      );
    }
    return null;
  }

  int get _cycleDone {
    final count = _engine.completedFocusSessions;
    final inCycle = count % TimerDefaults.sessionsPerCycle;
    if (inCycle == 0 &&
        count > 0 &&
        _engine.status == FocusStatus.completed &&
        _engine.phase == FocusPhase.focus) {
      return TimerDefaults.sessionsPerCycle;
    }
    return inCycle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _engine.remaining;
    final outcome = _engine.lastOutcome;
    final showSummary =
        outcome != null &&
        (_engine.status == FocusStatus.completed ||
            _engine.status == FocusStatus.cancelled);
    final secondary = _secondaryAction;
    final showCycle =
        _engine.phase == FocusPhase.focus &&
        _engine.status != FocusStatus.idle;
    final showPresets = !_engine.hasActiveSession && secondary == null;
    final savePending = _pendingOutcome != null;
    final config = _selectedSettings;
    final primary = _primaryAction;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = math.max(
          0.0,
          constraints.maxHeight - CompanionTheme.pageInset * 2,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(CompanionTheme.pageInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _engine.statusLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'Time remaining ${_spokenDuration(remaining)}',
                      child: ExcludeSemantics(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatDuration(remaining),
                            key: FocusPage.timeKey,
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showSummary) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Planned ${_formatDuration(outcome.intended)} · '
                        'Focused ${_formatDuration(outcome.actual)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (showCycle) _buildCycleDots(theme),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: FocusPage.primaryActionKey,
                       onPressed: savePending ? null : primary.onPressed,
                      icon: Icon(primary.icon),
                      label: Text(primary.label),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 48),
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                         onPressed: savePending ? null : secondary.onPressed,
                        icon: const Icon(Icons.close),
                        label: Text(secondary.label),
                      ),
                    ],
                     if (showPresets) ...[
                       const SizedBox(height: 16),
                       Wrap(
                         alignment: WrapAlignment.center,
                         spacing: 8,
                         children: [
                           for (final preset in FocusPreset.values)
                             ChoiceChip(
                               label: Text(preset.label),
                               selected: _preset == preset,
                               onSelected: savePending ? null : (selected) {
                                 if (selected) _selectPreset(preset);
                               },
                             ),
                         ],
                       ),
                       Text(
                         'Focus ${config.focusMinutes}m · '
                         'Short ${config.shortBreakMinutes}m · '
                         'Long ${config.longBreakMinutes}m',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                     ],
                     if (savePending || _snapshotFailed) ...[
                       const SizedBox(height: 8),
                       Semantics(
                         liveRegion: true,
                         child: Text(
                           _savingOutcome ? 'Saving session…' : 'Could not save the timer.',
                           textAlign: TextAlign.center,
                         ),
                       ),
                       if (!_savingOutcome)
                         TextButton(
                           onPressed: savePending ? _saveOutcome : () => _persist(allowTerminal: true),
                           child: const Text('Retry save'),
                         ),
                     ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCycleDots(ThemeData theme) {
    final done = _cycleDone;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Semantics(
              label: '$done of ${TimerDefaults.sessionsPerCycle} focus sessions completed',
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   for (var index = 0; index < TimerDefaults.sessionsPerCycle; index++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index < done
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$done of ${TimerDefaults.sessionsPerCycle} focus sessions',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inMilliseconds <= 0
      ? 0
      : (duration.inMilliseconds / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String _spokenDuration(Duration duration) {
  final totalSeconds = duration.inMilliseconds <= 0
      ? 0
      : (duration.inMilliseconds / 1000).ceil();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes == 0) return '$seconds seconds';
  final minuteLabel = minutes == 1 ? 'minute' : 'minutes';
  return '$minutes $minuteLabel $seconds seconds';
}
