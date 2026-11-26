import 'dart:convert';

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

/// Configurable timer defaults. Minutes are validated by the settings surface
/// that owns them; the engine refuses to start a non-positive duration.
class FocusSettings {
  const FocusSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
  });

  static const defaults = FocusSettings();

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  Duration durationFor(FocusPhase phase) => phase.durationFor(this);

  FocusSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
  }) => FocusSettings(
    focusMinutes: focusMinutes ?? this.focusMinutes,
    shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
    longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
  );
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
  });

  static const _version = 1;
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

  String encode() => jsonEncode(<String, Object?>{
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

    final phase = _phaseFrom(decoded['phase']);
    final status = _statusFrom(decoded['status']);
    final intendedMs = decoded['intendedMs'];
    final completedCount = decoded['completedFocusSessions'];
    if (decoded['version'] != _version || phase == null || status == null) {
      return null;
    }
    if (intendedMs is! int ||
        intendedMs <= 0 ||
        intendedMs > _maxIntendedMs) {
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

  FocusStatus get status => _status;
  FocusPhase get phase => _phase;
  String get id => _id;
  DateTime? get startedAt => _startedAt;
  DateTime? get finishedAt => _finishedAt;
  Duration get intended => _intended;
  int get completedFocusSessions => _completedFocusSessions;
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
        return _phase == FocusPhase.focus ? 'Focus complete' : 'Break complete';
      case FocusStatus.cancelled:
        return _phase == FocusPhase.focus
            ? 'Session cancelled'
            : 'Break cancelled';
    }
  }

  /// A long break follows every fourth completed focus session.
  FocusPhase get nextBreakPhase {
    final inCycle = _completedFocusSessions % 4;
    return _completedFocusSessions > 0 && inCycle == 0
        ? FocusPhase.longBreak
        : FocusPhase.shortBreak;
  }

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
    }
  }

  void startFocus() {
    if (hasActiveSession) {
      throw StateError('A timer is already running.');
    }
    _begin(FocusPhase.focus);
  }

  void startBreak() {
    if (_status != FocusStatus.completed || _phase != FocusPhase.focus) {
      throw StateError('A break can start only after a focus session completes.');
    }
    _begin(nextBreakPhase);
  }

  void skipBreak() {
    if (_status != FocusStatus.completed || _phase != FocusPhase.focus) {
      throw StateError('No completed focus session is waiting for a break.');
    }
    _phase = FocusPhase.focus;
    _status = FocusStatus.ready;
    _id = '';
    _startedAt = null;
    _anchor = null;
    _finishedAt = null;
    _intended = _settings.durationFor(_phase);
    _accumulated = Duration.zero;
    _pausedRemaining = Duration.zero;
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
    return _finish(completed: false);
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
    );
  }

  String encodeSnapshot() => snapshot().encode();

  void _begin(FocusPhase phase) {
    final now = _clock.nowUtc();
    final intended = _settings.durationFor(phase);
    if (intended <= Duration.zero) {
      throw StateError('${phase.label} duration must be positive.');
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
        _phase = snapshot.phase;
        _status = snapshot.status;
        _intended = _settings.durationFor(_phase);
        return;
      case FocusStatus.running:
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
        _phase = snapshot.phase;
        _id = snapshot.id;
        _startedAt = snapshot.startedAt;
        _anchor = snapshot.anchor;
        _intended = snapshot.intended;
        _accumulated = _intended;
        _status = FocusStatus.completed;
        final startedAt = snapshot.startedAt ?? snapshot.finishedAt!;
        final savedFinishedAt = snapshot.finishedAt!;
        final finishedAt = savedFinishedAt.isBefore(startedAt)
            ? startedAt
            : savedFinishedAt;
        _finishedAt = finishedAt;
        _lastOutcome = FocusOutcome(
          id: snapshot.id,
          startedAt: startedAt,
          finishedAt: finishedAt,
          intended: snapshot.intended,
          actual: snapshot.intended,
          completed: true,
        );
        return;
      case FocusStatus.cancelled:
        _phase = FocusPhase.focus;
        _status = FocusStatus.ready;
        _intended = _settings.durationFor(_phase);
        return;
    }
  }

  String _newId() {
    final createId = _createId;
    if (createId != null) return createId();
    final stamp = _clock.nowUtc().microsecondsSinceEpoch;
    return 'focus-$stamp-${_idSequence++}';
  }
}
