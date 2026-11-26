import 'package:companion_focus/core/time/boot_clock.dart';
import 'package:companion_focus/core/time/timer_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same Android boot ignores a manual wall-clock adjustment', () {
    final saved = TimerCheckpoint(
      snapshot: '{"running":true}',
      wallTime: DateTime.utc(2026, 11, 26, 12),
      boot: const BootSample(bootCount: 41, elapsed: Duration(hours: 2)),
    );
    final decoded = TimerCheckpoint.decode(saved.encode())!;
    expect(decoded.snapshot, '{"running":true}');
    expect(
      decoded.recoveryTime(
        DateTime.utc(2026, 11, 26, 8),
        const BootSample(bootCount: 41, elapsed: Duration(hours: 2, minutes: 4)),
      ),
      DateTime.utc(2026, 11, 26, 12, 4),
    );
  });

  test('new Android boot falls back to the UTC wall clock', () {
    final saved = TimerCheckpoint(
      snapshot: '{}',
      wallTime: DateTime.utc(2026, 11, 26, 12),
      boot: const BootSample(bootCount: 41, elapsed: Duration(hours: 2)),
    );
    final now = DateTime.utc(2026, 11, 26, 13);
    expect(
      saved.recoveryTime(now, const BootSample(bootCount: 42, elapsed: Duration(minutes: 5))),
      now,
    );
  });
}
