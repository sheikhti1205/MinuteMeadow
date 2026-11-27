import '../../features/clock/clock_engine.dart';
import '../../features/focus/focus_engine.dart';

/// A validated Focus preset carried by a portable backup.
///
/// Unlike [FocusPreset], this document has no selection or built-in flags: it
/// stores exactly the id, name and timer durations a restore needs. The
/// default preset always resolves to the restored shared settings through
/// [FocusPresetsDocument.toPlanState].
class FocusPresetDocument {
  const FocusPresetDocument({
    required this.id,
    required this.name,
    required this.settings,
  });

  static const maxIdLength = 80;
  static const maxNameLength = 40;

  final String id;
  final String name;
  final FocusSettings settings;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'settings': settings.toJson(),
  };

  /// Throws a [FormatException] when the preset is not safe to write.
  void validate() {
    if (!_isValidId(id, maxIdLength)) {
      throw const FormatException('Invalid focus preset id.');
    }
    if (name != name.trim() ||
        name.isEmpty ||
        name.length > maxNameLength) {
      throw const FormatException('Invalid focus preset name.');
    }
    if (!settings.isValid) {
      throw const FormatException('Invalid focus preset durations.');
    }
  }

  static FocusPresetDocument decode(Object? json) {
    if (json is! Map<String, Object?> ||
        !_hasExactKeys(json, const <String>{'id', 'name', 'settings'})) {
      throw const FormatException('Invalid focus preset.');
    }
    final id = json['id'];
    if (id is! String || !_isValidId(id, maxIdLength)) {
      throw const FormatException('Invalid focus preset id.');
    }
    final name = json['name'];
    if (name is! String) {
      throw const FormatException('Invalid focus preset name.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNameLength) {
      throw const FormatException('Invalid focus preset name.');
    }
    return FocusPresetDocument(
      id: id,
      name: trimmed,
      settings: _decodeFocusSettings(json['settings']),
    );
  }
}

/// The Focus plan document stored by a schema 2 backup.
///
/// It carries the named presets, the safe default and the auto-advance
/// preference. A pending one-off plan, the current selection and any running
/// timer state are deliberately absent, so restoring presets cannot resume a
/// timer or leak a one-off plan into the next session.
class FocusPresetsDocument {
  const FocusPresetsDocument({
    required this.presets,
    required this.defaultId,
    this.autoAdvance = false,
  });

  static const maxPresets = FocusPlanState.maxPresets;

  final List<FocusPresetDocument> presets;
  final String defaultId;
  final bool autoAdvance;

  FocusPresetDocument? presetById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  FocusPresetDocument get defaultPreset => presetById(defaultId)!;

