import 'package:companion_focus/features/clock/clock_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats minutes and seconds with optional tenths', () {
    expect(formatClock(Duration.zero, tenths: true), '00:00.0');
    expect(formatClock(Duration.zero), '00:00');
    expect(
      formatClock(const Duration(minutes: 5, seconds: 3), tenths: true),
      '05:03.0',
    );
    expect(
      formatClock(
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 400),
        tenths: true,
      ),
      '1:02:03.4',
    );
    expect(
      formatClock(const Duration(hours: 2, minutes: 5)),
      '2:05:00',
    );
  });

  test('clamps negative durations to zero', () {
    expect(formatClock(const Duration(seconds: -5), tenths: true), '00:00.0');
  });
}
