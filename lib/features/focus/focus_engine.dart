import 'dart:convert';

import '../../core/time/timer_defaults.dart';

/// The kind of timer a focus page session belongs to.
enum FocusPhase {
  focus('Focus'),
  shortBreak('Short break'),
  longBreak('Long break');

  const FocusPhase(this.label);

  final String label;

  bool get isBreak => this != FocusPhase.focus;

  Duration durationFor(FocusSettings settings) => switch (this) {
    FocusPhase.focus => Duration(minutes: settings.focusMinutes),
    FocusPhase.shortBreak => Duration(minutes: settings.shortBreakMinutes),
    FocusPhase.longBreak => Duration(minutes: settings.longBreakMinutes),
  };
}

/// Configurable timer plan. Values are validated at the surface that edits
/// them; the engine refuses to start a non-positive duration.
class FocusSettings {
  const FocusSettings({
    this.focusMinutes = TimerDefaults.focusMinutes,
    this.shortBreakMinutes = TimerDefaults.shortBreakMinutes,
    this.longBreakMinutes = TimerDefaults.longBreakMinutes,
    this.sessionsPerCycle = TimerDefaults.sessionsPerCycle,
  });

  static const defaults = FocusSettings();

  static const minFocusMinutes = 1;
  static const maxFocusMinutes = 180;
  static const minBreakMinutes = 1;
  static const maxBreakMinutes = 60;
  static const minSessionsPerCycle = 1;
  static const maxSessionsPerCycle = 12;

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// Focus blocks in one finite plan. The plan ends after this many focus
  /// sessions, with the final block followed by a long break.
  final int sessionsPerCycle;

  Duration durationFor(FocusPhase phase) => phase.durationFor(this);

  bool get isValid => validationError == null;

  /// A user-facing reason the plan cannot be used, or null when valid.
  String? get validationError {
    if (focusMinutes < minFocusMinutes || focusMinutes > maxFocusMinutes) {
      return 'Focus must be $minFocusMinutes-$maxFocusMinutes minutes.';
    }
    if (shortBreakMinutes < minBreakMinutes ||
        shortBreakMinutes > maxBreakMinutes) {
      return 'Short break must be $minBreakMinutes-$maxBreakMinutes minutes.';
    }
    if (longBreakMinutes < minBreakMinutes ||
        longBreakMinutes > maxBreakMinutes) {
      return 'Long break must be $minBreakMinutes-$maxBreakMinutes minutes.';
    }
    if (sessionsPerCycle < minSessionsPerCycle ||
        sessionsPerCycle > maxSessionsPerCycle) {
      return 'Sessions must be $minSessionsPerCycle-$maxSessionsPerCycle.';
    }
    return null;
  }

  FocusSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsPerCycle,
  }) => FocusSettings(
    focusMinutes: focusMinutes ?? this.focusMinutes,
    shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
    longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
    sessionsPerCycle: sessionsPerCycle ?? this.sessionsPerCycle,
  );

  Map<String, Object> toJson() => <String, Object>{
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'sessionsPerCycle': sessionsPerCycle,
  };

  static FocusSettings? tryDecode(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final focus = value['focusMinutes'];
    final short = value['shortBreakMinutes'];
    final long = value['longBreakMinutes'];
    if (focus is! int || short is! int || long is! int) return null;
    final rawSessions = value['sessionsPerCycle'];
    final settings = FocusSettings(
      focusMinutes: focus,
      shortBreakMinutes: short,
      longBreakMinutes: long,
      sessionsPerCycle: rawSessions is int
          ? rawSessions
          : TimerDefaults.sessionsPerCycle,
    );
    return settings.isValid ? settings : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FocusSettings &&
      other.focusMinutes == focusMinutes &&
      other.shortBreakMinutes == shortBreakMinutes &&
      other.longBreakMinutes == longBreakMinutes &&
      other.sessionsPerCycle == sessionsPerCycle;

  @override
  int get hashCode => Object.hash(
    focusMinutes,
    shortBreakMinutes,
    longBreakMinutes,
    sessionsPerCycle,
  );
}

/// A named timer plan the setup surface can select, edit and persist.
///
/// The built-in [defaults] preset mirrors the shared timer settings and is the
/// safe fallback when any other preset is removed. Built-ins are ordinary
/// values so old snapshots that stored the enum name keep decoding.
class FocusPreset {
  const FocusPreset({
    required this.id,
    required this.name,
    required this.presetSettings,
    this.isBuiltIn = false,
    this.fixed = false,
  });

  static const defaultsId = 'defaults';
  static const sprintId = 'sprint';
  static const deepWorkId = 'deepWork';

  static const defaults = FocusPreset(
    id: defaultsId,
    name: 'Default',
    presetSettings: FocusSettings.defaults,
    isBuiltIn: true,
    fixed: true,
  );

