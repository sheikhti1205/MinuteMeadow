import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/companion_theme.dart';
import 'clock_engine.dart';
import 'clock_format.dart';

final Stopwatch _processStopwatch = Stopwatch()..start();

int _monotonicNow() => _processStopwatch.elapsedMicroseconds;

/// The Clock screen: a monotonic stopwatch with laps and a countdown with
/// saved presets.
///
/// The page owns no storage or notification plugin. It reports snapshots and
/// countdown deadlines through callbacks so the host app can persist state and
/// schedule platform notifications.
class ClockPage extends StatefulWidget {
  const ClockPage({
    required this.initialSnapshot,
    required this.onSnapshot,
    this.engine,
    this.onCountdownDeadlineChanged,
    this.onCountdownCompleted,
    this.recoveryNow,
    this.wallClock,
    this.monotonicNow,
    this.processToken,
    this.resumeClock,
    super.key,
  });

  /// Serialized state from a previous page or process lifetime.
  final String? initialSnapshot;

  /// Called whenever the page has new state that should be persisted.
  final Future<void> Function(String) onSnapshot;

  /// Optional pre-built engine, useful for deterministic widget tests.
  final ClockEngine? engine;

  /// Receives the absolute UTC finish time for a running countdown, or `null`
  /// when the countdown is paused, reset or abandoned. A running countdown
  /// re-emits a fresh deadline when the app resumes so the host can re-anchor
  /// an inexact platform alert after a system clock change.
  ///
  /// A countdown that reaches its deadline in the foreground does not send
  /// `null`: the host should treat the deadline as already reached so it can
  /// avoid cancelling a just-matured scheduled notification.
  final Future<void> Function(DateTime?)? onCountdownDeadlineChanged;

  /// Optional foreground feedback hook for a countdown completion.
  final VoidCallback? onCountdownCompleted;

  /// Optional trusted wall time for restoring [initialSnapshot] after a
  /// process restart.
  ///
  /// A restarted process cannot measure the gap with its own monotonic clock.
  /// Android can pass a wall reference adjusted with `elapsedRealtime` so the
  /// engine can bridge the gap for a running countdown or stopwatch. Ignored
  /// when [engine] is supplied.
  final DateTime? recoveryNow;

  /// Optional wall clock override for tests. Defaults to `DateTime.now`.
  final DateTime Function()? wallClock;
  final int Function()? monotonicNow;
  final String? processToken;
  final Future<void> Function()? resumeClock;

