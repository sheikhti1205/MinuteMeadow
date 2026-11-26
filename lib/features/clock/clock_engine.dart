import 'dart:convert';

/// The two independent timing modes owned by the Clock feature.
enum ClockMode { stopwatch, countdown }

/// A saved countdown duration.
class ClockPreset {
  const ClockPreset({
    required this.id,
    required this.label,
    required this.durationMicros,
  });

  final String id;
  final String label;
  final int durationMicros;
}

/// A recorded stopwatch lap with both its total and split duration.
class ClockLap {
  const ClockLap({
    required this.index,
    required this.totalMicros,
    required this.splitMicros,
  });

  final int index;
  final int totalMicros;
  final int splitMicros;
}

/// Monotonic clock engine for the stopwatch and countdown.
///
/// Elapsed time is derived from an injected monotonic microsecond counter, so
/// wall-clock changes do not affect a running measurement. Snapshots store an
/// absolute monotonic anchor plus a process token: the same process can bridge
/// a background gap, while a restarted process resumes from the saved elapsed
/// time. A trusted [recoveryNow] wall reference (for example one derived from
/// Android's `elapsedRealtime`) can bridge the dead gap across a restart.
///
/// The stopwatch and the countdown keep separate state. Switching the visible
/// [mode] never clears either measurement, so a running countdown can keep
/// counting behind the stopwatch and vice versa.
class ClockEngine {
  ClockEngine({
    required this.nowMicroseconds,
    String? initialSnapshot,
    this.onCountdownComplete,
    String? processToken,
    DateTime Function()? wallClock,
    DateTime? recoveryNow,
  }) : processToken = processToken ?? _defaultProcessToken,
       wallClock = wallClock ?? DateTime.now {
    _restore(initialSnapshot, recoveryNow);
  }

  static const int defaultCountdownMicros = 25 * 60 * 1000000;
  static const int _minimumDurationMicros = 1000000;
  static const int _maximumDurationMicros = 24 * 60 * 60 * 1000000;

  static final String _defaultProcessToken =
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${identityHashCode(Object())}';

  final int Function() nowMicroseconds;
  final void Function()? onCountdownComplete;
  final String processToken;

  /// Wall clock used only to stamp snapshots for cross-process recovery.
  final DateTime Function() wallClock;

  ClockMode _mode = ClockMode.stopwatch;

  bool _stopwatchRunning = false;
  int _stopwatchAccumulatedMicros = 0;
  int? _stopwatchStartedAtMicros;

  bool _countdownRunning = false;
  int _countdownAccumulatedMicros = 0;
  int? _countdownStartedAtMicros;
  int _countdownMicros = defaultCountdownMicros;

  int _completionCount = 0;
  String? _selectedPresetId;
  final List<ClockPreset> _presets = <ClockPreset>[];
  final List<ClockLap> _laps = <ClockLap>[];

  ClockMode get mode => _mode;

  /// Whether the visible mode is measuring.
  bool get isRunning => _mode == ClockMode.stopwatch
      ? _stopwatchRunning
      : _countdownRunning;

  bool get isStopwatchRunning => _stopwatchRunning;
  bool get isCountdownRunning => _countdownRunning;

  /// Whether either measurement is running, so the host keeps ticking.
  bool get hasRunningMeasurement => _stopwatchRunning || _countdownRunning;

  int get completionCount => _completionCount;
  int get countdownMicros => _countdownMicros;
  Duration get countdownDuration => Duration(microseconds: _countdownMicros);
  String? get selectedPresetId => _selectedPresetId;

  List<ClockPreset> get presets => List<ClockPreset>.unmodifiable(_presets);
  List<ClockLap> get laps => List<ClockLap>.unmodifiable(_laps);

  /// Elapsed time of the visible mode.
  Duration get elapsed => Duration(microseconds: _elapsedAt(nowMicroseconds()));

