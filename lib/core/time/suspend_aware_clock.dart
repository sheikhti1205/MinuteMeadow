import 'boot_clock.dart';

typedef _ClockReading = ({BootSample? boot, Duration process});

class SuspendAwareClock {
  SuspendAwareClock({
    Duration Function()? processElapsed,
    Future<BootSample?> Function()? readBoot,
  }) : _processElapsed = processElapsed ?? _runningStopwatch(),
       _readBoot = readBoot ?? BootClock.sample;

  final Duration Function() _processElapsed;
  final Future<BootSample?> Function() _readBoot;
  Duration _suspended = Duration.zero;
  Future<_ClockReading>? _background;
  Future<void> _resume = Future<void>.value();

  Duration get elapsed => _processElapsed() + _suspended;

  void markBackground() {
    _background ??= _reading();
  }

  Future<void> resume() {
    final anchor = _background;
    if (anchor == null) return _resume;
    _background = null;
    final resumedAt = _reading();
    return _resume = _resume.then((_) async {
      final before = await anchor;
      final after = await resumedAt;
      final first = before.boot;
      final last = after.boot;
      if (first == null || last == null || first.bootCount != last.bootCount) {
        return;
      }
      final nativeGap = last.elapsed - first.elapsed;
      final processGap = after.process - before.process;
      final difference = nativeGap - processGap;
      if (difference > const Duration(milliseconds: 100)) {
        _suspended += difference;
      }
    });
  }

  Future<_ClockReading> _reading() async {
    final boot = await _readBoot();
    return (boot: boot, process: _processElapsed());
  }

  static Duration Function() _runningStopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
