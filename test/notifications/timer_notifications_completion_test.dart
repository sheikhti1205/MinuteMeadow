import 'package:companion_focus/core/notifications/timer_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// The method channel the pinned Android plugin talks to.
const _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// The runner channel that carries a foreground completion chime.
const _feedbackChannel = MethodChannel('app.companionfocus/timer_feedback');

/// One deadline every case pins, so a match never depends on the clock.
final _deadline = DateTime.utc(2026, 11, 27, 9, 30);

/// The payload `TimerNotifications.schedule` writes for one timer alert.
///
/// The wire format is restated here on purpose: the payload is the only link
/// between a posted or pending Android notification and the timer it belongs
/// to, so a change to it silently breaks completion matching.
String _payload(int kindBase, DateTime deadline) =>
    'timer-feedback:v1:$kindBase:${deadline.toUtc().millisecondsSinceEpoch}';

/// A posted notification as the plugin's pinned Android host reports it.
///
/// The host returns id, tag, groupKey, channelId, title, body and bigText, and
/// no payload at all, so a posted alert can only be matched by its ID.
Map<String, Object?> _activeNotification(int id) => {
  'id': id,
  'tag': null,
  'groupKey': null,
  'channelId': 'timer_completion_v2',
  'title': 'Focus complete',
  'body': 'Your timer finished.',
  'bigText': null,
};

/// A posted entry the pinned parser accepts without an ID.
Map<String, Object?> _activeNotificationWithoutId() => {
  'channelId': 'timer_completion_v2',
  'title': 'Focus complete',
  'body': 'Your timer finished.',
};

/// A pending alarm as Android reports it to the plugin.
Map<String, Object?> _pendingRequest(int id, String? payload) => {
  'id': id,
  'title': 'Focus complete',
  'body': 'Your timer finished.',
  'payload': payload,
};

/// One Android state a completion meets, and what the app asked of it.
class _AndroidHost {
  _AndroidHost({
    this.active = const <Map<String, Object?>>[],
    this.pending = const <Map<String, Object?>>[],
    this.notificationsEnabled = true,
    this.activeUnreadable = false,
    this.pendingUnreadable = false,
    this.cancelFails = false,
  });

  final List<Map<String, Object?>> active;
  final List<Map<String, Object?>> pending;
  final bool notificationsEnabled;
  final bool activeUnreadable;
  final bool pendingUnreadable;
  final bool cancelFails;

  /// Every plugin call, in the order the app made it.
  final List<MethodCall> calls = <MethodCall>[];

  /// Notification IDs the app asked Android to withdraw.
  final List<int> cancelled = <int>[];

  /// Completion chime requests the app sent to the runner.
  final List<MethodCall> chimes = <MethodCall>[];

  /// Binds the pinned Android implementation and answers its channel.
  ///
  /// No plugin registrant runs under `flutter test`, so the real Android Dart
  /// implementation is registered the way the app does on device and the host
  /// side of both channels is answered here.
  void install() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationsChannel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'areNotificationsEnabled') return notificationsEnabled;
      if (call.method == 'getActiveNotifications') {
        if (activeUnreadable) {
          throw PlatformException(code: 'active_unreadable');
        }
        return active;
      }
      if (call.method == 'pendingNotificationRequests') {
        if (pendingUnreadable) {
          throw PlatformException(code: 'pending_unreadable');
        }
        return pending;
      }
      if (call.method == 'cancel') {
        if (cancelFails) {
          throw PlatformException(code: 'cancel_failed');
        }
        cancelled.add((call.arguments as Map<Object?, Object?>)['id']! as int);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_feedbackChannel, (call) async {
      if (call.method == 'playCompletion') {
        chimes.add(call);
        return true;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_notificationsChannel, null);
      messenger.setMockMethodCallHandler(_feedbackChannel, null);
    });
  }
}