  Duration get stopwatchElapsed =>
      Duration(microseconds: _stopwatchElapsedAt(nowMicroseconds()));

  Duration get countdownElapsed =>
      Duration(microseconds: _countdownElapsedAt(nowMicroseconds()));

  /// Remaining countdown time, independent of the visible mode so a host can
  /// keep a scheduled alert anchored while the stopwatch is shown.
  Duration get remaining {
    final value = _countdownMicros - _countdownElapsedAt(nowMicroseconds());
    return Duration(microseconds: value > 0 ? value : 0);
  }

  bool get isCountdownComplete =>
      _countdownElapsedAt(nowMicroseconds()) >= _countdownMicros;

  bool get isComplete =>
      _mode == ClockMode.countdown && isCountdownComplete;

  bool get stopwatchHasProgress =>
      _stopwatchElapsedAt(nowMicroseconds()) > 0 || _laps.isNotEmpty;

  bool get countdownHasProgress =>
      _countdownElapsedAt(nowMicroseconds()) > 0;

  bool get hasProgress => _mode == ClockMode.stopwatch
      ? stopwatchHasProgress
      : countdownHasProgress;

  void start() {
    if (_mode == ClockMode.stopwatch) {
      if (_stopwatchRunning) {
        return;
      }
      _stopwatchStartedAtMicros = nowMicroseconds();
      _stopwatchRunning = true;
      return;
    }
    if (_countdownRunning) {
      return;
    }
    final now = nowMicroseconds();
    if (_countdownElapsedAt(now) >= _countdownMicros) {
      _countdownAccumulatedMicros = 0;
      _countdownStartedAtMicros = null;
    }
    _countdownStartedAtMicros = now;
    _countdownRunning = true;
  }

  void pause() {
    if (_mode == ClockMode.stopwatch) {
      if (!_stopwatchRunning) {
        return;
      }
      _stopwatchAccumulatedMicros = _stopwatchElapsedAt(nowMicroseconds());
      _stopwatchStartedAtMicros = null;
      _stopwatchRunning = false;
      return;
    }
    if (!_countdownRunning) {
      return;
    }
    final now = nowMicroseconds();
    final raw = _countdownElapsedAt(now);
    if (raw >= _countdownMicros) {
      update();
      return;
    }
    _countdownAccumulatedMicros = raw;
    _countdownStartedAtMicros = null;
    _countdownRunning = false;
  }

  void toggle() {
    if (isRunning) {
      pause();
    } else {
      start();
    }
  }

  /// Settles a countdown that has reached its duration.
  ///
  /// Completion fires the optional callback exactly once, even when the
  /// stopwatch is the visible mode. A timer that is already stopped is left
  /// untouched.
  void update() {
    if (!_countdownRunning) {
      return;
    }
    final startedAt = _countdownStartedAtMicros;
    if (startedAt == null) {
      return;
    }
    final now = nowMicroseconds();
    final raw = _countdownAccumulatedMicros +
        (now > startedAt ? now - startedAt : 0);
    if (raw < _countdownMicros) {
      return;
    }
    _countdownAccumulatedMicros = _countdownMicros;
    _countdownStartedAtMicros = null;
    _countdownRunning = false;
    _completionCount++;
    onCountdownComplete?.call();
  }

  /// Clears the visible measurement only; the other mode keeps its work.
  void reset() {
    if (_mode == ClockMode.stopwatch) {
      _stopwatchRunning = false;
      _stopwatchStartedAtMicros = null;
      _stopwatchAccumulatedMicros = 0;
      _laps.clear();
      return;
    }
    _countdownRunning = false;
    _countdownStartedAtMicros = null;
    _countdownAccumulatedMicros = 0;
  }

  /// Shows [mode] without clearing either measurement.
  ///
  /// The page owns any confirmation for replacing a countdown duration; a
  /// mode switch on its own is always non-destructive.
  void setMode(ClockMode mode) {
    _mode = mode;
  }

