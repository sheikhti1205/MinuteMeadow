import 'dart:async';

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

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> with WidgetsBindingObserver {
  late final ClockEngine _engine;
  Timer? _ticker;
  String? _lastSnapshot;
  bool _saveFailed = false;

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
    if (_engine.mode == ClockMode.countdown && _engine.isRunning) {
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
    } else if (_engine.mode == ClockMode.countdown && _engine.isRunning) {
      _notifyDeadline(_deadlineFromRemaining());
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _syncTicker() {
    if (_engine.isRunning) {
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
    if (!_engine.isRunning) {
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
    if (_engine.mode == ClockMode.countdown && !completed) {
      _notifyDeadline(
        _engine.isRunning ? _deadlineFromRemaining() : null,
      );
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _handleReset() {
    setState(_engine.reset);
    if (_engine.mode == ClockMode.countdown) {
      _notifyDeadline(null);
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _handleLap() {
    setState(_engine.addLap);
    _persistSnapshot();
  }

  Future<void> _handleModeSelection(ClockMode mode) async {
    if (mode == _engine.mode) {
      return;
    }
    if (_hasDiscardableProgress) {
      final modeLabel =
          mode == ClockMode.stopwatch ? 'stopwatch' : 'countdown';
      final confirmed = await _confirmDiscard(
        title: 'Switch to $modeLabel?',
        message: _engine.mode == ClockMode.stopwatch
            ? 'The stopwatch time and laps will be cleared.'
            : 'The countdown progress will be cleared.',
        actionLabel: 'Switch',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    final previous = _engine.mode;
    setState(() => _engine.setMode(mode));
    if (previous == ClockMode.countdown) {
      _notifyDeadline(null);
    }
    _syncTicker();
    _persistSnapshot();
  }

  Future<void> _handlePresetSelected(String id, String label) async {
    if (_hasDiscardableProgress) {
      final confirmed = await _confirmDiscard(
        title: 'Use $label?',
        message: _engine.mode == ClockMode.stopwatch
            ? 'The stopwatch time and laps will be cleared.'
            : 'The countdown progress will be cleared.',
        actionLabel: 'Use preset',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    var selected = false;
    setState(() {
      selected = _engine.selectPreset(id);
    });
    if (!selected) {
      return;
    }
    if (_engine.mode == ClockMode.countdown) {
      _notifyDeadline(null);
    }
    _syncTicker();
    _persistSnapshot();
  }

  void _handlePresetDeleted(String id) {
    setState(() => _engine.deletePreset(id));
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
    if (!_engine.isRunning || _engine.mode != ClockMode.countdown) {
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

  bool get _hasDiscardableProgress =>
      _engine.hasProgress || _engine.isRunning;

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
    if (_engine.elapsed > Duration.zero && !_engine.isComplete) {
      return 'Resume';
    }
    return 'Start';
  }

  String get _statusLabel {
    if (_engine.mode == ClockMode.countdown && _engine.isComplete) {
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
    final displayStyle = theme.textTheme.displayLarge?.copyWith(
      fontSize: 64,
      height: 1,
      color: theme.colorScheme.onSurface,
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CompanionTheme.pageInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: SegmentedButton<ClockMode>(
                  segments: const <ButtonSegment<ClockMode>>[
                    ButtonSegment<ClockMode>(
                      value: ClockMode.stopwatch,
                      label: Text('Stopwatch'),
                    ),
                    ButtonSegment<ClockMode>(
                      value: ClockMode.countdown,
                      label: Text('Countdown'),
                    ),
                  ],
                  selected: <ClockMode>{_engine.mode},
                  onSelectionChanged: (Set<ClockMode> selection) {
                    if (selection.isNotEmpty) {
                      unawaited(_handleModeSelection(selection.first));
                    }
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _displayTime,
                  key: ClockPage.timeKey,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: displayStyle,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _statusLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_engine.mode == ClockMode.countdown) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  'of ${formatClock(_engine.countdownDuration)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    key: ClockPage.primaryActionKey,
                    onPressed: _handlePrimaryAction,
                    icon: Icon(
                      _engine.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(_primaryLabel),
                  ),
                  IconButton.outlined(
                    tooltip: 'Reset',
                    onPressed: _engine.hasProgress ? _handleReset : null,
                    icon: const Icon(Icons.refresh),
                  ),
                  if (_engine.mode == ClockMode.stopwatch)
                    IconButton.outlined(
                      tooltip: 'Lap',
                      onPressed: _engine.isRunning ? _handleLap : null,
                      icon: const Icon(Icons.flag_outlined),
                    ),
                ],
              ),
              if (_saveFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Could not save the clock. Try again.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: _engine.mode == ClockMode.stopwatch
                    ? _buildLaps(theme)
                    : _buildPresets(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLaps(ThemeData theme) {
    final laps = _engine.laps;
    if (laps.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Laps appear here when you record one.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(width: 64, child: Text('Lap', style: headerStyle)),
              Expanded(
                child: Text(
                  'Split',
                  textAlign: TextAlign.right,
                  style: headerStyle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Total',
                  textAlign: TextAlign.right,
                  style: headerStyle,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: laps.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final lap = laps[laps.length - 1 - index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: <Widget>[
                    SizedBox(width: 64, child: Text('Lap ${lap.index}')),
                    Expanded(
                      child: Text(
                        formatClock(
                          Duration(microseconds: lap.splitMicros),
                          tenths: true,
                        ),
                        textAlign: TextAlign.right,
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
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresets(ThemeData theme) {
    final presets = _engine.presets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Presets', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _showAddPresetDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add preset'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: presets.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No presets yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final preset in presets)
                        InputChip(
                          label: Text(preset.label),
                          selected: _engine.selectedPresetId == preset.id,
                          onSelected: (_) => unawaited(
                            _handlePresetSelected(preset.id, preset.label),
                          ),
                          onDeleted: () => _handlePresetDeleted(preset.id),
                          deleteButtonTooltipMessage:
                              'Delete ${preset.label}',
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showAddPresetDialog() async {
    final draft = await showDialog<_PresetDraft>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddPresetDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _engine.addPreset(
        label: draft.label,
        duration: Duration(minutes: draft.minutes),
      );
    });
    _persistSnapshot();
  }
}

/// Owns its text controllers so they outlive the dialog's pop animation.
///
/// Disposing them in [_ClockPageState] as soon as `showDialog` resolved left
/// the still-animating fields listening to disposed controllers.
class _AddPresetDialog extends StatefulWidget {
  const _AddPresetDialog();

  @override
  State<_AddPresetDialog> createState() => _AddPresetDialogState();
}

class _AddPresetDialogState extends State<_AddPresetDialog> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController(
    text: '10',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _labelController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _PresetDraft(
        label: _labelController.text,
        minutes: int.parse(_minutesController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // A soft keyboard, a short screen or large text must never overflow the
      // dialog; the fields scroll instead.
      scrollable: true,
      title: const Text('Add countdown preset'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minutesController,
              decoration: const InputDecoration(labelText: 'Minutes'),
              keyboardType: TextInputType.number,
              validator: _validateMinutes,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

String? _validateMinutes(String? value) {
  final minutes = int.tryParse((value ?? '').trim());
  if (minutes == null || minutes < 1 || minutes > 1440) {
    return 'Enter 1-1440 minutes';
  }
  return null;
}

class _PresetDraft {
  const _PresetDraft({required this.label, required this.minutes});

  final String label;
  final int minutes;
}