  /// Throws a [FormatException] when the document is not safe to write.
  void validate() {
    if (presets.isEmpty || presets.length > maxPresets) {
      throw const FormatException('Invalid focus presets.');
    }
    final ids = <String>{};
    for (final preset in presets) {
      preset.validate();
      if (!ids.add(preset.id)) {
        throw const FormatException('Duplicate focus preset id.');
      }
    }
    // [FocusPlanState] always keeps the fixed built-in default, even when the
    // selected default is a custom preset. The two ids are independent.
    if (!ids.contains(FocusPreset.defaultsId)) {
      throw const FormatException('The fixed default focus preset is missing.');
    }
    if (!ids.contains(defaultId)) {
      throw const FormatException('The default focus preset is missing.');
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'presets': <Object>[for (final preset in presets) preset.toJson()],
    'defaultId': defaultId,
    'autoAdvance': autoAdvance,
  };

  static FocusPresetsDocument decode(Object? json) {
    if (json is! Map<String, Object?> ||
        !_hasExactKeys(json, const <String>{
          'presets',
          'defaultId',
          'autoAdvance',
        })) {
      throw const FormatException('Invalid focus presets.');
    }
    final rawPresets = json['presets'];
    if (rawPresets is! List<Object?> ||
        rawPresets.isEmpty ||
        rawPresets.length > maxPresets) {
      throw const FormatException('Invalid focus presets.');
    }
    final presets = <FocusPresetDocument>[];
    final ids = <String>{};
    for (final raw in rawPresets) {
      final preset = FocusPresetDocument.decode(raw);
      if (!ids.add(preset.id)) {
        throw const FormatException('Duplicate focus preset id.');
      }
      presets.add(preset);
    }
    // The fixed built-in default is mandatory even when [defaultId] names a
    // custom preset; it is the safe fallback for every plan operation.
    if (!ids.contains(FocusPreset.defaultsId)) {
      throw const FormatException('The fixed default focus preset is missing.');
    }
    final defaultId = json['defaultId'];
    if (defaultId is! String || !ids.contains(defaultId)) {
      throw const FormatException('The default focus preset is missing.');
    }
    final autoAdvance = json['autoAdvance'];
    if (autoAdvance is! bool) {
      throw const FormatException('Invalid focus presets.');
    }
    return FocusPresetsDocument(
      presets: List<FocusPresetDocument>.unmodifiable(presets),
      defaultId: defaultId,
      autoAdvance: autoAdvance,
    );
  }

  /// Captures the persisted plan without its selection or one-off settings.
  ///
  /// The fixed default preset takes its durations from [fallback] so the backup
  /// stays in step with the shared timer settings it is saved with.
  static FocusPresetsDocument fromPlan(
    FocusPlanState plan, {
    required FocusSettings fallback,
  }) {
    final presets = <FocusPresetDocument>[
      for (final preset in plan.presets)
        FocusPresetDocument(
          id: preset.id,
          name: preset.name.trim(),
          settings: preset.settings(fallback),
        ),
    ];
    final document = FocusPresetsDocument(
      presets: List<FocusPresetDocument>.unmodifiable(presets),
      defaultId: plan.presetById(plan.defaultId) != null
          ? plan.defaultId
          : (presets.isEmpty ? FocusPreset.defaultsId : presets.first.id),
      autoAdvance: plan.autoAdvance,
    );
    document.validate();
    return document;
  }

  /// Rebuilds a plan document for an idle Focus snapshot.
  ///
  /// Selections, one-off plans and running state are not part of the backup;
  /// the default preset becomes the selected preset.
  FocusPlanState toPlanState({required FocusSettings fallback}) {
    validate();
    final planPresets = <FocusPreset>[
      for (final preset in presets)
        FocusPreset(
          id: preset.id,
          name: preset.name,
          presetSettings: preset.id == FocusPreset.defaultsId
              ? fallback
              : preset.settings,
          isBuiltIn: FocusPreset.builtIns.any(
            (FocusPreset builtIn) => builtIn.id == preset.id,
          ),
          fixed: preset.id == FocusPreset.defaultsId,
        ),
    ];
    return FocusPlanState(
      presets: List<FocusPreset>.unmodifiable(planPresets),
      defaultId: defaultId,
      selectedId: defaultId,
      autoAdvance: autoAdvance,
    );
  }
}

/// A validated countdown preset carried by a portable backup.
class ClockPresetDocument {
  const ClockPresetDocument({
    required this.id,
    required this.label,
    required this.duration,
  });

  static const maxIdLength = 80;
  static const minDuration = Duration(seconds: 1);
  static const maxDuration = Duration(hours: 24);

  final String id;
  final String label;
  final Duration duration;

  int get durationMicros => duration.inMicroseconds;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'label': label,
    'durationMicros': durationMicros,
  };

  /// Throws a [FormatException] when the preset is not safe to write.
  void validate() {
    if (!_isValidId(id, maxIdLength)) {
      throw const FormatException('Invalid clock preset id.');
    }
    if (label != label.trim() || label.isEmpty) {
      throw const FormatException('Invalid clock preset label.');
    }
    if (durationMicros < minDuration.inMicroseconds ||
        durationMicros > maxDuration.inMicroseconds) {
      throw const FormatException('Invalid clock preset duration.');
    }
  }

  static ClockPresetDocument decode(Object? json) {
    if (json is! Map<String, Object?> ||
        !_hasExactKeys(json, const <String>{
          'id',
          'label',
          'durationMicros',
        })) {
      throw const FormatException('Invalid clock preset.');
    }
    final id = json['id'];
    if (id is! String || !_isValidId(id, maxIdLength)) {
      throw const FormatException('Invalid clock preset id.');
    }
    final label = json['label'];
    if (label is! String) {
      throw const FormatException('Invalid clock preset label.');
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Invalid clock preset label.');
    }
    final durationMicros = json['durationMicros'];
    if (durationMicros is! int ||
        durationMicros < minDuration.inMicroseconds ||
        durationMicros > maxDuration.inMicroseconds) {
      throw const FormatException('Invalid clock preset duration.');
    }
    return ClockPresetDocument(
      id: id,
      label: trimmed,
      duration: Duration(microseconds: durationMicros),
    );
  }
}