  /// Sets the countdown duration and returns the countdown to a ready state.
  ///
  /// The stopwatch and its laps are untouched.
  void setCountdownDuration(Duration duration) {
    _mode = ClockMode.countdown;
    _countdownMicros = _clampDuration(duration.inMicroseconds);
    _countdownRunning = false;
    _countdownStartedAtMicros = null;
    _countdownAccumulatedMicros = 0;
    _selectedPresetId = null;
  }

  /// Restarts a completed countdown using its original duration.
  ///
  /// Returns false when the countdown has not reached zero, so the explicit
  /// Repeat action cannot silently discard remaining time.
  bool repeatCountdown() {
    if (!isCountdownComplete) {
      return false;
    }
    _mode = ClockMode.countdown;
    _countdownAccumulatedMicros = 0;
    _countdownStartedAtMicros = nowMicroseconds();
    _countdownRunning = true;
    return true;
  }

  ClockPreset addPreset({
    required String label,
    required Duration duration,
  }) {
    final micros = _clampDuration(duration.inMicroseconds);
    final trimmed = label.trim();
    final preset = ClockPreset(
      id: _nextPresetId(),
      label: trimmed.isEmpty ? _defaultPresetLabel(micros) : trimmed,
      durationMicros: micros,
    );
    _presets.add(preset);
    return preset;
  }

  /// Renames or re-times an existing preset.
  ///
  /// A ready countdown that uses the preset adopts the new duration. A
  /// countdown with progress keeps its current duration, and the selection is
  /// cleared so the saved preset no longer claims to describe it.
  bool updatePreset({
    required String id,
    required String label,
    required Duration duration,
  }) {
    final index = _presets.indexWhere((preset) => preset.id == id);
    if (index < 0) {
      return false;
    }
    final previous = _presets[index];
    final micros = _clampDuration(duration.inMicroseconds);
    final trimmed = label.trim();
    _presets[index] = ClockPreset(
      id: id,
      label: trimmed.isEmpty ? _defaultPresetLabel(micros) : trimmed,
      durationMicros: micros,
    );
    if (_selectedPresetId == id && micros != previous.durationMicros) {
      final untouched =
          !_countdownRunning && _countdownElapsedAt(nowMicroseconds()) == 0;
      if (untouched) {
        _countdownMicros = micros;
      } else {
        _selectedPresetId = null;
      }
    }
    return true;
  }

  bool deletePreset(String id) {
    final before = _presets.length;
    _presets.removeWhere((preset) => preset.id == id);
    if (_selectedPresetId == id) {
      _selectedPresetId = null;
    }
    return _presets.length != before;
  }

  bool selectPreset(String id) {
    for (final preset in _presets) {
      if (preset.id == id) {
        setCountdownDuration(Duration(microseconds: preset.durationMicros));
        _selectedPresetId = id;
        return true;
      }
    }
    return false;
  }

  ClockLap? addLap() {
    if (!_stopwatchRunning) {
      return null;
    }
    final total = _stopwatchElapsedAt(nowMicroseconds());
    final previous = _laps.isEmpty ? 0 : _laps.last.totalMicros;
    final lap = ClockLap(
      index: _laps.length + 1,
      totalMicros: total,
      splitMicros: total - previous,
    );
    _laps.add(lap);
    return lap;
  }

