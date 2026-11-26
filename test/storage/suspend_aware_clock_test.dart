import 'package:companion_focus/core/time/boot_clock.dart';
import 'package:companion_focus/core/time/suspend_aware_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compensates for elapsed realtime that the process clock missed', () async {
    var process = const Duration(minutes: 2);
    var native = const Duration(minutes: 12);
    final clock = SuspendAwareClock(
      processElapsed: () => process,
      readBoot: () async => BootSample(bootCount: 4, elapsed: native),
    );
    clock.markBackground();
    await Future<void>.value();
    process += const Duration(seconds: 1);
    native += const Duration(minutes: 1);
    await clock.resume();
    expect(clock.elapsed, const Duration(minutes: 3));
    await clock.resume();
    expect(clock.elapsed, const Duration(minutes: 3));
  });
}
