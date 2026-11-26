/// Formats a duration as `mm:ss` or `h:mm:ss`, optionally with tenths.
///
/// Negative durations clamp to zero so a countdown never renders a negative
/// figure.
String formatClock(Duration duration, {bool tenths = false}) {
  final micros = duration.inMicroseconds;
  final safeMicros = micros < 0 ? 0 : micros;
  final hours = safeMicros ~/ Duration.microsecondsPerHour;
  final minutes =
      (safeMicros ~/ Duration.microsecondsPerMinute) % Duration.minutesPerHour;
  final seconds =
      (safeMicros ~/ Duration.microsecondsPerSecond) % Duration.secondsPerMinute;
  final tenth = (safeMicros ~/ 100000) % 10;

  final buffer = StringBuffer();
  if (hours > 0) {
    buffer
      ..write(hours)
      ..write(':');
  }
  buffer
    ..write(minutes.toString().padLeft(2, '0'))
    ..write(':')
    ..write(seconds.toString().padLeft(2, '0'));
  if (tenths) {
    buffer
      ..write('.')
      ..write(tenth);
  }
  return buffer.toString();
}
