import 'dart:convert';

import 'boot_clock.dart';

class TimerCheckpoint {
  const TimerCheckpoint({
    required this.snapshot,
    required this.wallTime,
    required this.boot,
  });

  final String snapshot;
  final DateTime wallTime;
  final BootSample? boot;

  static Future<TimerCheckpoint> capture(String snapshot) async {
    final time = DateTime.now().toUtc();
    return TimerCheckpoint(snapshot: snapshot, wallTime: time, boot: await BootClock.sample());
  }

  String encode() => jsonEncode({
    'timerCheckpoint': 1,
    'snapshot': snapshot,
    'wallMs': wallTime.millisecondsSinceEpoch,
    if (boot case final sample?)
      'boot': {
        'count': sample.bootCount,
        'elapsedMs': sample.elapsed.inMilliseconds,
      },
  });

  static TimerCheckpoint? decode(String? source) {
    if (source == null) return null;
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (json case {
      'timerCheckpoint': 1,
      'snapshot': final String snapshot,
      'wallMs': final int wallMs,
    }) {
      final boot = (json as Map<String, Object?>)['boot'];
      return TimerCheckpoint(
        snapshot: snapshot,
        wallTime: DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true),
        boot: switch (boot) {
          {'count': final int count, 'elapsedMs': final int elapsedMs}
              when count >= 0 && elapsedMs >= 0 => BootSample(
                bootCount: count,
                elapsed: Duration(milliseconds: elapsedMs),
              ),
          _ => null,
        },
      );
    }
    return null;
  }

  DateTime recoveryTime(DateTime wallNow, BootSample? current) {
    final saved = boot;
    if (saved == null || current == null || saved.bootCount != current.bootCount ||
        current.elapsed < saved.elapsed) {
      return wallNow;
    }
    return wallTime.add(current.elapsed - saved.elapsed);
  }
}