  static const sprint = FocusPreset(
    id: sprintId,
    name: 'Sprint',
    presetSettings: FocusSettings(
      focusMinutes: 15,
      shortBreakMinutes: 3,
      longBreakMinutes: 10,
    ),
    isBuiltIn: true,
  );

  static const deepWork = FocusPreset(
    id: deepWorkId,
    name: 'Deep work',
    presetSettings: FocusSettings(
      focusMinutes: 50,
      shortBreakMinutes: 10,
      longBreakMinutes: 20,
    ),
    isBuiltIn: true,
  );

  static const builtIns = <FocusPreset>[defaults, sprint, deepWork];

  final String id;
  final String name;
  final FocusSettings presetSettings;
  final bool isBuiltIn;

  /// The default preset resolves to the shared timer settings, so it stays in
  /// step with Settings and cannot be renamed or deleted.
  final bool fixed;

  String get label => name;
  bool get canEdit => !fixed;
  bool get canRename => !fixed;
  bool get canDelete => !fixed;

  FocusSettings settings(FocusSettings fallback) =>
      fixed ? fallback : presetSettings;

  FocusPreset copyWith({String? name, FocusSettings? presetSettings}) =>
      FocusPreset(
        id: id,
        name: name ?? this.name,
        presetSettings: presetSettings ?? this.presetSettings,
        isBuiltIn: isBuiltIn,
        fixed: fixed,
      );

  /// Reads a built-in id or a legacy enum/[name] value. Custom presets are
  /// resolved from a [FocusPlanState], never guessed from the snapshot.
  static FocusPreset? tryRead(Object? value) {
    if (value is! String) return null;
    for (final preset in builtIns) {
      if (value == preset.id || value == preset.name) return preset;
    }
    return null;
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'settings': presetSettings.toJson(),
  };

  static FocusPreset? tryDecode(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final name = value['name'];
    final settings = FocusSettings.tryDecode(value['settings']);
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        name is! String ||
        settings == null) {
      return null;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) return null;
    if (id == defaultsId) return FocusPreset.defaults;
    return FocusPreset(
      id: id,
      name: trimmed,
      presetSettings: settings,
      isBuiltIn: FocusPreset.builtIns.any((preset) => preset.id == id),
    );
  }

  @override
  bool operator ==(Object other) => other is FocusPreset && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FocusPreset($id)';
}

/// The persisted setup owner for the Focus destination.
///
/// It holds the named presets, the safe default, the selected preset, an
/// optional one-off plan and the explicit auto-advance preference. The page
/// keeps one instance and writes it through the existing timer snapshot owner,
/// so presets and the timer share one atomic persistence path.
class FocusPlanState {
  const FocusPlanState({
    required this.presets,
    required this.defaultId,
    required this.selectedId,
    this.oneOffSettings,
    this.autoAdvance = false,
  });

  static const initial = FocusPlanState(
    presets: FocusPreset.builtIns,
    defaultId: FocusPreset.defaultsId,
    selectedId: FocusPreset.defaultsId,
  );

  static const maxPresets = 50;

  final List<FocusPreset> presets;
  final String defaultId;
  final String selectedId;

  /// Applies to the next whole plan and is cleared when that plan ends.
  final FocusSettings? oneOffSettings;

  /// Manual phase changes by default; true starts the next phase automatically
  /// after a completed session outcome has been saved.
  final bool autoAdvance;

  bool get isOneOff => oneOffSettings != null;