  String snapshot() {
    final now = nowMicroseconds();
    return jsonEncode(<String, Object?>{
      'version': 2,
      'mode': _mode.name,
      // Top-level running and accumulated fields keep older readers working
      // for the visible mode.
      'running': isRunning,
      'accumulatedMicros': _elapsedAt(now),
      'savedAtMicros': now,
      'savedAtUtcMicros': wallClock().toUtc().microsecondsSinceEpoch,
      'process': processToken,
      'countdownMicros': _countdownMicros,
      'selectedPresetId': _selectedPresetId,
      'stopwatch': <String, Object?>{
        'running': _stopwatchRunning,
        'accumulatedMicros': _stopwatchElapsedAt(now),
      },
      'countdown': <String, Object?>{
        'running': _countdownRunning,
        'accumulatedMicros': _countdownElapsedAt(now),
      },
      'laps': <Map<String, Object?>>[
        for (final lap in _laps)
          <String, Object?>{
            'index': lap.index,
            'totalMicros': lap.totalMicros,
            'splitMicros': lap.splitMicros,
          },
      ],
      'presets': <Map<String, Object?>>[
        for (final preset in _presets)
          <String, Object?>{
            'id': preset.id,
            'label': preset.label,
            'durationMicros': preset.durationMicros,
          },
      ],
    });
  }

  int _elapsedAt(int now) => _mode == ClockMode.stopwatch
      ? _stopwatchElapsedAt(now)
      : _countdownElapsedAt(now);

  int _stopwatchElapsedAt(int now) {
    var value = _stopwatchAccumulatedMicros;
    final startedAt = _stopwatchStartedAtMicros;
    if (_stopwatchRunning && startedAt != null && now > startedAt) {
      value += now - startedAt;
    }
    return value;
  }

  int _countdownElapsedAt(int now) {
    var value = _countdownAccumulatedMicros;
    final startedAt = _countdownStartedAtMicros;
    if (_countdownRunning && startedAt != null && now > startedAt) {
      value += now - startedAt;
    }
    if (value > _countdownMicros) {
      value = _countdownMicros;
    }
    return value;
  }

  int _clampDuration(int micros) {
    if (micros < _minimumDurationMicros) {
      return _minimumDurationMicros;
    }
    if (micros > _maximumDurationMicros) {
      return _maximumDurationMicros;
    }
    return micros;
  }

  String _nextPresetId() {
    var index = 1;
    while (_presets.any((preset) => preset.id == 'preset-$index')) {
      index++;
    }
    return 'preset-$index';
  }

  String _defaultPresetLabel(int micros) {
    final duration = Duration(microseconds: micros);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % Duration.minutesPerHour;
    final seconds = duration.inSeconds % Duration.secondsPerMinute;
    if (hours > 0) {
      if (minutes == 0 && seconds == 0) {
        return '$hours h';
      }
      if (seconds == 0) {
        return '$hours h $minutes min';
      }
      return '$hours h $minutes min $seconds sec';
    }
    if (minutes >= 1) {
      if (seconds == 0) {
        return '$minutes min';
      }
      return '$minutes min $seconds sec';
    }
    return '$seconds sec';
  }

  void _restore(String? source, DateTime? recoveryNow) {
    if (source == null) {
      return;
    }
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final mode = decoded['mode'];
    if (mode is! String) {
      return;
    }
    final restoredMode = switch (mode) {
      'stopwatch' => ClockMode.stopwatch,
      'countdown' => ClockMode.countdown,
      _ => null,
    };
    if (restoredMode == null) {
      return;
    }
    _mode = restoredMode;

    final countdown = decoded['countdownMicros'];
    if (countdown is num) {
      _countdownMicros = _clampDuration(countdown.toInt());
    }

    final presets = decoded['presets'];
    if (presets is List) {
      for (final item in presets) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final id = item['id'];
        final label = item['label'];
        final duration = item['durationMicros'];
        if (id is! String || label is! String || duration is! num) {
          continue;
        }
        if (_presets.any((preset) => preset.id == id)) {
          continue;
        }
        _presets.add(
          ClockPreset(
            id: id,
            label: label,
            durationMicros: _clampDuration(duration.toInt()),
          ),
        );
      }
    }