  static const timeKey = Key('clock-time');
  static const primaryActionKey = Key('clock-primary-action');
  static const resetActionKey = Key('clock-reset');
  static const lapActionKey = Key('clock-lap');
  static const repeatActionKey = Key('clock-repeat');
  static const setDurationKey = Key('clock-set-duration');
  static const addPresetKey = Key('clock-add-preset');
  static const hoursFieldKey = Key('clock-hours');
  static const minutesFieldKey = Key('clock-minutes');
  static const secondsFieldKey = Key('clock-seconds');
  static const presetLabelKey = Key('clock-preset-label');
  static const durationSubmitKey = Key('clock-duration-submit');
  static const presetSubmitKey = Key('clock-preset-submit');
  static const hiddenCountdownKey = Key('clock-hidden-countdown');
  static const hiddenStopwatchKey = Key('clock-hidden-stopwatch');

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> with WidgetsBindingObserver {
  late final ClockEngine _engine;
  Timer? _ticker;
  String? _lastSnapshot;
  bool _saveFailed = false;

  bool get _isCountdown => _engine.mode == ClockMode.countdown;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ??
        ClockEngine(
          nowMicroseconds: widget.monotonicNow ?? _monotonicNow,
          initialSnapshot: widget.initialSnapshot,
          recoveryNow: widget.recoveryNow,
          wallClock: widget.wallClock,
          processToken: widget.processToken,
        );
    WidgetsBinding.instance.addObserver(this);
    _syncTicker();
    if (_engine.isCountdownRunning) {
      _notifyDeadline(_deadlineFromRemaining());
    }
    if (widget.initialSnapshot != null) _persistSnapshot();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _persistSnapshot();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_resumeFromBackground());
      case AppLifecycleState.inactive:
        _persistSnapshot();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _ticker?.cancel();
        _ticker = null;
        _persistSnapshot();
    }
  }

  Future<void> _resumeFromBackground() async {
    await widget.resumeClock?.call();
    if (!mounted) return;
    final completionBefore = _engine.completionCount;
    setState(_engine.update);
    final completed = _engine.completionCount != completionBefore;
    if (completed) {
      widget.onCountdownCompleted?.call();
    } else if (_engine.isCountdownRunning) {
      _notifyDeadline(_deadlineFromRemaining());
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _syncTicker() {
    if (_engine.hasRunningMeasurement) {
      _ticker ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _onTick(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onTick() {
    if (!mounted) {
      return;
    }
    final completionBefore = _engine.completionCount;
    setState(_engine.update);
    if (_engine.completionCount != completionBefore) {
      widget.onCountdownCompleted?.call();
      _persistSnapshot();
    }
    if (!_engine.hasRunningMeasurement) {
      _syncTicker();
    }
  }

  void _handlePrimaryAction() {
    final completionBefore = _engine.completionCount;
    final wasRunning = _engine.isRunning;
    setState(() {
      if (wasRunning) {
        _engine.pause();
      } else {
        _engine.start();
      }
    });
    final completed = _engine.completionCount != completionBefore;
    if (completed) {
      widget.onCountdownCompleted?.call();
    }
    if (_isCountdown && !completed) {
      _notifyDeadline(
        _engine.isCountdownRunning ? _deadlineFromRemaining() : null,
      );
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _handleReset() {
    final wasCountdown = _isCountdown;
    setState(_engine.reset);
    if (wasCountdown) {
      _notifyDeadline(null);
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _handleLap() {
    setState(_engine.addLap);
    _persistSnapshot();
  }

  void _handleRepeat() {
    var started = false;
    setState(() {
      started = _engine.repeatCountdown();
    });
    if (!started) {
      return;
    }
    _notifyDeadline(_deadlineFromRemaining());
    _syncTicker();
    _persistSnapshot();
  }

  /// Switches the visible mode without clearing either measurement.
  ///
  /// A running countdown keeps its scheduled alert and keeps counting while
  /// the stopwatch is shown; the stopwatch keeps its elapsed time and laps.
  void _handleModeSelection(ClockMode mode) {
    if (mode == _engine.mode) {
      return;
    }
    setState(() => _engine.setMode(mode));
    _syncTicker();
    _persistSnapshot();
  }

  Future<void> _handlePresetSelected(ClockPreset preset) async {
    if (_engine.countdownHasProgress || _engine.isCountdownRunning) {
      final confirmed = await _confirmDiscard(
        title: 'Use ${preset.label}?',
        message: 'The countdown progress will be cleared. '
            'The stopwatch keeps its time and laps.',
        actionLabel: 'Use preset',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    var selected = false;
    setState(() {
      selected = _engine.selectPreset(preset.id);
    });
    if (!selected) {
      return;
    }
    _notifyDeadline(null);
    _syncTicker();
    _persistSnapshot();
  }

  Future<void> _confirmDeletePreset(ClockPreset preset) async {
    final confirmed = await _confirmDiscard(
      title: 'Delete ${preset.label}?',
      message: 'The saved preset will be removed. '
          'A countdown that is already running keeps its duration.',
      actionLabel: 'Delete',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _engine.deletePreset(preset.id));
    _persistSnapshot();
  }

  Future<void> _showDurationEditor() async {
    if (_engine.countdownHasProgress || _engine.isCountdownRunning) {
      final confirmed = await _confirmDiscard(
        title: 'Replace the countdown?',
        message: 'The current countdown progress will be cleared. '
            'The stopwatch keeps its time and laps.',
        actionLabel: 'Replace',
      );
      if (!confirmed) {
        return;
      }
      if (!mounted) {
        return;
      }
    }
    final initial = _engine.countdownDuration;
    final duration = await showDialog<Duration>(
      context: context,
      builder: (BuildContext dialogContext) => _DurationEditorDialog(
        initialDuration: initial,
      ),
    );
    if (duration == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _engine.setCountdownDuration(duration));
    _notifyDeadline(null);
    _syncTicker();
    _persistSnapshot();
  }

  Future<void> _showAddPreset() async {
    final draft = await showDialog<_PresetDraft>(
      context: context,
      builder: (BuildContext dialogContext) => _PresetEditorDialog(
        title: 'New preset',
        initialLabel: '',
        initialDuration: _engine.countdownDuration,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _engine.addPreset(label: draft.label, duration: draft.duration);
    });
    _persistSnapshot();
  }

  Future<void> _showEditPreset(ClockPreset preset) async {
    final draft = await showDialog<_PresetDraft>(
      context: context,
      builder: (BuildContext dialogContext) => _PresetEditorDialog(
        title: 'Edit preset',
        initialLabel: preset.label,
        initialDuration: Duration(microseconds: preset.durationMicros),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _engine.updatePreset(
        id: preset.id,
        label: draft.label,
        duration: draft.duration,
      );
    });
    _persistSnapshot();
  }

  void _notifyDeadline(DateTime? deadline) {
    final callback = widget.onCountdownDeadlineChanged;
    if (callback == null) {
      return;
    }
    unawaited(callback(deadline));
  }

  DateTime _wallNowUtc() => (widget.wallClock ?? DateTime.now)().toUtc();

  DateTime? _deadlineFromRemaining() {
    if (!_engine.isCountdownRunning) {
      return null;
    }
    return _wallNowUtc().add(_engine.remaining);
  }

  void _persistSnapshot() {
    final value = _engine.snapshot();
    if (value == _lastSnapshot) {
      return;
    }
    _lastSnapshot = value;
    unawaited(_writeSnapshot(value));
  }

  Future<void> _writeSnapshot(String value) async {
    try {
      await widget.onSnapshot(value);
      if (mounted && _saveFailed && _lastSnapshot == value) {
        setState(() => _saveFailed = false);
      }
    } catch (_) {
      if (_lastSnapshot == value) {
        _lastSnapshot = null;
      }
      if (!mounted || _lastSnapshot != null) {
        return;
      }
      setState(() => _saveFailed = true);
    }
  }

  Future<bool> _confirmDiscard({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  String get _displayTime {
    if (_engine.mode == ClockMode.stopwatch) {
      return formatClock(_engine.elapsed, tenths: true);
    }
    return formatClock(_engine.remaining);
  }

  String get _primaryLabel {
    if (_engine.isRunning) {
      return 'Pause';
    }
    if (_isCountdown && _engine.isCountdownComplete) {
      return 'Start';
    }
    if (_engine.elapsed > Duration.zero) {
      return 'Resume';
    }
    return 'Start';
  }

  String get _statusLabel {
    if (_isCountdown && _engine.isCountdownComplete) {
      return 'Complete';
    }
    if (_engine.isRunning) {
      return 'Running';
    }
    if (_engine.elapsed > Duration.zero) {
      return 'Paused';
    }
    return 'Ready';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final laps = _engine.laps;
    final hasLaps = !_isCountdown && laps.isNotEmpty;
    final backgroundTimer = _buildBackgroundTimer(theme);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CompanionTheme.pageInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildModeSelector(),
              if (backgroundTimer != null) ...<Widget>[
                const SizedBox(height: 8),
                backgroundTimer,
              ],
              const SizedBox(height: 12),
              Expanded(
                child: CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(child: _buildHeroCard(theme)),
                    if (_isCountdown)
                      SliverToBoxAdapter(child: _buildCountdownNote(theme))
                    else ...<Widget>[
                      if (hasLaps)
                        SliverToBoxAdapter(child: _buildLapHeader(theme)),
                      if (!hasLaps)
                        SliverToBoxAdapter(child: _buildLapEmpty(theme))
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (BuildContext context, int index) {
                              final lap = laps[laps.length - 1 - index];
                              return Column(
                                children: <Widget>[
                                  if (index > 0) const Divider(height: 1),
                                  _buildLapRow(theme, lap),
                                ],
                              );
                            },
                            childCount: laps.length,
                          ),
                        ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildBackgroundTimer(ThemeData theme) {
    if (!_isCountdown &&
        (_engine.isCountdownRunning || _engine.countdownHasProgress)) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          key: ClockPage.hiddenCountdownKey,
          onPressed: () => _handleModeSelection(ClockMode.countdown),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
          icon: const Icon(Icons.hourglass_bottom, size: 18),
          label: Text('Countdown ${formatClock(_engine.remaining)}'),
        ),
      );
    }
    if (_isCountdown &&
        (_engine.isStopwatchRunning || _engine.stopwatchHasProgress)) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          key: ClockPage.hiddenStopwatchKey,
          onPressed: () => _handleModeSelection(ClockMode.stopwatch),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
          icon: const Icon(Icons.timer_outlined, size: 18),
          label: Text(
            'Stopwatch ${formatClock(_engine.stopwatchElapsed, tenths: true)}',
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildModeSelector() {
    return SegmentedButton<ClockMode>(
      segments: const <ButtonSegment<ClockMode>>[
        ButtonSegment<ClockMode>(
          value: ClockMode.stopwatch,
          icon: Icon(Icons.timer_outlined, size: 18),
          label: Text('Stopwatch'),
        ),
        ButtonSegment<ClockMode>(
          value: ClockMode.countdown,
          icon: Icon(Icons.hourglass_bottom, size: 18),
          label: Text('Countdown'),
        ),
      ],
      selected: <ClockMode>{_engine.mode},
      onSelectionChanged: (Set<ClockMode> selection) {
        if (selection.isNotEmpty) {
          _handleModeSelection(selection.first);
        }
      },
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _buildHeroCard(ThemeData theme) {
    final colors = theme.colorScheme;
    final hasLaps = !_isCountdown && _engine.laps.isNotEmpty;
    final readoutSize = hasLaps ? 44.0 : 64.0;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _isCountdown
                    ? Icons.hourglass_bottom
                    : Icons.timer_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isCountdown ? 'Countdown' : 'Stopwatch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (_isCountdown)
                TextButton.icon(
                  key: ClockPage.setDurationKey,
                  onPressed: _showDurationEditor,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Duration'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else if (hasLaps)
                Text(
                  '${_engine.laps.length} laps',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _displayTime,
                key: ClockPage.timeKey,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: readoutSize,
                  height: 1,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (_isCountdown) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              'of ${formatClock(_engine.countdownDuration)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickDurations(),
          ],
          const SizedBox(height: 14),
          _buildActions(),
          if (_saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Could not save the clock. Try again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickDurations() {
    // A horizontal scroller sizes to the chips, so large text grows the row
    // instead of overflowing a fixed height.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final preset in _engine.presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PresetChip(
                preset: preset,
                selected: _engine.selectedPresetId == preset.id,
                onSelected: () => unawaited(_handlePresetSelected(preset)),
                onEdit: () => unawaited(_showEditPreset(preset)),
                onDelete: () => unawaited(_confirmDeletePreset(preset)),
              ),
            ),
          _NewPresetChip(onPressed: _showAddPreset),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canReset = _engine.hasProgress || _engine.isRunning;
    return Row(
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: _RoundAction(
              buttonKey: ClockPage.resetActionKey,
              tooltip: 'Reset',
              icon: Icons.refresh,
              label: 'Reset',
              onPressed: canReset ? _handleReset : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: ClockPage.primaryActionKey,
          onPressed: _handlePrimaryAction,
          style: FilledButton.styleFrom(
            minimumSize: const Size(140, 56),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: const StadiumBorder(),
          ),
          icon: Icon(
            _engine.isRunning ? Icons.pause : Icons.play_arrow,
            size: 24,
          ),
          label: Text(_primaryLabel),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: _isCountdown
                ? _RoundAction(
                    buttonKey: ClockPage.repeatActionKey,
                    tooltip: 'Repeat',
                    icon: Icons.replay,
                    label: 'Repeat',
                    onPressed:
                        _engine.isCountdownComplete ? _handleRepeat : null,
                  )
                : _RoundAction(
                    buttonKey: ClockPage.lapActionKey,
                    tooltip: 'Lap',
                    icon: Icons.flag_outlined,
                    label: 'Lap',
                    onPressed: _engine.isRunning ? _handleLap : null,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLapHeader(ThemeData theme) {
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 64, child: Text('Lap', style: style)),
          Expanded(
            child: Text('Split', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Total', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }

  Widget _buildLapEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Laps appear here when you record one.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildLapRow(ThemeData theme, ClockLap lap) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              'Lap ${lap.index}',
              style: style?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              formatClock(
                Duration(microseconds: lap.splitMicros),
                tenths: true,
              ),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              formatClock(
                Duration(microseconds: lap.totalMicros),
                tenths: true,
              ),
              textAlign: TextAlign.right,
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownNote(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Presets are optional. A one-off duration is never saved.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _PresetAction { edit, delete }

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton.outlined(
          key: buttonKey,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
  });

  final ClockPreset preset;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    final muted = selected
        ? colors.onPrimary.withValues(alpha: 0.72)
        : colors.onSurfaceVariant;

    return Material(
      color: selected ? colors.primary : colors.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.timer_outlined, size: 18, color: foreground),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    preset.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatClock(
                      Duration(microseconds: preset.durationMicros),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
              PopupMenuButton<_PresetAction>(
                tooltip: 'Preset options for ${preset.label}',
                icon: Icon(Icons.more_vert, size: 18, color: muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 152),
                onSelected: (_PresetAction action) {
                  if (action == _PresetAction.edit) {
                    onEdit();
                  } else {
                    onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<_PresetAction>>[
                  PopupMenuItem<_PresetAction>(
                    value: _PresetAction.edit,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem<_PresetAction>(
                    value: _PresetAction.delete,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPresetChip extends StatelessWidget {
  const _NewPresetChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: colors.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ClockPage.addPresetKey,
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.add, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Preset',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationEditorDialog extends StatefulWidget {
  const _DurationEditorDialog({required this.initialDuration});

  final Duration initialDuration;

  @override
  State<_DurationEditorDialog> createState() => _DurationEditorDialogState();
}

class _DurationEditorDialogState extends State<_DurationEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours = TextEditingController(
    text: '${widget.initialDuration.inHours}',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: '${widget.initialDuration.inMinutes % Duration.minutesPerHour}',
  );
  late final TextEditingController _seconds = TextEditingController(
    text: '${widget.initialDuration.inSeconds % Duration.secondsPerMinute}',
  );

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Duration? _readDuration() {
    final hours = _readUnit(_hours);
    final minutes = _readUnit(_minutes);
    final seconds = _readUnit(_seconds);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_readDuration());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // A soft keyboard, a short screen or large text must never overflow the
      // dialog; the fields scroll instead.
      scrollable: true,
      title: const Text('Set countdown'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Enter an exact duration. It applies immediately and is not '
              'saved as a preset.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _DurationFields(
              hours: _hours,
              minutes: _minutes,
              seconds: _seconds,
            ),
            _DurationTotalField(readDuration: _readDuration),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ClockPage.durationSubmitKey,
          onPressed: _submit,
          child: const Text('Set'),
        ),
      ],
    );
  }
}

class _PresetEditorDialog extends StatefulWidget {
  const _PresetEditorDialog({
    required this.title,
    required this.initialLabel,
    required this.initialDuration,
  });

  final String title;
  final String initialLabel;
  final Duration initialDuration;

  @override
  State<_PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<_PresetEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _label = TextEditingController(
    text: widget.initialLabel,
  );
  late final TextEditingController _hours = TextEditingController(
    text: '${widget.initialDuration.inHours}',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: '${widget.initialDuration.inMinutes % Duration.minutesPerHour}',
  );
  late final TextEditingController _seconds = TextEditingController(
    text: '${widget.initialDuration.inSeconds % Duration.secondsPerMinute}',
  );

  @override
  void dispose() {
    _label.dispose();
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Duration? _readDuration() {
    final hours = _readUnit(_hours);
    final minutes = _readUnit(_minutes);
    final seconds = _readUnit(_seconds);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final duration = _readDuration();
    if (duration == null) {
      return;
    }
    Navigator.of(context).pop(
      _PresetDraft(label: _label.text, duration: duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              key: ClockPage.presetLabelKey,
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Preset name (optional)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _DurationFields(
              hours: _hours,
              minutes: _minutes,
              seconds: _seconds,
            ),
            _DurationTotalField(readDuration: _readDuration),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ClockPage.presetSubmitKey,
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DurationFields extends StatelessWidget {
  const _DurationFields({
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  final TextEditingController hours;
  final TextEditingController minutes;
  final TextEditingController seconds;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      TextFormField(
        key: ClockPage.hoursFieldKey,
        controller: hours,
        decoration: const InputDecoration(labelText: 'Hours'),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        validator: (String? value) => _validateUnit(value, maximum: 24),
      ),
      TextFormField(
        key: ClockPage.minutesFieldKey,
        controller: minutes,
        decoration: const InputDecoration(labelText: 'Minutes'),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        validator: (String? value) => _validateUnit(value, maximum: 59),
      ),
      TextFormField(
        key: ClockPage.secondsFieldKey,
        controller: seconds,
        decoration: const InputDecoration(labelText: 'Seconds'),
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        validator: (String? value) => _validateUnit(value, maximum: 59),
      ),
    ];
    // AlertDialog asks its content for intrinsic dimensions before it lays
    // anything out, so a LayoutBuilder cannot be used here. The three labelled
    // fields give the dialog an intrinsic width near 336dp, it insets itself
    // by 40dp on each side, and its content padding is 24dp per side.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = math.min(screenWidth - 80, 336.0) - 48;
    if (contentWidth < 216 * textScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < fields.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 8),
            fields[index],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: fields[0]),
        const SizedBox(width: 8),
        Expanded(child: fields[1]),
        const SizedBox(width: 8),
        Expanded(child: fields[2]),
      ],
    );
  }
}

class _DurationTotalField extends StatelessWidget {
  const _DurationTotalField({required this.readDuration});

  final Duration? Function() readDuration;

  @override
  Widget build(BuildContext context) {
    return FormField<Duration>(
      validator: (_) {
        final duration = readDuration();
        if (duration == null) {
          return 'Enter whole numbers for hours, minutes and seconds.';
        }
        final micros = duration.inMicroseconds;
        if (micros < Duration.microsecondsPerSecond) {
          return 'Choose at least 1 second.';
        }
        if (micros > 24 * Duration.microsecondsPerHour) {
          return 'Keep the duration at 24 hours or less.';
        }
        return null;
      },
      builder: (FormFieldState<Duration> state) {
        if (!state.hasError) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            state.errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}

int? _readUnit(TextEditingController controller) {
  final text = controller.text.trim();
  if (text.isEmpty) {
    return 0;
  }
  return int.tryParse(text);
}

String? _validateUnit(String? value, {required int maximum}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0 || parsed > maximum) {
    return '0-$maximum';
  }
  return null;
}

class _PresetDraft {
  const _PresetDraft({required this.label, required this.duration});

  final String label;
  final Duration duration;
}
