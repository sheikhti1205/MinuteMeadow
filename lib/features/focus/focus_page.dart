import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/time/timer_defaults.dart';
import 'focus_engine.dart';
import 'focus_stage.dart';
import 'slide_to_quit.dart';

export 'focus_engine.dart';

/// Focus and break timer surface for the shell.
///
/// The page owns its engine, ticker and the local focus plan (named presets,
/// one-off plan, auto-advance). Session records and persisted snapshots belong
/// to the host through [onOutcome] and [onSnapshot]. The shell owns the app
/// header, settings entry and bottom navigation; [onImmersiveChanged] tells it
/// when the active focus layout should take over the screen.
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
  /// once its renderer is wired to the Focus destination. When null no stage
  /// is mounted, so ordinary layouts never reserve a blank or demo actor.
  final WidgetBuilder? companionStageBuilder;

  /// Reports whether the shell should hide its header and bottom navigation.
  /// True for a running or paused focus session, false at terminal and idle
  /// states. Notifications are delivered after a frame, never during build.
  final ValueChanged<bool>? onImmersiveChanged;

  /// Opens the shell's existing timer settings surface. In-place plan editing
  /// stays on this page; when null the quiet settings link is not shown.
  final VoidCallback? onConfigureTimers;

  static const timeKey = Key('focus-time');
  static const timeSemanticsKey = Key('focus-time-semantics');
  static const primaryActionKey = Key('focus-primary-action');
  static const secondaryActionKey = Key('focus-secondary-action');
  static const stageKey = Key('focus-stage');
  static const closeActionKey = Key('focus-close-action');
  static const slideToQuitKey = Key('focus-slide-to-quit');
  static const configureTimersKey = Key('focus-configure-timers');
  static const configGridKey = Key('focus-config');
  static const focusDurationKey = Key('focus-config-focus');
  static const shortBreakKey = Key('focus-config-short');
  static const longBreakKey = Key('focus-config-long');
  static const sessionsKey = Key('focus-config-sessions');
  static const presetListKey = Key('focus-preset-list');
  static const managePresetsKey = Key('focus-manage-presets');
  static const autoAdvanceKey = Key('focus-auto-advance');
  static const oneOffPlanKey = Key('focus-one-off');
  static const saveOneOffKey = Key('focus-save-one-off');
  static const discardOneOffKey = Key('focus-discard-one-off');
  static const durationEditorKey = Key('focus-duration-editor');
  static const applyOneOffKey = Key('focus-apply-one-off');
  static const savePresetActionKey = Key('focus-save-preset-action');
  static const updatePresetKey = Key('focus-update-preset');
  static const setDefaultPresetKey = Key('focus-set-default-preset');
  static const presetManagerKey = Key('focus-preset-manager');
  static const newPresetKey = Key('focus-new-preset');
  static const presetNameFieldKey = Key('focus-preset-name');
  static const focusMinutesFieldKey = Key('focus-editor-focus');
  static const shortBreakFieldKey = Key('focus-editor-short');
  static const longBreakFieldKey = Key('focus-editor-long');
  static const sessionsFieldKey = Key('focus-editor-sessions');

  @override
  State<FocusPage> createState() => _FocusPageState();
}

enum _FocusEditorMode { oneOff, savePreset, updatePreset, updatePresetAndDefault }

class _FocusEditorResult {
  const _FocusEditorResult(this.mode, this.settings);

  final _FocusEditorMode mode;
  final FocusSettings settings;
}

class _PresetNameResult {
  const _PresetNameResult(this.name, this.makeDefault);

  final String name;
  final bool makeDefault;
}

enum _PresetMenuAction { edit, rename, duplicate, makeDefault, delete }

class _FocusPageState extends State<FocusPage> with WidgetsBindingObserver {
  late final FocusEngine _engine;
  late FocusPlanState _plan;
  Timer? _ticker;
  ({FocusOutcome outcome, String snapshot, bool autoAdvance})? _pendingOutcome;
  bool _savingOutcome = false;
  bool _snapshotFailed = false;
  bool _confirmingCancel = false;

  bool? _publishedImmersive;
  bool _immersivePublishScheduled = false;

  FocusSettings get _activeSettings => _plan.resolve(widget.settings.value);

  FocusPlanState _restorePlan(FocusSnapshot? saved) {
    final plan = saved?.plan;
    if (plan != null) return plan;
    final selected = saved?.preset;
    if (selected == null ||
        FocusPlanState.initial.presetById(selected.id) == null) {
      return FocusPlanState.initial;
    }
    return FocusPlanState.initial.copyWith(selectedId: selected.id);
  }

  bool get _isImmersive =>
      _engine.phase == FocusPhase.focus && _engine.hasActiveSession;

  String _snapshot() => _engine.snapshot().encode(
    selectedPreset: _plan.presetById(_plan.selectedId),
    plan: _plan,
  );