/// The Clock preset list stored by a schema 2 backup.
///
/// These are saved presets only; they are not active clock state. To apply
/// them to a live snapshot, reset the stopwatch and countdown, clear laps and
/// any completed-countdown state first, then replace the snapshot's `presets`
/// array and clear its `selectedPresetId`. Never merge them into a running
/// snapshot.
class ClockPresetsDocument {
  const ClockPresetsDocument({required this.presets});

  /// A broad defensive bound, not an engine limit.
  ///
  /// The Clock engine itself has no preset cap. This only rejects a
  /// pathological document that cannot fit meaningfully inside the 16 MiB
  /// backup budget; saved presets are never truncated.
  static const maxPresets = 100000;

  final List<ClockPresetDocument> presets;

  /// Throws a [FormatException] when the document is not safe to write.
  void validate() {
    if (presets.length > maxPresets) {
      throw const FormatException('Invalid clock presets.');
    }
    final ids = <String>{};
    for (final preset in presets) {
      preset.validate();
      if (!ids.add(preset.id)) {
        throw const FormatException('Duplicate clock preset id.');
      }
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'presets': <Object>[for (final preset in presets) preset.toJson()],
  };

  static ClockPresetsDocument decode(Object? json) {
    if (json is! Map<String, Object?> ||
        !_hasExactKeys(json, const <String>{'presets'})) {
      throw const FormatException('Invalid clock presets.');
    }
    final rawPresets = json['presets'];
    if (rawPresets is! List<Object?> || rawPresets.length > maxPresets) {
      throw const FormatException('Invalid clock presets.');
    }
    final presets = <ClockPresetDocument>[];
    final ids = <String>{};
    for (final raw in rawPresets) {
      final preset = ClockPresetDocument.decode(raw);
      if (!ids.add(preset.id)) {
        throw const FormatException('Duplicate clock preset id.');
      }
      presets.add(preset);
    }
    return ClockPresetsDocument(
      presets: List<ClockPresetDocument>.unmodifiable(presets),
    );
  }

  /// Captures the saved presets without the active countdown or stopwatch.
  static ClockPresetsDocument fromPresets(Iterable<ClockPreset> presets) {
    var index = 0;
    final document = ClockPresetsDocument(
      presets: List<ClockPresetDocument>.unmodifiable(<ClockPresetDocument>[
        for (final preset in presets)
          ClockPresetDocument(
            id: preset.id,
            label: preset.label.trim().isEmpty
                ? 'Preset ${++index}'
                : preset.label.trim(),
            duration: Duration(microseconds: preset.durationMicros),
          ),
      ]),
    );
    document.validate();
    return document;
  }

  List<ClockPreset> toClockPresets() => <ClockPreset>[
    for (final preset in presets)
      ClockPreset(
        id: preset.id,
        label: preset.label,
        durationMicros: preset.durationMicros,
      ),
  ];
}

FocusSettings _decodeFocusSettings(Object? value) {
  if (value is! Map<String, Object?> ||
      !_hasExactKeys(value, const <String>{
        'focusMinutes',
        'shortBreakMinutes',
        'longBreakMinutes',
        'sessionsPerCycle',
      })) {
    throw const FormatException('Invalid focus preset durations.');
  }
  final focusMinutes = value['focusMinutes'];
  final shortBreakMinutes = value['shortBreakMinutes'];
  final longBreakMinutes = value['longBreakMinutes'];
  final sessionsPerCycle = value['sessionsPerCycle'];
  if (focusMinutes is! int ||
      shortBreakMinutes is! int ||
      longBreakMinutes is! int ||
      sessionsPerCycle is! int) {
    throw const FormatException('Invalid focus preset durations.');
  }
  final settings = FocusSettings(
    focusMinutes: focusMinutes,
    shortBreakMinutes: shortBreakMinutes,
    longBreakMinutes: longBreakMinutes,
    sessionsPerCycle: sessionsPerCycle,
  );
  if (!settings.isValid) {
    throw const FormatException('Invalid focus preset durations.');
  }
  return settings;
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> keys) =>
    value.length == keys.length &&
    value.keys.every((String key) => keys.contains(key));

bool _isValidId(String id, int maxLength) {
  if (id.isEmpty || id.length > maxLength || id != id.trim()) return false;
  for (final unit in id.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  return true;
}
