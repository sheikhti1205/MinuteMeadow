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
  bool _running = false;
  int _accumulatedMicros = 0;
  int? _startedAtMicros;
  int _countdownMicros = defaultCountdownMicros;
  int _completionCount = 0;
  String? _selectedPresetId;
  final List<ClockPreset> _presets = <ClockPreset>[];
  final List<ClockLap> _laps = <ClockLap>[];

  ClockMode get mode => _mode;
  bool get isRunning => _running;
  int get completionCount => _completionCount;
  int get countdownMicros => _countdownMicros;
  Duration get countdownDuration =>
      Duration(microseconds: _countdownMicros);
  String? get selectedPresetId => _selectedPresetId;

  List<ClockPreset> get presets => List<ClockPreset>.unmodifiable(_presets);
  List<ClockLap> get laps => List<ClockLap>.unmodifiable(_laps);

  Duration get elapsed => Duration(microseconds: _elapsedAt(nowMicroseconds()));

  Duration get remaining {
    if (_mode != ClockMode.countdown) {
      return Duration.zero;
    }
    final value = _countdownMicros - _elapsedAt(nowMicroseconds());
    return Duration(microseconds: value > 0 ? value : 0);
  }

  bool get isComplete =>
      _mode == ClockMode.countdown &&
      _elapsedAt(nowMicroseconds()) >= _countdownMicros;

  bool get hasProgress => _elapsedAt(nowMicroseconds()) > 0 || _laps.isNotEmpty;

  void start() {
    if (_running) {
      return;
    }
    final now = nowMicroseconds();
    if (_mode == ClockMode.countdown && _elapsedAt(now) >= _countdownMicros) {
      _accumulatedMicros = 0;
      _laps.clear();
    }
    _startedAtMicros = now;
    _running = true;
  }

  void pause() {
    if (!_running) {
      return;
    }
    if (_mode == ClockMode.countdown) {
      final now = nowMicroseconds();
      final startedAt = _startedAtMicros;
      final raw = _accumulatedMicros +
          (startedAt != null && now > startedAt ? now - startedAt : 0);
      if (raw >= _countdownMicros) {
        update();
        return;
      }
    }
    _accumulatedMicros = _elapsedAt(nowMicroseconds());
    _startedAtMicros = null;
    _running = false;
  }

  void toggle() {
    if (_running) {
      pause();
    } else {
      start();
    }
  }

  /// Settles a countdown that has reached its duration.
  ///
  /// Completion fires the optional callback exactly once. A timer that is
  /// already stopped, or a stopwatch, is left untouched.
  void update() {
    if (!_running || _mode != ClockMode.countdown) {
      return;
    }
    final startedAt = _startedAtMicros;
    if (startedAt == null) {
      return;
    }
    final now = nowMicroseconds();
    final raw =
        _accumulatedMicros + (now > startedAt ? now - startedAt : 0);
    if (raw < _countdownMicros) {
      return;
    }
    _accumulatedMicros = _countdownMicros;
    _startedAtMicros = null;
    _running = false;
    _completionCount++;
    onCountdownComplete?.call();
  }

  void reset() {
    _running = false;
    _startedAtMicros = null;
    _accumulatedMicros = 0;
    _laps.clear();
  }

  void setMode(ClockMode mode) {
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    _running = false;
    _startedAtMicros = null;
    _accumulatedMicros = 0;
    _laps.clear();
  }

  /// Sets the countdown duration and returns to a ready state.
  void setCountdownDuration(Duration duration) {
    _mode = ClockMode.countdown;
    _countdownMicros = _clampDuration(duration.inMicroseconds);
    _running = false;
    _startedAtMicros = null;
    _accumulatedMicros = 0;
    _laps.clear();
    _selectedPresetId = null;
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
    if (_mode != ClockMode.stopwatch || !_running) {
      return null;
    }
    final total = _elapsedAt(nowMicroseconds());
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
      'version': 1,
      'mode': _mode.name,
      'running': _running,
      'accumulatedMicros': _elapsedAt(now),
      'savedAtMicros': now,
      'savedAtUtcMicros': wallClock().toUtc().microsecondsSinceEpoch,
      'process': processToken,
      'countdownMicros': _countdownMicros,
      'selectedPresetId': _selectedPresetId,
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

  int _elapsedAt(int now) {
    var value = _accumulatedMicros;
    final startedAt = _startedAtMicros;
    if (_running && startedAt != null && now > startedAt) {
      value += now - startedAt;
    }
    if (_mode == ClockMode.countdown && value > _countdownMicros) {
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
    final minutes = micros ~/ Duration.microsecondsPerMinute;
    if (minutes >= 1) {
      return '$minutes min';
    }
    return '${micros ~/ Duration.microsecondsPerSecond} sec';
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

    final accumulated = decoded['accumulatedMicros'];
    if (accumulated is! num) {
      return;
    }

    final now = nowMicroseconds();
    var restoredElapsed = accumulated.toInt();
    if (restoredElapsed < 0) {
      restoredElapsed = 0;
    }
    if (_mode == ClockMode.countdown &&
        restoredElapsed > _countdownMicros) {
      restoredElapsed = _countdownMicros;
    }

    var running = decoded['running'] == true;
    if (running) {
      final savedAt = decoded['savedAtMicros'];
      final sameProcess =
          decoded['process'] is String && decoded['process'] == processToken;
      var bridged = false;
      if (sameProcess) {
        if (savedAt is num && now > savedAt.toInt()) {
          restoredElapsed += now - savedAt.toInt();
        }
        bridged = true;
      }
      if (!bridged && recoveryNow != null) {
        final savedAtUtc = decoded['savedAtUtcMicros'];
        if (savedAtUtc is num) {
          final gap = recoveryNow.toUtc().microsecondsSinceEpoch -
              savedAtUtc.toInt();
          if (gap > 0) {
            restoredElapsed += gap;
          }
        }
      }
      if (_mode == ClockMode.countdown &&
          restoredElapsed >= _countdownMicros) {
        restoredElapsed = _countdownMicros;
        running = false;
      }
    }

    _accumulatedMicros = restoredElapsed;
    _running = running;
    _startedAtMicros = running ? now : null;
  }
}