  @override
  void initState() {
    super.initState();
    final saved = FocusSnapshot.tryDecode(widget.initialSnapshot);
    _plan = _restorePlan(saved);
    _engine = FocusEngine(
      settings: _plan.resolve(widget.settings.value),
      clock: widget.clock,
      restored: saved,
      recoveredAt: widget.recoveryNow,
    )..prepare();
    widget.settings.addListener(_handleSettingsChanged);
    WidgetsBinding.instance.addObserver(this);

    final overdue = _engine.tick();
    if (overdue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_finish(overdue, allowAutoAdvance: false));
        }
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
    setState(() => _engine.updateSettings(_activeSettings));
    if (_engine.status == FocusStatus.idle ||
        _engine.status == FocusStatus.ready) {
      _persist();
    }
    _notifyTimeline();
  }

  void _startFocus() {
    if (_engine.hasActiveSession) return;
    if (_engine.status == FocusStatus.completed &&
        _engine.phase.isBreak &&
        _engine.planFinished) {
      return;
    }
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
    // No outcome is emitted, so persist the between-block state explicitly.
    _afterChange(allowTerminal: true);
  }

  void _endPlan() {
    if (!_engine.hasPlan || _engine.hasActiveSession) return;
    final next = _plan.clearOneOff();
    setState(() {
      _plan = next;
      _engine.endPlan();
      _engine.updateSettings(next.resolve(widget.settings.value));
    });
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

  void _afterChange({bool allowTerminal = false}) {
    _syncTicker();
    _notifyTimeline();
    _persist(allowTerminal: allowTerminal);
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

  Future<void> _finish(
    FocusOutcome outcome, {
    bool allowAutoAdvance = true,
  }) async {
    if (!mounted) return;
    setState(() {
      _pendingOutcome = (
        outcome: outcome,
        snapshot: _snapshot(),
        autoAdvance: allowAutoAdvance,
      );
    });
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
      if (!mounted) return;
      setState(() {
        _pendingOutcome = null;
        _snapshotFailed = false;
      });
      if (pending.autoAdvance &&
          pending.outcome.completed &&
          _plan.autoAdvance &&
          _engine.status == FocusStatus.completed) {
        // One opt-in transition, after the outcome has been stored, so a
        // restart or a failed write can never lose the completed session. The
        // final break never starts another plan.
        if (_engine.phase == FocusPhase.focus) {
          _startBreak();
        } else if (!_engine.planFinished) {
          _startFocus();
        }
      }
    } catch (_) {
      // Keep the terminal snapshot and offer to retry before starting another
      // session. Auto-advance waits for a successful write.
    } finally {
      if (mounted) setState(() => _savingOutcome = false);
    }
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

      final next = _plan.clearOneOff();
      final outcome = _engine.cancel();
      _engine.updateSettings(next.resolve(widget.settings.value));
      setState(() => _plan = next);
      unawaited(_finish(outcome));
      return true;
    } finally {
      if (mounted) setState(() => _confirmingCancel = false);
    }
  }

  void _applyPlan(FocusPlanState next, {bool allowTerminal = false}) {
    if (!mounted) return;
    setState(() {
      _plan = next;
      _engine.updateSettings(next.resolve(widget.settings.value));
    });
    _notifyTimeline();
    _persist(allowTerminal: allowTerminal);
  }

  void _selectPreset(FocusPreset preset) {
    if (_pendingOutcome != null ||
        _engine.hasActiveSession ||
        _engine.hasPlan) {
      return;
    }
    if (_plan.selectedId == preset.id && !_plan.isOneOff) return;
    _applyPlan(_plan.select(preset.id), allowTerminal: true);
  }

  void _applyOneOff(FocusSettings settings) {
    if (_engine.hasPlan) return;
    _applyPlan(_plan.useOneOff(settings), allowTerminal: true);
  }

  void _discardOneOff() {
    if (_engine.hasPlan) return;
    _applyPlan(_plan.clearOneOff(), allowTerminal: true);
  }

  Future<void> _openPlanEditor({
    FocusPreset? preset,
    _EditorField focusField = _EditorField.focus,
  }) async {
    if (!mounted ||
        _engine.hasActiveSession ||
        _engine.hasPlan ||
        _pendingOutcome != null) {
      return;
    }
    final editablePreset = preset?.canEdit == true ? preset : null;
    final initial = editablePreset == null
        ? _activeSettings
        : editablePreset.settings(widget.settings.value);
    final result = await showModalBottomSheet<_FocusEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _FocusPlanEditor(
        key: FocusPage.durationEditorKey,
        initial: initial,
        focusField: focusField,
        title: editablePreset == null
            ? 'Focus plan'
            : 'Edit ${editablePreset.name}',
        editingPreset: editablePreset != null,
        alreadyDefault:
            editablePreset != null && editablePreset.id == _plan.defaultId,
        onCancel: () => Navigator.of(sheetContext).pop(),
        onSubmit: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (result == null || !mounted) return;
    switch (result.mode) {
      case _FocusEditorMode.oneOff:
        _applyOneOff(result.settings);
        break;
      case _FocusEditorMode.savePreset:
        await _promptSavePreset(result.settings);
        break;
      case _FocusEditorMode.updatePreset:
        if (editablePreset != null) {
          _applyPlan(
            _plan.updatePreset(editablePreset.id, result.settings),
            allowTerminal: true,
          );
        }
        break;
      case _FocusEditorMode.updatePresetAndDefault:
        if (editablePreset != null) {
          _applyPlan(
            _plan.updatePreset(
              editablePreset.id,
              result.settings,
              makeDefault: true,
            ),
            allowTerminal: true,
          );
        }
        break;
    }
  }

  Future<void> _promptSavePreset(FocusSettings settings) async {
    final result = await showDialog<_PresetNameResult>(
      context: context,
      builder: (dialogContext) => _PresetNameDialog(
        title: 'Save as preset',
        actionLabel: 'Save preset',
        showMakeDefault: true,
        validator: (name) => _plan.validatePresetName(name),
      ),
    );
    if (result == null || !mounted) return;
    final next = _plan.addPreset(
      result.name,
      settings,
      makeDefault: result.makeDefault,
    );
    if (identical(next, _plan)) return;
    _applyPlan(next, allowTerminal: true);
  }

  Future<void> _promptCreatePreset() async {
    final result = await showDialog<_PresetNameResult>(
      context: context,
      builder: (dialogContext) => _PresetNameDialog(
        title: 'New preset',
        actionLabel: 'Create preset',
        showMakeDefault: true,
        validator: (name) => _plan.validatePresetName(name),
      ),
    );
    if (result == null || !mounted) return;
    final next = _plan.addPreset(
      result.name,
      _activeSettings,
      makeDefault: result.makeDefault,
    );
    if (identical(next, _plan)) return;
    _applyPlan(next, allowTerminal: true);
  }

  Future<void> _promptRenamePreset(FocusPreset preset) async {
    final result = await showDialog<_PresetNameResult>(
      context: context,
      builder: (dialogContext) => _PresetNameDialog(
        title: 'Rename preset',
        actionLabel: 'Rename',
        initialName: preset.name,
        validator: (name) =>
            _plan.validatePresetName(name, exceptId: preset.id),
      ),
    );
    if (result == null || !mounted) return;
    final next = _plan.renamePreset(preset.id, result.name);
    if (identical(next, _plan)) return;
    _applyPlan(next, allowTerminal: true);
  }

  Future<void> _openPresetManager() async {
    if (_pendingOutcome != null || _engine.hasActiveSession || _engine.hasPlan) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _PresetManagerSheet(
        key: FocusPage.presetManagerKey,
        plan: _plan,
        fallback: widget.settings.value,
        onPlanChanged: (next) =>
            _applyPlan(next, allowTerminal: true),
        onClose: () => Navigator.of(sheetContext).pop(),
        onEdit: (preset) {
          Navigator.of(sheetContext).pop();
          unawaited(_openPlanEditor(preset: preset));
        },
        onRename: (preset) {
          Navigator.of(sheetContext).pop();
          unawaited(_promptRenamePreset(preset));
        },
        onCreate: () {
          Navigator.of(sheetContext).pop();
          unawaited(_promptCreatePreset());
        },
      ),
    );
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
        return (
          label: 'Resume',
          icon: Icons.play_arrow_rounded,
          onPressed: _resume,
        );
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
        if (_engine.planFinished) {
          return (
            label: 'Done',
            icon: Icons.done_all_rounded,
            onPressed: _endPlan,
          );
        }
        return (
          label: 'Start next focus',
          icon: Icons.play_arrow_rounded,
          onPressed: _startFocus,
        );
    }
  }

  ({String label, IconData icon, VoidCallback onPressed})? get _secondaryAction {
    if (_engine.status == FocusStatus.completed) {
      if (_engine.phase == FocusPhase.focus) {
        if (_engine.planFinished) {
          return (
            label: 'Done',
            icon: Icons.done_all_rounded,
            onPressed: _endPlan,
          );
        }
        return (
          label: 'Skip break',
          icon: Icons.skip_next_rounded,
          onPressed: _skipBreak,
        );
      }
      if (_engine.planFinished) return null;
      return (
        label: 'End plan',
        icon: Icons.stop_circle_outlined,
        onPressed: _endPlan,
      );
    }
    if (_engine.hasActiveSession) {
      return (
        label: _engine.phase.isBreak ? 'Cancel break' : 'Cancel',
        icon: Icons.close_rounded,
        onPressed: () => unawaited(_confirmCancel()),
      );
    }
    return null;
  }

  int get _cycleDone => _engine.planCompleted;

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
        final stage = _buildStage(scheme);
        final stageExtent = _stageExtent(constraints);
        final children = <Widget>[
          if (stage != null) ...[
            Center(
              child: SizedBox(
                width: stageExtent,
                height: stageExtent,
                child: stage,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ..._standardContent(context, scheme),
        ];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            stage == null ? 20 : 10,
            20,
            20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? math.max(0.0, constraints.maxHeight - 40)
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
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
    final stage = _buildStage(scheme);

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
                        math.max(140.0, constraints.maxHeight * 0.5),
                      );
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (stage != null) ...[
                                SizedBox(
                                  width: stageExtent,
                                  height: stageExtent,
                                  child: stage,
                                ),
                                const SizedBox(height: 24),
                              ],
                              _buildTime(
                                context,
                                scheme,
                                _engine.remaining,
                                'Time remaining '
                                '${_spokenDuration(_engine.remaining)}',
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
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
    final terminal =
        _engine.status == FocusStatus.completed ||
        _engine.status == FocusStatus.cancelled;

    // Between blocks of a finite plan: no elapsed timer and no fake break
    // result. The plan keeps its progress and offers the next block or Done.
    if (_engine.status == FocusStatus.completed && _engine.phase.isBreak) {
      return [
        _statusLine(theme, scheme),
        const SizedBox(height: 12),
        _buildCycleLine(theme, scheme),
        const SizedBox(height: 24),
        _primaryButton(primary, scheme, enabled: !locked),
        if (secondary != null) ...[
          const SizedBox(height: 4),
          _secondaryButton(secondary, scheme, enabled: !locked),
        ],
        ..._saveNotice(theme, scheme, pending),
      ];
    }

    if (terminal) {
      final outcome = _engine.lastOutcome;
      final showCycle =
          _engine.phase == FocusPhase.focus &&
          _engine.status == FocusStatus.completed;
      final showPresets =
          !_engine.hasPlan &&
          !_engine.hasActiveSession &&
          secondary == null &&
          !pending;
      return [
        _statusLine(theme, scheme),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
          _secondaryButton(secondary, scheme, enabled: !locked),
        ],
        if (showPresets) ...[
          const SizedBox(height: 16),
          _presetSection(scheme, enabled: !locked),
        ],
        ..._saveNotice(theme, scheme, pending),
      ];
    }

    if (_engine.hasActiveSession) {
      return [
        _statusLine(theme, scheme),
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
        if (secondary != null) ...[
          const SizedBox(height: 4),
          _secondaryButton(secondary, scheme, enabled: !locked),
        ],
        ..._saveNotice(theme, scheme, pending),
      ];
    }

    return _setupContent(
      context,
      scheme,
      locked: locked,
      primary: primary,
    );
  }

  Widget _statusLine(ThemeData theme, ColorScheme scheme) {
    return Text(
      _engine.statusLabel,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  List<Widget> _setupContent(
    BuildContext context,
    ColorScheme scheme, {
    required bool locked,
    required ({String label, IconData icon, VoidCallback onPressed}) primary,
  }) {
    final theme = Theme.of(context);
    final settings = _activeSettings;
    return [
      _buildSetupTime(context, scheme),
      const SizedBox(height: 14),
      _configGrid(scheme, settings, enabled: !locked),
      const SizedBox(height: 12),
      _presetSection(scheme, enabled: !locked),
      if (_plan.isOneOff) ...[
        const SizedBox(height: 8),
        _oneOffRow(scheme, enabled: !locked),
      ],
      const SizedBox(height: 8),
      _autoAdvanceRow(scheme, enabled: !locked),
      if (widget.onConfigureTimers != null) ...[
        const SizedBox(height: 2),
        _configureTimersAction(scheme),
      ],
      const SizedBox(height: 12),
      _primaryButton(primary, scheme, enabled: !locked),
      ..._saveNotice(theme, scheme, _pendingOutcome != null),
    ];
  }

  Widget _buildSetupTime(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return Semantics(
      key: FocusPage.timeSemanticsKey,
      container: true,
      label:
          '${_engine.statusLabel}. Focus timer '
          '${_spokenDuration(_engine.remaining)}',
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 2,
          children: [
            Text(
              _engine.statusLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _formatDuration(_engine.remaining),
              key: FocusPage.timeKey,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configGrid(
    ColorScheme scheme,
    FocusSettings settings, {
    required bool enabled,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn = constraints.maxWidth < 300;
        final width = oneColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        final tiles = <Widget>[
          _ConfigTile(
            key: FocusPage.focusDurationKey,
            icon: Icons.timer_outlined,
            label: 'Focus',
            value: '${settings.focusMinutes} min',
            onTap: enabled
                ? () => _openPlanEditor(focusField: _EditorField.focus)
                : null,
          ),
          _ConfigTile(
            key: FocusPage.shortBreakKey,
            icon: Icons.coffee_outlined,
            label: 'Short break',
            value: '${settings.shortBreakMinutes} min',
            onTap: enabled
                ? () => _openPlanEditor(focusField: _EditorField.shortBreak)
                : null,
          ),
          _ConfigTile(
            key: FocusPage.longBreakKey,
            icon: Icons.local_cafe_outlined,
            label: 'Long break',
            value: '${settings.longBreakMinutes} min',
            onTap: enabled
                ? () => _openPlanEditor(focusField: _EditorField.longBreak)
                : null,
          ),
          _ConfigTile(
            key: FocusPage.sessionsKey,
            icon: Icons.repeat_rounded,
            label: 'Sessions in plan',
            value: '${settings.sessionsPerCycle} sessions',
            onTap: enabled
                ? () => _openPlanEditor(focusField: _EditorField.sessions)
                : null,
          ),
        ];
        return Wrap(
          key: FocusPage.configGridKey,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  Widget _presetSection(ColorScheme scheme, {required bool enabled}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.bookmarks_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          'Preset',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            key: FocusPage.presetListKey,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in _plan.presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        _presetIcon(preset),
                        size: 17,
                        color: _isPresetSelected(preset)
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                      label: Text(preset.name),
                      selected: _isPresetSelected(preset),
                      showCheckmark: false,
                      onSelected: enabled
                          ? (selected) {
                              if (selected) _selectPreset(preset);
                            }
                          : null,
                      selectedColor: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                      side: BorderSide(
                        color: _isPresetSelected(preset)
                            ? Colors.transparent
                            : scheme.outlineVariant,
                      ),
                      labelStyle: TextStyle(
                        color: _isPresetSelected(preset)
                            ? scheme.onPrimary
                            : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      shape: const StadiumBorder(),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: FocusPage.managePresetsKey,
            tooltip: 'Manage presets',
            onPressed: enabled ? _openPresetManager : null,
            icon: const Icon(Icons.tune_rounded, size: 20),
            color: scheme.onSurface,
            disabledColor: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  bool _isPresetSelected(FocusPreset preset) =>
      _plan.selectedId == preset.id && !_plan.isOneOff;

  Widget _oneOffRow(ColorScheme scheme, {required bool enabled}) {
    final theme = Theme.of(context);
    return Container(
      key: FocusPage.oneOffPlanKey,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One-off plan',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Applies to the next plan only',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: FocusPage.discardOneOffKey,
                tooltip: 'Discard one-off plan',
                onPressed: enabled ? _discardOneOff : null,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: FocusPage.saveOneOffKey,
              onPressed: enabled
                  ? () => unawaited(_promptSavePreset(_activeSettings))
                  : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save as preset'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                minimumSize: const Size(48, 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoAdvanceRow(ColorScheme scheme, {required bool enabled}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SwitchListTile.adaptive(
        key: FocusPage.autoAdvanceKey,
        value: _plan.autoAdvance,
        onChanged: enabled
            ? (value) =>
                  _applyPlan(_plan.withAutoAdvance(value), allowTerminal: true)
            : null,
        secondary: Icon(
          Icons.autorenew_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        title: Text(
          'Auto-start next phase',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Start the break, then the next focus, when time is up.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget? _buildStage(ColorScheme scheme) {
    final builder = widget.companionStageBuilder;
    if (builder == null) return null;
    return FocusStage(
      key: FocusPage.stageKey,
      builder: builder,
      background: scheme.surfaceContainerLow,
      highlight: scheme.surfaceBright,
      border: scheme.outlineVariant,
    );
  }

  /// Opens the shell's existing timer settings. Plan editing stays in place on
  /// this page; this link only reaches the shared defaults and app settings.
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

  Widget _secondaryButton(
    ({String label, IconData icon, VoidCallback onPressed}) action,
    ColorScheme scheme, {
    required bool enabled,
  }) {
    return Center(
      child: TextButton.icon(
        key: FocusPage.secondaryActionKey,
        onPressed: enabled ? action.onPressed : null,
        icon: Icon(action.icon, size: 18),
        label: Text(action.label),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildCycleLine(ThemeData theme, ColorScheme scheme) {
    final done = _cycleDone;
    final target = _engine.planTarget;
    final cycle = target > 0
        ? target
        : (_engine.sessionsPerCycle <= 0
              ? TimerDefaults.sessionsPerCycle
              : _engine.sessionsPerCycle);
    return Semantics(
      label: '$done of $cycle focus sessions completed',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < cycle; index++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index < done
                          ? scheme.onSurface
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$done of $cycle focus sessions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
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
        ? constraints.maxHeight * 0.26
        : 180.0;
    final widthCap = math.min(constraints.maxWidth, 420.0);
    return math.max(112.0, math.min(widthCap, math.min(240.0, byHeight)));
  }

}

enum _EditorField { focus, shortBreak, longBreak, sessions }

IconData _presetIcon(FocusPreset preset) {
  switch (preset.id) {
    case FocusPreset.sprintId:
      return Icons.bolt_outlined;
    case FocusPreset.deepWorkId:
      return Icons.waves_rounded;
    case FocusPreset.defaultsId:
      return Icons.hourglass_empty_rounded;
    default:
      return Icons.bookmark_outline_rounded;
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: '$label, $value',
      hint: enabled ? 'Double tap to edit' : null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
          minimumSize: const Size(112, 48),
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

class _FocusPlanEditor extends StatefulWidget {
  const _FocusPlanEditor({
    required this.initial,
    required this.title,
    required this.editingPreset,
    required this.alreadyDefault,
    required this.onCancel,
    required this.onSubmit,
    this.focusField = _EditorField.focus,
    super.key,
  });

  final FocusSettings initial;
  final String title;
  final bool editingPreset;
  final bool alreadyDefault;
  final _EditorField focusField;
  final VoidCallback onCancel;
  final ValueChanged<_FocusEditorResult> onSubmit;

  @override
  State<_FocusPlanEditor> createState() => _FocusPlanEditorState();
}

class _FocusPlanEditorState extends State<_FocusPlanEditor> {
  late final TextEditingController _focus;
  late final TextEditingController _short;
  late final TextEditingController _long;
  late final TextEditingController _sessions;
  late final FocusNode _focusNode;
  late final FocusNode _shortNode;
  late final FocusNode _longNode;
  late final FocusNode _sessionsNode;

  @override
  void initState() {
    super.initState();
    _focus = TextEditingController(
      text: widget.initial.focusMinutes.toString(),
    );
    _short = TextEditingController(
      text: widget.initial.shortBreakMinutes.toString(),
    );
    _long = TextEditingController(
      text: widget.initial.longBreakMinutes.toString(),
    );
    _sessions = TextEditingController(
      text: widget.initial.sessionsPerCycle.toString(),
    );
    _focusNode = FocusNode();
    _shortNode = FocusNode();
    _longNode = FocusNode();
    _sessionsNode = FocusNode();
    for (final controller in [_focus, _short, _long, _sessions]) {
      controller.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusField) {
        case _EditorField.focus:
          _focusNode.requestFocus();
          break;
        case _EditorField.shortBreak:
          _shortNode.requestFocus();
          break;
        case _EditorField.longBreak:
          _longNode.requestFocus();
          break;
        case _EditorField.sessions:
          _sessionsNode.requestFocus();
          break;
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [_focus, _short, _long, _sessions]) {
      controller.removeListener(_onChanged);
      controller.dispose();
    }
    _focusNode.dispose();
    _shortNode.dispose();
    _longNode.dispose();
    _sessionsNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String? get _focusError => _validate(
    _focus,
    FocusSettings.minFocusMinutes,
    FocusSettings.maxFocusMinutes,
  );
  String? get _shortError => _validate(
    _short,
    FocusSettings.minBreakMinutes,
    FocusSettings.maxBreakMinutes,
  );
  String? get _longError => _validate(
    _long,
    FocusSettings.minBreakMinutes,
    FocusSettings.maxBreakMinutes,
  );
  String? get _sessionsError => _validate(
    _sessions,
    FocusSettings.minSessionsPerCycle,
    FocusSettings.maxSessionsPerCycle,
  );

  String? _validate(TextEditingController controller, int min, int max) {
    final text = controller.text.trim();
    if (text.isEmpty) return 'Required';
    final value = int.tryParse(text);
    if (value == null) return 'Numbers only';
    if (value < min || value > max) return 'Use $min-$max';
    return null;
  }

  FocusSettings? get _settings {
    if (_focusError != null ||
        _shortError != null ||
        _longError != null ||
        _sessionsError != null) {
      return null;
    }
    final settings = FocusSettings(
      focusMinutes: int.parse(_focus.text),
      shortBreakMinutes: int.parse(_short.text),
      longBreakMinutes: int.parse(_long.text),
      sessionsPerCycle: int.parse(_sessions.text),
    );
    return settings.isValid ? settings : null;
  }

  void _step(
    TextEditingController controller,
    int delta,
    int min,
    int max,
  ) {
    final current = int.tryParse(controller.text) ?? min;
    final next = (current + delta).clamp(min, max);
    controller.text = next.toString();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  void _submit(_FocusEditorMode mode) {
    final settings = _settings;
    if (settings == null) {
      FocusScope.of(context).unfocus();
      return;
    }
    widget.onSubmit(_FocusEditorResult(mode, settings));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = _settings;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                widget.editingPreset
                    ? 'Changes are saved to this preset.'
                    : 'Apply once to the next whole plan, or save these values '
                          'as a preset.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _editorRow(
                fieldKey: FocusPage.focusMinutesFieldKey,
                controller: _focus,
                node: _focusNode,
                icon: Icons.timer_outlined,
                label: 'Focus',
                suffix: 'min',
                min: FocusSettings.minFocusMinutes,
                max: FocusSettings.maxFocusMinutes,
                error: _focusError,
                onStep: (delta) => _step(
                  _focus,
                  delta,
                  FocusSettings.minFocusMinutes,
                  FocusSettings.maxFocusMinutes,
                ),
              ),
              _editorRow(
                fieldKey: FocusPage.shortBreakFieldKey,
                controller: _short,
                node: _shortNode,
                icon: Icons.coffee_outlined,
                label: 'Short break',
                suffix: 'min',
                min: FocusSettings.minBreakMinutes,
                max: FocusSettings.maxBreakMinutes,
                error: _shortError,
                onStep: (delta) => _step(
                  _short,
                  delta,
                  FocusSettings.minBreakMinutes,
                  FocusSettings.maxBreakMinutes,
                ),
              ),
              _editorRow(
                fieldKey: FocusPage.longBreakFieldKey,
                controller: _long,
                node: _longNode,
                icon: Icons.local_cafe_outlined,
                label: 'Long break',
                suffix: 'min',
                min: FocusSettings.minBreakMinutes,
                max: FocusSettings.maxBreakMinutes,
                error: _longError,
                onStep: (delta) => _step(
                  _long,
                  delta,
                  FocusSettings.minBreakMinutes,
                  FocusSettings.maxBreakMinutes,
                ),
              ),
              _editorRow(
                fieldKey: FocusPage.sessionsFieldKey,
                controller: _sessions,
                node: _sessionsNode,
                icon: Icons.repeat_rounded,
                label: 'Sessions in plan',
                suffix: null,
                min: FocusSettings.minSessionsPerCycle,
                max: FocusSettings.maxSessionsPerCycle,
                error: _sessionsError,
                onStep: (delta) => _step(
                  _sessions,
                  delta,
                  FocusSettings.minSessionsPerCycle,
                  FocusSettings.maxSessionsPerCycle,
                ),
              ),
              if (settings == null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Check the highlighted values.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.editingPreset) ...[
                FilledButton.icon(
                  key: FocusPage.updatePresetKey,
                  onPressed: settings == null
                      ? null
                      : () => _submit(_FocusEditorMode.updatePreset),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Save preset'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (!widget.alreadyDefault)
                  TextButton.icon(
                    key: FocusPage.setDefaultPresetKey,
                    onPressed: settings == null
                        ? null
                        : () => _submit(
                            _FocusEditorMode.updatePresetAndDefault,
                          ),
                    icon: const Icon(Icons.star_outline_rounded, size: 18),
                    label: const Text('Save and set default'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      minimumSize: const Size(48, 48),
                    ),
                  ),
              ] else ...[
                FilledButton.icon(
                  key: FocusPage.applyOneOffKey,
                  onPressed: settings == null
                      ? null
                      : () => _submit(_FocusEditorMode.oneOff),
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: const Text('Apply once'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: FocusPage.savePresetActionKey,
                  onPressed: settings == null
                      ? null
                      : () => _submit(_FocusEditorMode.savePreset),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save as preset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorRow({
    required Key fieldKey,
    required TextEditingController controller,
    required FocusNode node,
    required IconData icon,
    required String label,
    required String? suffix,
    required int min,
    required int max,
    required String? error,
    required ValueChanged<int> onStep,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onStep(-1),
            tooltip: 'Decrease $label',
            icon: const Icon(Icons.remove_rounded, size: 20),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            color: scheme.onSurface,
          ),
          SizedBox(
            width: 84,
            child: Semantics(
              label: label,
              hint: 'Between $min and $max',
              child: TextField(
                key: fieldKey,
                controller: controller,
                focusNode: node,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  suffixText: suffix,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => onStep(1),
            tooltip: 'Increase $label',
            icon: const Icon(Icons.add_rounded, size: 20),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            color: scheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({
    required this.title,
    required this.actionLabel,
    required this.validator,
    this.initialName,
    this.showMakeDefault = false,
  });

  final String title;
  final String actionLabel;
  final String? initialName;
  final bool showMakeDefault;
  final String? Function(String name) validator;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );
  bool _makeDefault = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      _PresetNameResult(_controller.text.trim(), _makeDefault),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: FocusPage.presetNameFieldKey,
              controller: _controller,
              autofocus: true,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Preset name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) => widget.validator(value ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
            if (widget.showMakeDefault)
              SwitchListTile.adaptive(
                value: _makeDefault,
                onChanged: (value) => setState(() => _makeDefault = value),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.star_outline_rounded),
                title: const Text('Make this the default'),
                subtitle: Text(
                  'Kept as the safe fallback.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

class _PresetManagerSheet extends StatefulWidget {
  const _PresetManagerSheet({
    required this.plan,
    required this.fallback,
    required this.onPlanChanged,
    required this.onClose,
    required this.onEdit,
    required this.onRename,
    required this.onCreate,
    super.key,
  });

  final FocusPlanState plan;
  final FocusSettings fallback;
  final ValueChanged<FocusPlanState> onPlanChanged;
  final VoidCallback onClose;
  final ValueChanged<FocusPreset> onEdit;
  final ValueChanged<FocusPreset> onRename;
  final VoidCallback onCreate;

  @override
  State<_PresetManagerSheet> createState() => _PresetManagerSheetState();
}

class _PresetManagerSheetState extends State<_PresetManagerSheet> {
  late FocusPlanState _plan = widget.plan;

  void _change(FocusPlanState next) {
    if (identical(next, _plan)) return;
    setState(() => _plan = next);
    widget.onPlanChanged(next);
  }

  void _handleMenu(_PresetMenuAction action, FocusPreset preset) {
    switch (action) {
      case _PresetMenuAction.edit:
        widget.onEdit(preset);
        break;
      case _PresetMenuAction.rename:
        widget.onRename(preset);
        break;
      case _PresetMenuAction.duplicate:
        _change(
          _plan.duplicatePreset(preset.id, fallback: widget.fallback),
        );
        break;
      case _PresetMenuAction.makeDefault:
        _change(_plan.setDefault(preset.id));
        break;
      case _PresetMenuAction.delete:
        unawaited(_confirmDelete(preset));
        break;
    }
  }

  Future<void> _confirmDelete(FocusPreset preset) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${preset.name}?'),
        content: const Text(
          'The preset is removed. Recorded focus sessions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep preset'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _change(_plan.deletePreset(preset.id));
  }

  String _summary(FocusPreset preset) {
    final settings = preset.fixed
        ? widget.fallback
        : preset.presetSettings;
    return '${settings.focusMinutes} / ${settings.shortBreakMinutes} / '
        '${settings.longBreakMinutes} min · '
        '${settings.sessionsPerCycle} sessions';
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(label),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Presets',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Default: ${_plan.defaultPreset.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: FocusPage.newPresetKey,
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: _plan.presets.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: scheme.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final preset = _plan.presets[index];
                final isDefault = preset.id == _plan.defaultId;
                final selected =
                    preset.id == _plan.selectedId && !_plan.isOneOff;
                return ListTile(
                  key: ValueKey('focus-preset-row-${preset.id}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    _presetIcon(preset),
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          preset.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Default',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    _summary(preset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 22,
                          color: scheme.primary,
                        )
                      else
                        IconButton(
                          tooltip: 'Use ${preset.name}',
                          onPressed: () {
                            _change(_plan.select(preset.id));
                            widget.onClose();
                          },
                          icon: const Icon(Icons.check_rounded, size: 20),
                          color: scheme.onSurfaceVariant,
                        ),
                      PopupMenuButton<_PresetMenuAction>(
                        key: ValueKey('focus-preset-menu-${preset.id}'),
                        tooltip: 'Actions for ${preset.name}',
                        onSelected: (action) => _handleMenu(action, preset),
                        itemBuilder: (context) => [
                          if (preset.canEdit)
                            PopupMenuItem(
                              value: _PresetMenuAction.edit,
                              child: _menuRow(
                                Icons.edit_outlined,
                                'Edit values',
                              ),
                            ),
                          if (preset.canRename)
                            PopupMenuItem(
                              value: _PresetMenuAction.rename,
                              child: _menuRow(
                                Icons.drive_file_rename_outline,
                                'Rename',
                              ),
                            ),
                          PopupMenuItem(
                            value: _PresetMenuAction.duplicate,
                            child: _menuRow(
                              Icons.copy_all_outlined,
                              'Duplicate',
                            ),
                          ),
                          if (!isDefault)
                            PopupMenuItem(
                              value: _PresetMenuAction.makeDefault,
                              child: _menuRow(
                                Icons.star_outline_rounded,
                                'Set as default',
                              ),
                            ),
                          if (_plan.canDelete(preset.id))
                            PopupMenuItem(
                              value: _PresetMenuAction.delete,
                              child: _menuRow(
                                Icons.delete_outline,
                                'Delete',
                                color: scheme.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    _change(_plan.select(preset.id));
                    widget.onClose();
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'The Default preset mirrors timer settings and stays safe. '
              'Choose another default before deleting the current one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
