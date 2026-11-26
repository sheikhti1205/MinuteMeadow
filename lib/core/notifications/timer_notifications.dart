import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class TimerNotifications {
  static const focusId = 1;
  static const countdownId = 2;

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool?>? _initializing;

  Future<void> _initialize() async {
    await (_initializing ??= _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_timer_notification'),
      ),
    ));
  }

  Future<bool> requestPermission() async {
    if (!available) return false;
    await _initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> schedule({
    required int id,
    required DateTime? deadline,
    required String title,
    required bool enabled,
    required bool sound,
  }) async {
    if (!available) return;
    await _initialize();
    await _plugin.cancel(id: id);
    if (!enabled || deadline == null || !deadline.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      scheduledDate: tz.TZDateTime.from(deadline, tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          sound ? 'timer_completion' : 'timer_completion_silent',
          sound ? 'Timer completion' : 'Silent timer completion',
          channelDescription: 'Focus, break and countdown alerts',
          playSound: sound,
          enableVibration: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