  FocusPreset? presetById(String? id) {
    if (id == null) return null;
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  FocusPreset get defaultPreset =>
      presetById(defaultId) ?? presets.first;

  FocusPreset get selectedPreset =>
      presetById(selectedId) ?? defaultPreset;

  FocusSettings resolve(FocusSettings fallback) =>
      oneOffSettings ?? selectedPreset.settings(fallback);

  bool canDelete(String id) {
    final preset = presetById(id);
    return preset != null &&
        preset.canDelete &&
        presets.length > 1 &&
        id != defaultId;
  }

  String? validatePresetName(String name, {String? exceptId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a preset name.';
    if (trimmed.length > 40) return 'Use 40 characters or fewer.';
    final lower = trimmed.toLowerCase();
    for (final preset in presets) {
      if (preset.id != exceptId && preset.name.toLowerCase() == lower) {
        return 'That name is already used.';
      }
    }
    return null;
  }

  String _newPresetId() {
    var index = presets.length;
    while (presetById('custom-$index') != null) {
      index++;
    }
    return 'custom-$index';
  }

  FocusPlanState copyWith({
    List<FocusPreset>? presets,
    String? defaultId,
    String? selectedId,
    FocusSettings? oneOffSettings,
    bool clearOneOff = false,
    bool? autoAdvance,
  }) => FocusPlanState(
    presets: presets ?? this.presets,
    defaultId: defaultId ?? this.defaultId,
    selectedId: selectedId ?? this.selectedId,
    oneOffSettings: clearOneOff
        ? null
        : (oneOffSettings ?? this.oneOffSettings),
    autoAdvance: autoAdvance ?? this.autoAdvance,
  );

  FocusPlanState addPreset(
    String name,
    FocusSettings settings, {
    bool makeDefault = false,
  }) {
    if (!settings.isValid ||
        presets.length >= maxPresets ||
        validatePresetName(name) != null) {
      return this;
    }
    final preset = FocusPreset(
      id: _newPresetId(),
      name: name.trim(),
      presetSettings: settings,
    );
    return copyWith(
      presets: <FocusPreset>[...presets, preset],
      selectedId: preset.id,
      defaultId: makeDefault ? preset.id : defaultId,
    );
  }

  FocusPlanState updatePreset(
    String id,
    FocusSettings settings, {
    bool makeDefault = false,
  }) {
    final preset = presetById(id);
    if (preset == null || preset.fixed || !settings.isValid) return this;
    return copyWith(
      presets: <FocusPreset>[
        for (final item in presets)
          if (item.id == id)
            item.copyWith(presetSettings: settings)
          else
            item,
      ],
      selectedId: id,
      defaultId: makeDefault ? id : defaultId,
    );
  }

  FocusPlanState renamePreset(String id, String name) {
    final preset = presetById(id);
    if (preset == null ||
        !preset.canRename ||
        validatePresetName(name, exceptId: id) != null) {
      return this;
    }
    final trimmed = name.trim();
    return copyWith(
      presets: <FocusPreset>[
        for (final item in presets)
          if (item.id == id) item.copyWith(name: trimmed) else item,
      ],
    );
  }

  FocusPlanState duplicatePreset(String id, {FocusSettings? fallback}) {
    final source = presetById(id);
    if (source == null || presets.length >= maxPresets) return this;
    final base = source.name.length > 28
        ? source.name.substring(0, 28)
        : source.name;
    var candidate = '$base copy';
    var index = 2;
    while (validatePresetName(candidate) != null) {
      candidate = '$base copy $index';
      index++;
    }
    final settings = source.fixed
        ? (fallback ?? FocusSettings.defaults)
        : source.presetSettings;
    if (!settings.isValid) return this;
    final duplicate = FocusPreset(
      id: _newPresetId(),
      name: candidate,
      presetSettings: settings,
    );
    return copyWith(
      presets: <FocusPreset>[...presets, duplicate],
      selectedId: duplicate.id,
    );
  }

  /// Removes a preset when it is safe; returns the same instance otherwise.
  /// Removing the selected preset falls back to the safe default.
  FocusPlanState deletePreset(String id) {
    if (!canDelete(id)) return this;
    final next = <FocusPreset>[
      for (final preset in presets)
        if (preset.id != id) preset,
    ];
    return copyWith(
      presets: next,
      selectedId: selectedId == id ? defaultId : selectedId,
    );
  }

  FocusPlanState setDefault(String id) {
    if (presetById(id) == null) return this;
    return copyWith(defaultId: id);
  }

  FocusPlanState select(String id) {
    if (presetById(id) == null) return this;
    // A pending one-off applies to the next whole plan; only ending that plan
    // clears it, so choosing a preset must not consume it silently.
    return copyWith(selectedId: id);
  }

  FocusPlanState useOneOff(FocusSettings settings) {
    if (!settings.isValid) return this;
    return copyWith(oneOffSettings: settings);
  }

  FocusPlanState clearOneOff() => copyWith(clearOneOff: true);

  FocusPlanState withAutoAdvance(bool value) =>
      copyWith(autoAdvance: value);

  Map<String, Object?> toJson() => <String, Object?>{
    'presets': <Object>[for (final preset in presets) preset.toJson()],
    'defaultId': defaultId,
    'selectedId': selectedId,
    if (oneOffSettings case final settings?) 'oneOff': settings.toJson(),
    'autoAdvance': autoAdvance,
  };

  static FocusPlanState? tryDecode(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final rawPresets = value['presets'];
    if (rawPresets is! List<Object?>) return null;
    final decoded = <FocusPreset>[];
    final ids = <String>{};
    for (final raw in rawPresets) {
      if (decoded.length >= maxPresets) break;
      final preset = FocusPreset.tryDecode(raw);
      if (preset != null && ids.add(preset.id)) decoded.add(preset);
    }
    if (decoded.isEmpty) return null;

    final rawDefault = value['defaultId'];
    final defaultId = rawDefault is String && ids.contains(rawDefault)
        ? rawDefault
        : decoded.first.id;
    final rawSelected = value['selectedId'];
    final selectedId = rawSelected is String && ids.contains(rawSelected)
        ? rawSelected
        : defaultId;
    final oneOff = FocusSettings.tryDecode(value['oneOff']);
    return FocusPlanState(
      presets: decoded,
      defaultId: defaultId,
      selectedId: selectedId,
      oneOffSettings: oneOff,
      autoAdvance: value['autoAdvance'] == true,
    );
  }
}

/// The explicit states the page can show.
enum FocusStatus { idle, ready, running, paused, completed, cancelled }

/// A finished or abandoned timer session handed to the host for storage.
class FocusOutcome {
  const FocusOutcome({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.intended,
    required this.actual,
    required this.completed,
  });

  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Duration intended;
  final Duration actual;
  final bool completed;
}

/// A versioned, JSON-safe view of the engine. Running sessions persist their
/// wall-clock anchor; the page restores from it after a process restart.
///
/// Version 2 adds an optional [plan] document (presets, one-off plan,
/// auto-advance). Version 3 adds the active plan's finite target, its progress
/// and the settings it started with. Version 1 and 2 snapshots still decode;
/// a legacy snapshot without plan fields never carries lifetime focus counts
/// into the new plan progress, so no phantom blocks appear after an upgrade.
class FocusSnapshot {
  const FocusSnapshot({
    required this.id,
    required this.phase,
    required this.status,
    required this.startedAt,
    required this.anchor,
    required this.intended,
    required this.remaining,
    required this.finishedAt,
    required this.completedFocusSessions,
    this.preset,
    this.plan,
    this.planTarget,
    this.planCompleted = 0,
    this.planSettings,
    this.breakSkipped = false,
  });

  static const _version = 3;
  static const _readableVersions = <int>{1, 2, 3};
  static const _maxIntendedMs = 24 * 60 * 60 * 1000;
  static const _maxCompletedSessions = 1000000;

  final String id;
  final FocusPhase phase;
  final FocusStatus status;
  final DateTime? startedAt;
  final DateTime? anchor;
  final Duration intended;
  final Duration? remaining;
  final DateTime? finishedAt;
  final int completedFocusSessions;
  final FocusPreset? preset;
  final FocusPlanState? plan;

  /// Focus blocks in the active plan, or 0 when no plan is running. Null in a
  /// legacy/unspecified snapshot; the engine then captures the current target
  /// from settings instead of guessing progress.
  final int? planTarget;

  /// Focus blocks already completed in the active plan, never negative and
  /// never greater than [planTarget].
  final int planCompleted;

  /// The settings the active plan started with, so recovery keeps its
  /// durations even when the shared defaults changed in the meantime.
  final FocusSettings? planSettings;

  /// True when the last break was skipped rather than run to completion.
  final bool breakSkipped;

  String encode({FocusPreset? selectedPreset, FocusPlanState? plan}) =>
      jsonEncode(<String, Object?>{
        'version': _version,
        'id': id,
        'phase': phase.name,
        'status': status.name,
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'anchor': anchor?.millisecondsSinceEpoch,
        'intendedMs': intended.inMilliseconds,
        'remainingMs': remaining?.inMilliseconds,
        'finishedAt': finishedAt?.millisecondsSinceEpoch,
        'completedFocusSessions': completedFocusSessions,
        if ((selectedPreset ?? preset) case final active?)
          'preset': active.id,
        if (plan != null) 'plan': plan.toJson(),
        if (planTarget case final target?) 'planTarget': target,
        if (planTarget != null) 'planCompleted': planCompleted,
        if (planSettings case final settings?)
          'planSettings': settings.toJson(),
        if (planTarget != null) 'breakSkipped': breakSkipped,
      });

  static FocusSnapshot? tryDecode(String? source) {
    if (source == null || source.trim().isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['version'];
    final phase = _phaseFrom(decoded['phase']);
    final status = _statusFrom(decoded['status']);
    final intendedMs = decoded['intendedMs'];
    final completedCount = decoded['completedFocusSessions'];
    if (version is! int ||
        !_readableVersions.contains(version) ||
        phase == null ||
        status == null) {
      return null;
    }
    if (intendedMs is! int || intendedMs <= 0 || intendedMs > _maxIntendedMs) {
      return null;
    }
    if (completedCount is! int ||
        completedCount < 0 ||
        completedCount > _maxCompletedSessions) {
      return null;
    }

    final id = decoded['id'];
    if (id is! String || id.length > 128) return null;

    final startedAt = _dateTimeFrom(decoded['startedAt']);
    final anchor = _dateTimeFrom(decoded['anchor']);
    final finishedAt = _dateTimeFrom(decoded['finishedAt']);
    final remaining = _durationFromMillis(decoded['remainingMs']);
    if (decoded['remainingMs'] != null && remaining == null) return null;
    if (remaining != null && remaining > Duration(milliseconds: intendedMs)) {
      return null;
    }

    final dormant = status == FocusStatus.idle || status == FocusStatus.ready;
    if (!dormant && (id.isEmpty || startedAt == null || anchor == null)) {
      return null;
    }
    if (status == FocusStatus.paused && remaining == null) return null;
    if ((status == FocusStatus.completed || status == FocusStatus.cancelled) &&
        finishedAt == null) {
      return null;
    }

    final plan = version >= 2 ? FocusPlanState.tryDecode(decoded['plan']) : null;

    int? planTarget;
    var planCompleted = 0;
    FocusSettings? planSettings;
    var breakSkipped = false;
    if (version >= 3) {
      final rawTarget = decoded['planTarget'];
      if (rawTarget != null && rawTarget is! int) return null;
      if (rawTarget is int) {
        if (rawTarget < 0 || rawTarget > FocusSettings.maxSessionsPerCycle) {
          return null;
        }
        planTarget = rawTarget;
      }
      final rawCompleted = decoded['planCompleted'];
      if (rawCompleted != null && rawCompleted is! int) return null;
      if (rawCompleted is int) {
        if (rawCompleted < 0) return null;
        planCompleted = rawCompleted;
      }
      if (planTarget != null && planCompleted > planTarget) return null;
      if (planTarget == 0 && planCompleted != 0) return null;
      planSettings = FocusSettings.tryDecode(decoded['planSettings']);
      final rawSkipped = decoded['breakSkipped'];
      if (rawSkipped != null && rawSkipped is! bool) return null;
      breakSkipped = rawSkipped == true;
    }

    // A running, paused or completed timer always belongs to a plan. A missing
    // target in a legacy snapshot is left unspecified so the engine can adopt
    // the current settings and derive at most the blocks the state proves.
    final needsPlan = status == FocusStatus.running ||
        status == FocusStatus.paused ||
        status == FocusStatus.completed;
    if (needsPlan && planTarget == 0) {
      planTarget = null;
      planCompleted = 0;
      breakSkipped = false;
    }
    if (planTarget == null || planTarget == 0) {
      planSettings = null;
      breakSkipped = false;
      planCompleted = 0;
    } else if (breakSkipped &&
        !(status == FocusStatus.completed && phase.isBreak)) {
      breakSkipped = false;
    }

    return FocusSnapshot(
      id: id,
      phase: phase,
      status: status,
      startedAt: startedAt,
      anchor: anchor,
      intended: Duration(milliseconds: intendedMs),
      remaining: remaining,
      finishedAt: finishedAt,
      completedFocusSessions: completedCount,
      preset: plan?.selectedPreset ?? FocusPreset.tryRead(decoded['preset']),
      plan: plan,
      planTarget: planTarget,
      planCompleted: planCompleted,
      planSettings: planSettings,
      breakSkipped: breakSkipped,
    );
  }

  static FocusPhase? _phaseFrom(Object? value) {
    if (value is! String) return null;
    for (final phase in FocusPhase.values) {
      if (phase.name == value) return phase;
    }
    return null;
  }

  static FocusStatus? _statusFrom(Object? value) {
    if (value is! String) return null;
    for (final status in FocusStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }

  static DateTime? _dateTimeFrom(Object? value) => value is int
      ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
      : null;

  static Duration? _durationFromMillis(Object? value) =>
      value is int && value >= 0 ? Duration(milliseconds: value) : null;
}

/// Injectable time source. `monotonic` drives the running timer so a wall-clock
/// jump cannot move it; `nowUtc` is only used for persisted anchors.
abstract interface class FocusClock {
  DateTime nowUtc();

  Duration monotonic();
}

class SystemFocusClock implements FocusClock {
  SystemFocusClock();

  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  Duration monotonic() => _stopwatch.elapsed;
}

/// Pure timestamp-based focus/break state machine.
class FocusEngine {
  FocusEngine({
    required FocusSettings settings,
    FocusClock? clock,
    String Function()? createId,
    FocusSnapshot? restored,
    DateTime? recoveredAt,
  }) : _settings = settings,
       _clock = clock ?? SystemFocusClock(),
       _createId = createId {
    _intended = _settings.durationFor(FocusPhase.focus);
    final snapshot = restored;
    if (snapshot != null) {
      _restore(snapshot, recoveredAt);
    }
  }

  final FocusClock _clock;
  final String Function()? _createId;

  FocusSettings _settings;
  FocusStatus _status = FocusStatus.idle;
  FocusPhase _phase = FocusPhase.focus;
  String _id = '';
  DateTime? _startedAt;
  DateTime? _anchor;
  DateTime? _finishedAt;
  Duration _intended = Duration.zero;
  Duration _accumulated = Duration.zero;
  Duration _pausedRemaining = Duration.zero;
  Duration _runStartedMono = Duration.zero;
  int _completedFocusSessions = 0;
  int _idSequence = 0;
  FocusOutcome? _lastOutcome;

  /// Finite plan state. A plan starts on the first focus block, ends after the
  /// target block's long break (or End/Done), and never recurs on its own.
  int _planTarget = 0;
  int _planCompleted = 0;
  FocusSettings? _planSettings;
  bool _breakSkipped = false;

  FocusStatus get status => _status;
  FocusPhase get phase => _phase;
  String get id => _id;
  DateTime? get startedAt => _startedAt;
  DateTime? get finishedAt => _finishedAt;
  Duration get intended => _intended;
  FocusSettings get settings => _settings;
  int get completedFocusSessions => _completedFocusSessions;
  int get sessionsPerCycle => _settings.sessionsPerCycle;

  bool get hasPlan => _planTarget > 0;
  int get planTarget => _planTarget;
  int get planCompleted => _planCompleted;
  bool get planFinished => hasPlan && _planCompleted >= _planTarget;
  bool get breakSkipped => _breakSkipped;
  FocusOutcome? get lastOutcome => _lastOutcome;
  bool get isRunning => _status == FocusStatus.running;
  bool get isPaused => _status == FocusStatus.paused;
  bool get hasActiveSession => isRunning || isPaused;

  /// When the running session is due, for host scheduling. Null unless running.
  DateTime? get deadline => isRunning ? _clock.nowUtc().add(remaining) : null;

  String get statusLabel {
    switch (_status) {
      case FocusStatus.idle:
        return 'Idle';
      case FocusStatus.ready:
        return 'Ready to focus';
      case FocusStatus.running:
        return _phase == FocusPhase.focus ? 'Focusing' : _phase.label;
      case FocusStatus.paused:
        return _phase == FocusPhase.focus ? 'Paused' : 'Break paused';
      case FocusStatus.completed:
        if (_phase == FocusPhase.focus) return 'Focus complete';
        return _breakSkipped ? 'Break skipped' : 'Break complete';
      case FocusStatus.cancelled:
        return _phase == FocusPhase.focus
            ? 'Session cancelled'
            : 'Break cancelled';
    }
  }

  /// The break that follows the block that just completed. Only the plan's
  /// final block gets a long break; a plan never recurs past its target.
  FocusPhase get nextBreakPhase =>
      planFinished ? FocusPhase.longBreak : FocusPhase.shortBreak;

  Duration get remaining {
    switch (_status) {
      case FocusStatus.idle:
      case FocusStatus.ready:
        return _intended;
      case FocusStatus.running:
        final left = _intended - _activeElapsed;
        return left.isNegative ? Duration.zero : left;
      case FocusStatus.paused:
        return _pausedRemaining;
      case FocusStatus.completed:
      case FocusStatus.cancelled:
        return Duration.zero;
    }
  }

  Duration get elapsed {
    switch (_status) {
      case FocusStatus.idle:
      case FocusStatus.ready:
        return Duration.zero;
      case FocusStatus.running:
      case FocusStatus.paused:
        return _activeElapsed;
      case FocusStatus.completed:
      case FocusStatus.cancelled:
        return _accumulated;
    }
  }

  Duration get _activeElapsed {
    if (_status != FocusStatus.running) return _accumulated;
    final delta = _clock.monotonic() - _runStartedMono;
    final active = _accumulated + (delta.isNegative ? Duration.zero : delta);
    if (active.isNegative) return Duration.zero;
    return active > _intended ? _intended : active;
  }

  void prepare() {
    if (_status == FocusStatus.idle) {
      _status = FocusStatus.ready;
      _phase = FocusPhase.focus;
      _intended = _settings.durationFor(_phase);
    }
  }

  void updateSettings(FocusSettings settings) {
    _settings = settings;
    if (_status == FocusStatus.idle || _status == FocusStatus.ready) {
      _intended = _settings.durationFor(_phase);
    } else if (hasPlan) {
      // Durations may change for the blocks still ahead, but the plan target
      // and its progress stay fixed until the plan ends.
      _planSettings = settings;
    }
  }

  void startFocus() {
    if (hasActiveSession) {
      throw StateError('A timer is already running.');
    }
    if (_status == FocusStatus.completed) {
      if (_phase == FocusPhase.focus) {
        throw StateError('Start the break before the next focus.');
      }
      if (planFinished) {
        throw StateError('This plan is complete.');
      }
    }
    if (!hasPlan) _startNewPlan();
    _begin(FocusPhase.focus);
  }

  void startBreak() {
    if (_status != FocusStatus.completed || _phase != FocusPhase.focus) {
      throw StateError('A break can start only after a focus session completes.');
    }
    if (!hasPlan) {
      _startNewPlan();
      _planCompleted = 1;
    }
    _begin(nextBreakPhase);
  }

  /// Skips the pending break without running a timer or recording an outcome.
  /// The plan keeps its progress and offers the next block or Done.
  void skipBreak() {
    if (_status != FocusStatus.completed || _phase != FocusPhase.focus) {
      throw StateError('No completed focus session is waiting for a break.');
    }
    if (!hasPlan) {
      _startNewPlan();
      _planCompleted = 1;
    }
    _phase = nextBreakPhase;
    _breakSkipped = true;
    _finishedAt = _clock.nowUtc();
    _lastOutcome = null;
  }

  /// Leaves the active plan for setup through End plan or Done. No outcome is
  /// emitted: every completed focus block was already delivered to the host.
  void endPlan() {
    if (hasActiveSession) {
      throw StateError('Finish the running session before ending the plan.');
    }
    if (!hasPlan) {
      throw StateError('No plan is active.');
    }
    _resetPlan();
    _phase = FocusPhase.focus;
    _status = FocusStatus.ready;
    _id = '';
    _startedAt = null;
    _anchor = null;
    _finishedAt = null;
    _intended = _settings.durationFor(_phase);
    _accumulated = Duration.zero;
    _pausedRemaining = Duration.zero;
    _runStartedMono = _clock.monotonic();
    _lastOutcome = null;
  }

  /// Captures a fresh finite plan from the settings in force at its start.
  void _startNewPlan() {
    final target = _settings.sessionsPerCycle;
    _planTarget = target < FocusSettings.minSessionsPerCycle
        ? FocusSettings.minSessionsPerCycle
        : (target > FocusSettings.maxSessionsPerCycle
              ? FocusSettings.maxSessionsPerCycle
              : target);
    _planCompleted = 0;
    _planSettings = _settings;
    _breakSkipped = false;
  }

  void _resetPlan() {
    _planTarget = 0;
    _planCompleted = 0;
    _planSettings = null;
    _breakSkipped = false;
  }

  FocusOutcome? pause() {
    if (_status != FocusStatus.running) {
      throw StateError('Only a running timer can pause.');
    }
    if (remaining <= Duration.zero) {
      return _finish(completed: true);
    }
    final active = _activeElapsed;
    _accumulated = active;
    _pausedRemaining = _intended - active;
    _status = FocusStatus.paused;
    return null;
  }

  void resume() {
    if (_status != FocusStatus.paused) {
      throw StateError('Only a paused timer can resume.');
    }
    _accumulated = _intended - _pausedRemaining;
    _anchor = _clock.nowUtc().subtract(_accumulated);
    _runStartedMono = _clock.monotonic();
    _status = FocusStatus.running;
  }

  FocusOutcome cancel() {
    if (!hasActiveSession) {
      throw StateError('No active session can be cancelled.');
    }
    final outcome = _finish(completed: false);
    // A confirmed abandonment clears the plan, so one-off settings cannot leak
    // into a later plan.
    _resetPlan();
    return outcome;
  }

  /// Returns an outcome exactly once when a running session reaches zero.
  FocusOutcome? tick() {
    if (_status != FocusStatus.running) return null;
    if (remaining > Duration.zero) return null;
    return _finish(completed: true);
  }

  FocusSnapshot snapshot() {
    final anchor = _status == FocusStatus.running
        ? _clock.nowUtc().subtract(_activeElapsed)
        : _anchor;
    return FocusSnapshot(
      id: _id,
      phase: _phase,
      status: _status,
      startedAt: _startedAt,
      anchor: anchor,
      intended: _intended,
      remaining: _status == FocusStatus.paused ? _pausedRemaining : null,
      finishedAt: _finishedAt,
      completedFocusSessions: _completedFocusSessions,
      planTarget: _planTarget,
      planCompleted: _planCompleted,
      planSettings: _planSettings,
      breakSkipped: _breakSkipped,
    );
  }

  String encodeSnapshot() => snapshot().encode();

  void _begin(FocusPhase phase) {
    final now = _clock.nowUtc();
    final intended = (_planSettings ?? _settings).durationFor(phase);
    if (intended <= Duration.zero) {
      throw StateError('${phase.label} duration must be positive.');
    }
    if (phase == FocusPhase.focus) {
      // A skipped break belongs to the block that just finished, not to the
      // next focus block.
      _breakSkipped = false;
    }
    _phase = phase;
    _intended = intended;
    _id = _newId();
    _startedAt = now;
    _anchor = now;
    _finishedAt = null;
    _accumulated = Duration.zero;
    _pausedRemaining = Duration.zero;
    _runStartedMono = _clock.monotonic();
    _lastOutcome = null;
    _status = FocusStatus.running;
  }

  FocusOutcome _finish({required bool completed}) {
    final now = _clock.nowUtc();
    final startedAt = _startedAt ?? now;
    final actual = completed ? _intended : _activeElapsed;
    var finishedAt = completed ? (_anchor ?? now).add(_intended) : now;
    if (finishedAt.isBefore(startedAt)) {
      finishedAt = startedAt;
    }
    _accumulated = actual;
    _finishedAt = finishedAt;
    _status = completed ? FocusStatus.completed : FocusStatus.cancelled;
    if (completed && _phase == FocusPhase.focus) {
      _completedFocusSessions += 1;
      if (hasPlan && _planCompleted < _planTarget) {
        _planCompleted += 1;
      }
      _breakSkipped = false;
    }
    final outcome = FocusOutcome(
      id: _id,
      startedAt: startedAt,
      finishedAt: finishedAt,
      intended: _intended,
      actual: actual,
      completed: completed,
    );
    _lastOutcome = outcome;
    return outcome;
  }

  void _restore(FocusSnapshot snapshot, DateTime? recoveredAt) {
    _completedFocusSessions = snapshot.completedFocusSessions;

    switch (snapshot.status) {
      case FocusStatus.idle:
      case FocusStatus.ready:
        _resetPlan();
        _phase = snapshot.phase;
        _status = snapshot.status;
        _intended = _settings.durationFor(_phase);
        return;
      case FocusStatus.running:
        _adoptRestoredPlan(snapshot);
        _phase = snapshot.phase;
        _id = snapshot.id;
        _startedAt = snapshot.startedAt;
        _intended = snapshot.intended;
        _status = FocusStatus.running;
        final anchor = snapshot.anchor!;
        final recoveryNow = recoveredAt ?? _clock.nowUtc();
        final away = recoveryNow.difference(anchor);
        if (away.isNegative) {
          _anchor = _clock.nowUtc();
          _accumulated = Duration.zero;
        } else {
          _accumulated = away > _intended ? _intended : away;
          _anchor = _accumulated >= _intended
              ? anchor
              : _clock.nowUtc().subtract(_accumulated);
        }
        _runStartedMono = _clock.monotonic();
        return;
      case FocusStatus.paused:
        _adoptRestoredPlan(snapshot);
        _phase = snapshot.phase;
        _id = snapshot.id;
        _startedAt = snapshot.startedAt;
        _anchor = snapshot.anchor;
        _intended = snapshot.intended;
        _pausedRemaining = snapshot.remaining ?? Duration.zero;
        _accumulated = _intended - _pausedRemaining;
        _status = FocusStatus.paused;
        return;
      case FocusStatus.completed:
        _adoptRestoredPlan(snapshot);
        _phase = snapshot.phase;
        _id = snapshot.id;
        _startedAt = snapshot.startedAt;
        _anchor = snapshot.anchor;
        _intended = snapshot.intended;
        _status = FocusStatus.completed;
        final startedAt = snapshot.startedAt ?? snapshot.finishedAt!;
        final savedFinishedAt = snapshot.finishedAt!;
        final finishedAt = savedFinishedAt.isBefore(startedAt)
            ? startedAt
            : savedFinishedAt;
        _finishedAt = finishedAt;
        if (_breakSkipped) {
          // A skipped break never ran, so it has no elapsed time or outcome.
          _accumulated = Duration.zero;
          _lastOutcome = null;
        } else {
          _accumulated = _intended;
          _lastOutcome = FocusOutcome(
            id: snapshot.id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            intended: snapshot.intended,
            actual: snapshot.intended,
            completed: true,
          );
        }
        return;
      case FocusStatus.cancelled:
        _resetPlan();
        _phase = FocusPhase.focus;
        _status = FocusStatus.ready;
        _intended = _settings.durationFor(_phase);
        return;
    }
  }

  /// Restores the active plan. A v3 snapshot carries its own target and
  /// settings; a legacy snapshot only proves the blocks implied by its state,
  /// never its lifetime focus count.
  void _adoptRestoredPlan(FocusSnapshot snapshot) {
    final target = snapshot.planTarget;
    if (target != null && target > 0) {
      _planTarget = target > FocusSettings.maxSessionsPerCycle
          ? FocusSettings.maxSessionsPerCycle
          : target;
      final completed = snapshot.planCompleted;
      _planCompleted = completed < 0
          ? 0
          : (completed > _planTarget ? _planTarget : completed);
      _planSettings = snapshot.planSettings ?? _settings;
      _breakSkipped = snapshot.breakSkipped &&
          snapshot.status == FocusStatus.completed &&
          snapshot.phase.isBreak;
      return;
    }
    final rawTarget = _settings.sessionsPerCycle;
    _planTarget = rawTarget < FocusSettings.minSessionsPerCycle
        ? FocusSettings.minSessionsPerCycle
        : (rawTarget > FocusSettings.maxSessionsPerCycle
              ? FocusSettings.maxSessionsPerCycle
              : rawTarget);
    _planSettings = _settings;
    final proved = snapshot.phase == FocusPhase.focus
        ? (snapshot.status == FocusStatus.completed ? 1 : 0)
        : 1;
    _planCompleted = proved > _planTarget ? _planTarget : proved;
    _breakSkipped = false;
  }

  String _newId() {
    final createId = _createId;
    if (createId != null) return createId();
    final stamp = _clock.nowUtc().microsecondsSinceEpoch;
    return 'focus-$stamp-${_idSequence++}';
  }
}