/// Installs [host] and returns the subject wired to it.
TimerNotifications _notifications(_AndroidHost host) {
  host.install();
  return TimerNotifications();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The app only talks to the plugin on Android, so every case runs as one.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('completeInForeground', () {
    test('a posted alert is kept and never chimes again', () async {
      const postedId = 1042;
      final host = _AndroidHost(
        active: [_activeNotification(postedId)],
        pending: [
          _pendingRequest(
            postedId,
            _payload(TimerNotifications.focusId, _deadline),
          ),
        ],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        scheduledId: postedId,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.alreadyPosted);
      expect(result.withdrawn, 0);
      expect(result.pendingWithdrawFailed, isFalse);
      expect(result.stateUnknown, isFalse);
      expect(result.needsAttention, isFalse);
      expect(result.message, 'The completion alert is already posted.');
      expect(
        host.cancelled,
        isEmpty,
        reason: 'The posted entry shares its ID with the pending request and '
            'must not be withdrawn while the user is reading it.',
      );
      expect(
        host.chimes,
        isEmpty,
        reason: 'A posted alert already carried the completion feedback.',
      );
    });

    test('a posted entry without an ID is ignored rather than treated as '
        'posted', () async {
      const pendingId = 1047;
      // The parser accepts an entry with no ID but no payload either, so it can
      // only be skipped: it must not fail the read or suppress the chime.
      final host = _AndroidHost(
        active: [_activeNotificationWithoutId()],
        pending: [
          _pendingRequest(
            pendingId,
            _payload(TimerNotifications.focusId, _deadline),
          ),
        ],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.stateUnknown, isFalse);
      expect(result.withdrawn, 1);
      expect(host.cancelled, [pendingId]);
      expect(host.chimes, hasLength(1));
    });

    test('a pending alert matching the scheduled ID is withdrawn, then one '
        'chime plays', () async {
      const scheduledId = 1047;
      final host = _AndroidHost(
        // The payload is missing, so only the ID links this alarm to the timer.
        pending: [_pendingRequest(scheduledId, null)],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        scheduledId: scheduledId,
        sound: true,
        vibration: false,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.withdrawn, 1);
      expect(result.pendingWithdrawFailed, isFalse);
      expect(result.stateUnknown, isFalse);
      expect(result.needsAttention, isFalse);
      expect(result.message, isNull);
      expect(host.cancelled, [scheduledId]);
      expect(host.chimes, hasLength(1));
      final request =
          host.chimes.single.arguments as Map<Object?, Object?>;
      expect(request['sound'], isTrue);
      expect(request['vibration'], isFalse);
      expect(request['channelId'], 'timer_completion_v2');
    });

    test('a pending alert is withdrawn by kind and deadline when no scheduled '
        'ID was kept', () async {
      const pendingId = 1044;
      final host = _AndroidHost(
        pending: [
          _pendingRequest(
            pendingId,
            _payload(TimerNotifications.focusId, _deadline),
          ),
        ],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.withdrawn, 1);
      expect(host.cancelled, [pendingId]);
      expect(host.chimes, hasLength(1));
    });

    test('an alert for another ID, deadline or kind is left alone', () async {
      const scheduledId = 1555;
      final otherDeadline = _deadline.add(const Duration(minutes: 5));
      final host = _AndroidHost(
        active: [_activeNotification(1300)],
        pending: [
          _pendingRequest(
            1301,
            _payload(TimerNotifications.focusId, otherDeadline),
          ),
          _pendingRequest(
            2042,
            _payload(TimerNotifications.countdownId, _deadline),
          ),
          _pendingRequest(1043, null),
        ],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        scheduledId: scheduledId,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.withdrawn, 0);
      expect(result.stateUnknown, isFalse);
      expect(host.cancelled, isEmpty);
      expect(host.chimes, hasLength(1));
    });

    test('a pending alert that cannot be withdrawn suppresses the chime', () async {
      final host = _AndroidHost(
        pending: [
          _pendingRequest(
            1047,
            _payload(TimerNotifications.focusId, _deadline),
          ),
        ],
        cancelFails: true,
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.pendingWithdrawFailed);
      expect(result.pendingWithdrawFailed, isTrue);
      expect(result.withdrawn, 0);
      expect(result.needsAttention, isTrue);
      expect(result.message, contains('chime was suppressed'));
      expect(
        host.chimes,
        isEmpty,
        reason: 'The late alarm may still fire, so a second alert must not be '
            'played in the foreground.',
      );
    });

    test('an unreadable posted probe plays once and reports the unknown '
        'state', () async {
      final host = _AndroidHost(
        activeUnreadable: true,
        pending: [
          _pendingRequest(
            1047,
            _payload(TimerNotifications.focusId, _deadline),
          ),
        ],
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.stateUnknown, isTrue);
      expect(result.needsAttention, isTrue);
      expect(result.withdrawn, 0);
      expect(
        host.cancelled,
        isEmpty,
        reason: 'Without the posted set an alarm may already have posted, so '
            'it must not be withdrawn on a guess.',
      );
      expect(host.chimes, hasLength(1));
      expect(result.message, contains('could not list posted notifications'));
    });

    test('a posted alert still suppresses the chime when pending alerts are '
        'unreadable', () async {
      final host = _AndroidHost(
        active: [_activeNotification(1042)],
        pendingUnreadable: true,
      );

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        scheduledId: 1042,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.alreadyPosted);
      expect(result.stateUnknown, isTrue);
      expect(result.needsAttention, isTrue);
      expect(host.cancelled, isEmpty);
      expect(host.chimes, isEmpty);
      expect(result.message, contains('could not report the pending state'));
    });

    test('a blocked notification permission still chimes once in the '
        'foreground', () async {
      final host = _AndroidHost(notificationsEnabled: false);

      final result = await _notifications(host).completeInForeground(
        id: TimerNotifications.focusId,
        deadline: _deadline,
        sound: true,
        vibration: true,
      );

      expect(result.outcome, TimerCompletionOutcome.played);
      expect(result.stateUnknown, isFalse);
      expect(result.message, isNull);
      expect(host.chimes, hasLength(1));
      expect(host.cancelled, isEmpty);
      expect(
        host.calls.map((call) => call.method),
        isNot(contains('areNotificationsEnabled')),
        reason: 'A denied permission governs native posting only; it must not '
            'suppress or gate the in-app completion chime.',
      );
    });
  });
}
