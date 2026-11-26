import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_database.dart';
import '../core/storage/session_record.dart';
import '../core/time/boot_clock.dart';
import '../core/time/timer_checkpoint.dart';
import '../features/settings/app_settings.dart';

final databaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase.open();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final startupProvider = FutureProvider<StartupData>((ref) async {
  final database = ref.watch(databaseProvider);
  final storedSettings = await database.readState('settings');
  final focus = await database.readState('focus');
  final clock = await database.readState('clock');
  final focusCheckpoint = TimerCheckpoint.decode(focus);
  final clockCheckpoint = TimerCheckpoint.decode(clock);
  final hasCheckpoint = focusCheckpoint != null || clockCheckpoint != null;
  final nativeTime = hasCheckpoint ? await BootClock.sample() : null;
  final now = DateTime.now().toUtc();
  return StartupData(
    settings: storedSettings == null
        ? const AppSettings()
        : AppSettings.decode(storedSettings),
    focus: focusCheckpoint?.snapshot ?? focus,
    clock: clockCheckpoint?.snapshot ?? clock,
    focusRecoveryNow: focusCheckpoint?.recoveryTime(now, nativeTime),
    clockRecoveryNow: clockCheckpoint?.recoveryTime(now, nativeTime),
    companion: await database.readState('companion'),
    sessions: await database.sessions(),
  );
});

class StartupData {
  const StartupData({
    required this.settings,
    required this.focus,
    required this.clock,
    required this.companion,
    required this.sessions,
    this.focusRecoveryNow,
    this.clockRecoveryNow,
  });

  final AppSettings settings;
  final String? focus;
  final String? clock;
  final String? companion;
  final List<SessionRecord> sessions;
  final DateTime? focusRecoveryNow;
  final DateTime? clockRecoveryNow;
}