    final laps = decoded['laps'];
    if (laps is List) {
      var previousTotal = 0;
      for (final item in laps) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final total = item['totalMicros'];
        final split = item['splitMicros'];
        if (total is! num || split is! num) {
          continue;
        }
        final totalMicros = total.toInt();
        final splitMicros = split.toInt();
        if (totalMicros < previousTotal) {
          continue;
        }
        _laps.add(
          ClockLap(
            index: _laps.length + 1,
            totalMicros: totalMicros,
            splitMicros: splitMicros < 0 ? 0 : splitMicros,
          ),
        );
        previousTotal = totalMicros;
      }
    }

    final selectedPreset = decoded['selectedPresetId'];
    if (selectedPreset is String &&
        _presets.any((preset) => preset.id == selectedPreset)) {
      _selectedPresetId = selectedPreset;
    }

    final now = nowMicroseconds();
    final savedAt = decoded['savedAtMicros'];
    final savedAtMicros = savedAt is num ? savedAt.toInt() : null;
    final savedAtUtc = decoded['savedAtUtcMicros'];
    final savedAtUtcMicros = savedAtUtc is num ? savedAtUtc.toInt() : null;
    final sameProcess =
        decoded['process'] is String && decoded['process'] == processToken;

    final version = decoded['version'] is num
        ? (decoded['version'] as num).toInt()
        : 1;

    Object? stopwatchRaw;
    Object? countdownRaw;
    if (version >= 2) {
      stopwatchRaw = decoded['stopwatch'];
      countdownRaw = decoded['countdown'];
    } else {
      final legacy = <String, Object?>{
        'running': decoded['running'],
        'accumulatedMicros': decoded['accumulatedMicros'],
      };
      if (restoredMode == ClockMode.stopwatch) {
        stopwatchRaw = legacy;
      } else {
        countdownRaw = legacy;
      }
    }

    final stopwatch = _restoreMeasurement(
      stopwatchRaw,
      now: now,
      isCountdown: false,
      sameProcess: sameProcess,
      savedAtMicros: savedAtMicros,
      savedAtUtcMicros: savedAtUtcMicros,
      recoveryNow: recoveryNow,
    );
    _stopwatchAccumulatedMicros = stopwatch.accumulated;
    _stopwatchRunning = stopwatch.running;
    _stopwatchStartedAtMicros = stopwatch.running ? now : null;

    final countdownRestored = _restoreMeasurement(
      countdownRaw,
      now: now,
      isCountdown: true,
      sameProcess: sameProcess,
      savedAtMicros: savedAtMicros,
      savedAtUtcMicros: savedAtUtcMicros,
      recoveryNow: recoveryNow,
    );
    _countdownAccumulatedMicros = countdownRestored.accumulated;
    _countdownRunning = countdownRestored.running;
    _countdownStartedAtMicros = countdownRestored.running ? now : null;
  }

  ({int accumulated, bool running}) _restoreMeasurement(
    Object? raw, {
    required int now,
    required bool isCountdown,
    required bool sameProcess,
    required int? savedAtMicros,
    required int? savedAtUtcMicros,
    required DateTime? recoveryNow,
  }) {
    var accumulated = 0;
    var running = false;
    if (raw is Map<Object?, Object?>) {
      final value = raw['accumulatedMicros'];
      if (value is num) {
        accumulated = value.toInt();
      }
      running = raw['running'] == true;
    }
    if (accumulated < 0) {
      accumulated = 0;
    }

    if (running) {
      var bridged = false;
      if (sameProcess) {
        if (savedAtMicros != null && now > savedAtMicros) {
          accumulated += now - savedAtMicros;
        }
        bridged = true;
      }
      if (!bridged && recoveryNow != null && savedAtUtcMicros != null) {
        final gap = recoveryNow.toUtc().microsecondsSinceEpoch -
            savedAtUtcMicros;
        if (gap > 0) {
          accumulated += gap;
        }
      }
    }

    if (isCountdown) {
      if (accumulated > _countdownMicros) {
        accumulated = _countdownMicros;
      }
      if (running && accumulated >= _countdownMicros) {
        accumulated = _countdownMicros;
        running = false;
      }
    }

    return (accumulated: accumulated, running: running);
  }
}
