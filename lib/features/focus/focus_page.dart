import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/time/timer_defaults.dart';
import 'focus_engine.dart';
import 'focus_stage.dart';
import 'slide_to_quit.dart';

export 'focus_engine.dart';

/// Focus and break timer surface for the shell.
///
/// The page owns only its engine and ticker. Session records and persisted
/// snapshots belong to the host through [onOutcome] and [onSnapshot]. The shell
/// owns the app header, settings entry and bottom navigation; [onImmersiveChanged]
/// tells it when the active focus layout should take over the screen.
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
    this.companionStageBuilder,
    this.onImmersiveChanged,
    this.onConfigureTimers,
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

  /// Draws the companion inside the central stage. The shell supplies this
  /// once its renderer is wired to the Focus destination.
  final WidgetBuilder? companionStageBuilder;

  /// Reports whether the shell should hide its header and bottom navigation.
  /// True for a running or paused focus session, false at terminal and idle
  /// states. Notifications are delivered after a frame, never during build.
  final ValueChanged<bool>? onImmersiveChanged;

  /// Opens the shell's existing timer settings surface. The page never edits
  /// durations or storage itself; when null, the home's duration line stays
  /// plain text and no configuration control is shown.
  final VoidCallback? onConfigureTimers;

  static const timeKey = Key('focus-time');
  static const timeSemanticsKey = Key('focus-time-semantics');
  static const primaryActionKey = Key('focus-primary-action');
  static const stageKey = Key('focus-stage');
  static const closeActionKey = Key('focus-close-action');
  static const slideToQuitKey = Key('focus-slide-to-quit');
  static const configureTimersKey = Key('focus-configure-timers');

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
  bool _confirmingCancel = false;

  bool? _publishedImmersive;
  bool _immersivePublishScheduled = false;

  FocusSettings get _selectedSettings => _preset.settings(widget.settings.value);

  bool get _isImmersive =>
      _engine.phase == FocusPhase.focus && _engine.hasActiveSession;

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
    if (oldWidget.onImmersiveChanged == null &&
        widget.onImmersiveChanged != null) {
      // A host that wires its listener after construction still receives the
      // current requirement once. Re-publishing on every new closure would
      // loop, so only the first non-null listener resets the mark.
      _publishedImmersive = null;
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

  /// Returns true only when the session was actually cancelled, so the slide
  /// control can snap back after "Keep going".
  Future<bool> _confirmCancel() async {
    if (_confirmingCancel || !_engine.hasActiveSession) return false;
    setState(() => _confirmingCancel = true);
    try {
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
      if (confirmed != true || !mounted || !_engine.hasActiveSession) {
        return false;
      }

      final outcome = _engine.cancel();
      setState(() {});
      unawaited(_finish(outcome));
      return true;
    } finally {
      if (mounted) setState(() => _confirmingCancel = false);
    }
  }

  void _selectPreset(FocusPreset preset) {
    if (_pendingOutcome != null ||
        _engine.hasActiveSession ||
        _preset == preset) {
      return;
    }
    setState(() {
      _preset = preset;
      _engine.updateSettings(_selectedSettings);
    });
    _persist(allowTerminal: true);
  }

  void _persist({bool allowTerminal = false}) {
    if (_pendingOutcome != null ||
        (!allowTerminal &&
            (_engine.status == FocusStatus.completed ||
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

  /// Publishes the immersive requirement after the current frame, so a host
  /// that hides its navigation in response never rebuilds during our build.
  void _scheduleImmersivePublish() {
    if (_immersivePublishScheduled || _publishedImmersive == _isImmersive) {
      return;
    }
    if (widget.onImmersiveChanged == null) {
      _publishedImmersive = _isImmersive;
      return;
    }
    _immersivePublishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _immersivePublishScheduled = false;
      if (!mounted) return;
      final value = _isImmersive;
      if (_publishedImmersive == value) return;
      _publishedImmersive = value;
      widget.onImmersiveChanged?.call(value);
    });
  }

  ({String label, IconData icon, VoidCallback onPressed}) get _primaryAction {
    switch (_engine.status) {
      case FocusStatus.idle:
      case FocusStatus.ready:
      case FocusStatus.cancelled:
        return (
          label: 'Start focus',
          icon: Icons.play_arrow_rounded,
          onPressed: _startFocus,
        );
      case FocusStatus.running:
        return (label: 'Pause', icon: Icons.pause_rounded, onPressed: _pause);
      case FocusStatus.paused:
        return (label: 'Resume', icon: Icons.play_arrow_rounded, onPressed: _resume);
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
          icon: Icons.play_arrow_rounded,
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
        onPressed: () => unawaited(_confirmCancel()),
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
    final scheme = Theme.of(context).colorScheme;
    _scheduleImmersivePublish();
    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: _isImmersive
            ? _buildImmersive(context, scheme)
            : _buildStandard(context, scheme),
      ),
    );
  }

  Widget _buildStandard(BuildContext context, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageExtent = _stageExtent(constraints);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 40),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: stageExtent,
                        height: stageExtent,
                        child: _buildStage(scheme),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ..._standardContent(context, scheme),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImmersive(BuildContext context, ColorScheme scheme) {
    final primary = _primaryAction;
    final savePending = _pendingOutcome != null;
    final locked = savePending || _confirmingCancel;
    final theme = Theme.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _RoundAction(
                      key: FocusPage.closeActionKey,
                      icon: Icons.close_rounded,
                      tooltip: 'End focus session',
                      scheme: scheme,
                      onPressed: locked
                          ? null
                          : () => unawaited(_confirmCancel()),
                    ),
                    const Spacer(),
                    _LabeledAction(
                      key: FocusPage.primaryActionKey,
                      label: primary.label,
                      icon: primary.icon,
                      scheme: scheme,
                      onPressed: locked ? null : primary.onPressed,
                    ),
                  ],
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stageExtent = math.min(
                        constraints.maxWidth,
                        math.max(140.0, constraints.maxHeight * 0.52),
                      );
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: stageExtent,
                                height: stageExtent,
                                child: _buildStage(scheme),
                              ),
                              const SizedBox(height: 24),
                              _buildTime(
                                context,
                                scheme,
                                _engine.remaining,
                                'Time remaining '
                                '${_spokenDuration(_engine.remaining)}',
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 280),
                                child: Text(
                                  _engine.isPaused
                                      ? 'Paused. Continue when you are ready.'
                                      : 'Focus in progress. Keep going.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_snapshotFailed) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Could not save the timer.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _persist(allowTerminal: true),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                    ),
                    child: const Text('Retry save'),
                  ),
                ],
                const SizedBox(height: 8),
                SlideToQuit(
                  key: FocusPage.slideToQuitKey,
                  enabled: !locked,
                  onQuit: _confirmCancel,
                  trackColor: scheme.surfaceContainerHighest,
                  thumbColor: scheme.primary,
                  onThumbColor: scheme.onPrimary,
                  labelColor: scheme.onSurfaceVariant,
                  focusColor: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _standardContent(
    BuildContext context,
    ColorScheme scheme,
  ) {
    final pending = _pendingOutcome != null;
    final locked = pending || _confirmingCancel;
    final theme = Theme.of(context);
    final primary = _primaryAction;
    final secondary = _secondaryAction;
    final terminal = _engine.status == FocusStatus.completed ||
        _engine.status == FocusStatus.cancelled;

    if (terminal) {
      final outcome = _engine.lastOutcome;
      final showCycle = _engine.phase == FocusPhase.focus &&
          _engine.status == FocusStatus.completed;
      final showPresets =
          !_engine.hasActiveSession && secondary == null && !pending;
      return [
        Text(
          _engine.statusLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildTime(
          context,
          scheme,
          outcome?.actual ?? Duration.zero,
          '${_engine.phase.isBreak ? 'Elapsed' : 'Focused'} time '
          '${_spokenDuration(outcome?.actual ?? Duration.zero)}',
        ),
        if (outcome != null) ...[
          const SizedBox(height: 8),
          Text(
            'Planned ${_formatDuration(outcome.intended)} · '
            '${_engine.phase.isBreak ? 'Elapsed' : 'Focused'} '
            '${_formatDuration(outcome.actual)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (showCycle) ...[
          const SizedBox(height: 12),
          _buildCycleLine(theme, scheme),
        ],
        const SizedBox(height: 24),
        _primaryButton(primary, scheme, enabled: !locked),
        if (secondary != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: locked ? null : secondary.onPressed,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(secondary.label),
            style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          ),
        ],
        if (showPresets) ...[
          const SizedBox(height: 16),
          _presetChips(scheme, locked),
        ],
        ..._saveNotice(theme, scheme, pending),
      ];
    }

    if (_engine.hasActiveSession) {
      return [
        Text(
          _engine.statusLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildTime(
          context,
          scheme,
          _engine.remaining,
          'Break time remaining ${_spokenDuration(_engine.remaining)}',
        ),
        const SizedBox(height: 8),
        Text(
          _engine.isPaused
              ? 'Paused. Continue when you are ready.'
              : 'Rest your eyes. This is break time.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton(primary, scheme, enabled: !locked),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: locked ? null : secondary?.onPressed,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: Text(secondary?.label ?? 'Cancel'),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
        ),
        ..._saveNotice(theme, scheme, pending),
      ];
    }

    final config = _selectedSettings;
    return [
      Text(
        _engine.statusLabel,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      _buildTime(
        context,
        scheme,
        _engine.remaining,
        'Focus timer ${_spokenDuration(_engine.remaining)}',
      ),
      const SizedBox(height: 8),
      Text(
        'Focus ${config.focusMinutes}m · '
        'Short ${config.shortBreakMinutes}m · '
        'Long ${config.longBreakMinutes}m',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      if (widget.onConfigureTimers != null) ...[
        const SizedBox(height: 4),
        _configureTimersAction(scheme),
      ],
      const SizedBox(height: 20),
      _presetChips(scheme, locked),
      const SizedBox(height: 24),
      _primaryButton(primary, scheme, enabled: !locked),
      ..._saveNotice(theme, scheme, pending),
    ];
  }

  Widget _buildStage(ColorScheme scheme) {
    return FocusStage(
      key: FocusPage.stageKey,
      builder: widget.companionStageBuilder,
      background: scheme.surfaceContainerLow,
      highlight: scheme.surfaceBright,
      border: scheme.outlineVariant,
    );
  }

  /// Opens the shell's existing timer settings. The Focus page deliberately
  /// owns no second duration editor or storage path.
  Widget _configureTimersAction(ColorScheme scheme) {
    final onConfigure = widget.onConfigureTimers!;
    return Center(
      child: Semantics(
        key: FocusPage.configureTimersKey,
        container: true,
        button: true,
        enabled: true,
        label: 'Edit focus and break durations in settings',
        onTap: onConfigure,
        excludeSemantics: true,
        child: TextButton.icon(
          onPressed: onConfigure,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Edit timers'),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTime(
    BuildContext context,
    ColorScheme scheme,
    Duration duration,
    String semanticsLabel,
  ) {
    return Semantics(
      key: FocusPage.timeSemanticsKey,
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatDuration(duration),
            key: FocusPage.timeKey,
            maxLines: 1,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: scheme.onSurface,
              fontSize: 64,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -1.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(
    ({String label, IconData icon, VoidCallback onPressed}) action,
    ColorScheme scheme, {
    required bool enabled,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: FocusPage.primaryActionKey,
        onPressed: enabled ? action.onPressed : null,
        icon: Icon(action.icon, size: 20),
        label: Text(action.label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }

  Widget _presetChips(ColorScheme scheme, bool disabled) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in FocusPreset.values)
          ChoiceChip(
            label: Text(preset.label),
            selected: _preset == preset,
            showCheckmark: false,
            onSelected: disabled
                ? null
                : (selected) {
                    if (selected) _selectPreset(preset);
                  },
            selectedColor: scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
            side: BorderSide(
              color: _preset == preset
                  ? Colors.transparent
                  : scheme.outlineVariant,
            ),
            labelStyle: TextStyle(
              color: _preset == preset ? scheme.onPrimary : scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            shape: const StadiumBorder(),
          ),
      ],
    );
  }

  Widget _buildCycleLine(ThemeData theme, ColorScheme scheme) {
    final done = _cycleDone;
    return Semantics(
      label: '$done of ${TimerDefaults.sessionsPerCycle} focus sessions completed',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0;
                    index < TimerDefaults.sessionsPerCycle;
                    index++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index < done ? scheme.onSurface : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$done of ${TimerDefaults.sessionsPerCycle} focus sessions',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _saveNotice(
    ThemeData theme,
    ColorScheme scheme,
    bool pending,
  ) {
    if (!pending && !_snapshotFailed) return const [];
    return [
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(
          _savingOutcome ? 'Saving session…' : 'Could not save the timer.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      if (!_savingOutcome)
        TextButton(
          onPressed: pending
              ? () => unawaited(_saveOutcome())
              : () => _persist(allowTerminal: true),
          style: TextButton.styleFrom(foregroundColor: scheme.primary),
          child: const Text('Retry save'),
        ),
    ];
  }

  double _stageExtent(BoxConstraints constraints) {
    final byHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight * 0.36
        : 220.0;
    final widthCap = math.min(constraints.maxWidth, 420.0);
    return math.max(112.0, math.min(widthCap, math.min(280.0, byHeight)));
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.scheme,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final ColorScheme scheme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 22),
        color: scheme.onSurface,
        disabledColor: scheme.onSurfaceVariant,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}

class _LabeledAction extends StatelessWidget {
  const _LabeledAction({
    required this.label,
    required this.icon,
    required this.scheme,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final ColorScheme scheme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
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
