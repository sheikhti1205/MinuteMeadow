import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'timer_feedback.dart';

/// What happened when the app asked Android to schedule or show an alert.
///
/// The caller receives an explicit result instead of a swallowed platform
/// exception, so a blocked permission, an inexact fallback, a failed cleanup or
/// a rejected schedule can be surfaced in the UI.
enum TimerScheduleOutcome {
  /// Scheduled with an exact, idle-safe alarm.
  scheduledExact,

  /// Scheduled with an inexact, idle-safe alarm. The alert may arrive late.
  scheduledInexact,

  /// An immediate test notification was posted.
  testPosted,

  /// A pending alert for the kind was removed (or nothing was pending).
  cleared,

  /// The requested deadline had already passed, so nothing was scheduled.
  expired,

  /// Notifications are blocked in Android settings.
  notificationsDisabled,

  /// The plugin or the runner's platform bridge is not available.
  unavailable,

  /// Android rejected the schedule or a pending alert could not be withdrawn.
  failed,
}

class TimerScheduleResult {
  const TimerScheduleResult(
    this.outcome, {
    this.scheduledAt,
    this.message,
    this.notificationId,
    this.pendingWithdrawFailed = false,
  });

  final TimerScheduleOutcome outcome;
  final DateTime? scheduledAt;
  final String? message;

  /// The rolled notification ID Android accepted, when one was scheduled.
  ///
  /// The caller should hold this for the life of the timer and pass it back to
  /// [TimerNotifications.completeInForeground]: Android returns no payload for
  /// a posted notification, so this ID is what proves an alert already posted.
  /// Pending alerts can also be matched by their kind and deadline.
  final int? notificationId;

  /// True when a pending alert for the same kind could not be removed.
  ///
  /// The caller should surface this: an old alarm may still fire, and no new
  /// alarm was scheduled in that case so a duplicate is not created silently.
  final bool pendingWithdrawFailed;

  bool get isScheduled =>
      outcome == TimerScheduleOutcome.scheduledExact ||
      outcome == TimerScheduleOutcome.scheduledInexact;

  bool get usedInexact => outcome == TimerScheduleOutcome.scheduledInexact;

  /// True when the user should see a warning or a recovery action.
  bool get needsAttention =>
      outcome == TimerScheduleOutcome.scheduledInexact ||
      outcome == TimerScheduleOutcome.notificationsDisabled ||
      outcome == TimerScheduleOutcome.unavailable ||
      outcome == TimerScheduleOutcome.failed ||
      pendingWithdrawFailed;
}

/// What a foreground completion did about the native alert.
enum TimerCompletionOutcome {
  /// The runner accepted the foreground chime request.
  ///
  /// Android can still mute it through Do Not Disturb, the ringer mode or the
  /// notification volume; the request itself succeeded.
  played,

  /// A matching native alert is already posted, so no chime was played again.
  alreadyPosted,

  /// Sound and vibration were both disabled, so nothing was played.
  muted,

  /// A late pending alert could not be withdrawn. The chime is suppressed so
  /// the user does not hear the same completion twice.
  pendingWithdrawFailed,

  /// The runner or the plugin is not available.
  unavailable,

  /// The platform is not Android.
  unsupported,

  /// The supplied timer ID is not a known timer kind.
  failed,
}

class TimerCompletionResult {
  const TimerCompletionResult(
    this.outcome, {
    this.withdrawn = 0,
    this.pendingWithdrawFailed = false,
    this.stateUnknown = false,
    this.message,
  });

  final TimerCompletionOutcome outcome;

  /// How many late pending alerts were cancelled.
  final int withdrawn;

  /// True when at least one pending alert could not be cancelled.
  final bool pendingWithdrawFailed;

  /// True when Android could not report its pending or posted state.
  ///
  /// The decision is then best effort and a duplicate alert is possible.
  final bool stateUnknown;

  final String? message;

  bool get needsAttention =>
      pendingWithdrawFailed ||
      stateUnknown ||
      outcome == TimerCompletionOutcome.pendingWithdrawFailed ||
      outcome == TimerCompletionOutcome.unavailable ||
      outcome == TimerCompletionOutcome.failed;
}

/// Schedules Android timer alerts and serves the shared alert feedback.
///
/// Android notification IDs are rolling per timer kind rather than fixed. A
/// posted completion and a newly scheduled alert therefore never share an ID,
/// so cancelling a pending break cannot remove the Focus completion the user is
/// still reading. The legacy fixed IDs (1 and 2) are only removed when they are
/// pending and not currently posted.
///
/// Audible alerts use the versioned `timer_completion_v2*` channels and an
/// app-owned raw chime. The original `timer_completion` channel is left intact
/// on the device: Android channel settings are immutable, so it cannot be
/// given the new sound, and deleting it would silently discard the user's
/// choices. Silent alerts keep the silent channels.
///
/// A schedule request performs these steps:
/// 1. initialise the plugin;
/// 2. cancel pending IDs for the same timer kind unless that ID is currently
///    posted;
/// 3. allocate an unused ID in the kind's range;
/// 4. schedule an exact idle-safe alarm when exact alarms are allowed, or an
///    inexact idle-safe alarm otherwise.
///
/// No alert is scheduled for an expired deadline. A completed alert is never
/// replayed from a stored checkpoint; that decision belongs to the caller.
class TimerNotifications {
  /// Kind identifiers passed by the app. Each kind owns a 1000-ID range.
  static const focusId = 1000;
  static const countdownId = 2000;

  /// Immediate test notification. It is outside both timer ranges.
  static const testId = 3000;

  /// The app-owned completion chime in `android/app/src/main/res/raw`.
  ///
  /// The file is an original procedural sine-bell motif generated for this
  /// project, not an upstream sound. The native host plays the same resource
  /// when the notification channel does not exist yet.
  static const timerChimeResource = 'timer_completion_chime';

  static const _idSpan = 1000;
  static const _legacyFocusId = 1;
  static const _legacyCountdownId = 2;
  static const _payloadPrefix = 'timer-feedback:v1';
  static const _deadlineTolerance = Duration(seconds: 1);

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _initializing;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> _initialize() {
    final pending = _initializing;
    if (pending != null) return pending;
    final next = _initializeOnce();
    _initializing = next;
    return next;
  }

  Future<bool> _initializeOnce() async {
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_timer_notification'),
        ),
      );
      if (initialized == false) {
        _initializing = null;
        return false;
      }
      return true;
    } on MissingPluginException {
      _initializing = null;
      return false;
    } on PlatformException {
      _initializing = null;
      return false;
    }
  }

  /// Requests the Android 13+ notification permission.
  ///
  /// Returns false when the plugin is unavailable, the request is rejected, or
  /// another permission request is already in progress.
  Future<bool> requestPermission() async {
    if (!available) return false;
    if (!await _initialize()) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Reports whether Android will currently post this app's notifications.
  Future<bool> hasPermission() async {
    if (!available) return false;
    if (!await _initialize()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Reports whether exact alarms may be used.
  ///
  /// On Android before 12 this is true without a user grant. On Android 12+ it
  /// reflects the `SCHEDULE_EXACT_ALARM` grant, which the user controls.
  Future<bool> canScheduleExact() async {
    if (!available) return false;
    if (!await _initialize()) return false;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system page where the user can grant exact alarms.
  ///
  /// This is the only supported exact-alarm opt-in. The app never declares the
  /// install-time `USE_EXACT_ALARM` permission and never requests notification
  /// policy access, so no alert bypasses Do Not Disturb.
  Future<bool> requestExactAlarmPermission() async {
    if (!available) return false;
    if (!await _initialize()) return false;
    try {
      return await _android?.requestExactAlarmsPermission() ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens this app's notification settings page.
  Future<bool> openNotificationSettings() {
    if (!available) return Future<bool>.value(false);
    return TimerFeedback.openNotificationSettings();
  }

  /// The channel used for one sound/vibration combination.
  ///
  /// Audible alerts use new versioned IDs because an existing Android channel
  /// cannot be given a new sound. The silent IDs keep the existing quiet
  /// channel and quiet vibration-only channel so no user setting is wiped.
  static String channelIdFor({required bool sound, required bool vibration}) {
    if (!sound) {
      return vibration
          ? 'timer_completion_silent_vibrate'
          : 'timer_completion_silent';
    }
    return vibration ? 'timer_completion_v2_vibrate' : 'timer_completion_v2';
  }

  static String _channelName({required bool sound, required bool vibration}) {
    if (sound && vibration) return 'Timer completion chime and vibration';
    if (sound) return 'Timer completion chime';
    if (vibration) return 'Silent timer completion with vibration';
    return 'Silent timer completion';
  }

  AndroidNotificationDetails _details({
    required bool sound,
    required bool vibration,
  }) => AndroidNotificationDetails(
    channelIdFor(sound: sound, vibration: vibration),
    _channelName(sound: sound, vibration: vibration),
    channelDescription: 'Focus, break and countdown alerts',
    importance: Importance.high,
    priority: Priority.high,
    playSound: sound,
    sound: sound
        ? const RawResourceAndroidNotificationSound(timerChimeResource)
        : null,
    enableVibration: vibration,
    enableLights: false,
    channelShowBadge: false,
    category: AndroidNotificationCategory.reminder,
    audioAttributesUsage: AudioAttributesUsage.notification,
  );

  /// Schedules the next alert for [id]'s timer kind.
  ///
  /// [id] is [focusId] or [countdownId]. Passing `enabled: false` or a null
  /// [deadline] clears future pending alerts for that kind but leaves an alert
  /// that already posted untouched. A deadline that has already passed is
  /// reported as [TimerScheduleOutcome.expired] and is not scheduled.
  ///
  /// [vibration] is independent of [sound]. [forceInexact] is for tests and for
  /// a caller that deliberately declines exact timing.
  ///
  /// When a pending alert for the kind cannot be withdrawn, no new alarm is
  /// scheduled: the old one may still fire, and returning
  /// [TimerScheduleResult.pendingWithdrawFailed] is better than silently
  /// producing two alerts.
  Future<TimerScheduleResult> schedule({
    required int id,
    required DateTime? deadline,
    required String title,
    required bool enabled,
    required bool sound,
    bool vibration = false,
    bool forceInexact = false,
  }) async {
    if (!available) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts need the Android app.',
      );
    }
    final kind = _kindForId(id);
    if (kind == null) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.failed,
        message: 'Unknown timer kind.',
      );
    }
    if (!await _initialize()) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts could not start.',
      );
    }

    final now = DateTime.now().toUtc();
    if (!enabled || deadline == null) {
      final cancel = await _cancelPending(kind, now);
      return TimerScheduleResult(
        TimerScheduleOutcome.cleared,
        pendingWithdrawFailed: !cancel.ok,
        message: cancel.ok
            ? null
            : 'A pending timer alert could not be withdrawn.',
      );
    }

    final target = deadline.toUtc();
    if (!target.isAfter(now)) {
      // Do not cancel here: a due alert may already have posted under this
      // kind, and removing it is the defect this class exists to avoid.
      return const TimerScheduleResult(
        TimerScheduleOutcome.expired,
        message: 'The timer deadline has already passed.',
      );
    }

    if (!await hasPermission()) {
      // Still withdraw a stale alarm. Leaving it pending would let it fire
      // after the user re-enables notifications, which looks like a duplicate.
      final cancel = await _cancelPending(kind, now);
      return TimerScheduleResult(
        TimerScheduleOutcome.notificationsDisabled,
        pendingWithdrawFailed: !cancel.ok,
        message: cancel.ok
            ? 'Notifications are blocked in Android settings.'
            : 'Notifications are blocked and a pending alert could not be '
                  'withdrawn; it may still fire.',
      );
    }

    final cancel = await _cancelPending(kind, now);
    if (!cancel.ok) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.failed,
        pendingWithdrawFailed: true,
        message: 'A previous timer alert could not be withdrawn, so a new one '
            'was not scheduled.',
      );
    }
    final notificationId = await _allocateId(kind);
    final exact = !forceInexact && await canScheduleExact();
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _zonedSchedule(
        id: notificationId,
        target: target,
        title: title,
        sound: sound,
        vibration: vibration,
        mode: mode,
        kind: kind,
      );
      return TimerScheduleResult(
        exact
            ? TimerScheduleOutcome.scheduledExact
            : TimerScheduleOutcome.scheduledInexact,
        scheduledAt: target,
        notificationId: notificationId,
        message: exact
            ? null
            : 'Exact alarms are off, so this alert may arrive late.',
      );
    } on PlatformException catch (error) {
      // Android can revoke exact-alarm access between the probe and the
      // schedule call. Fall back once to an inexact alarm rather than losing
      // the alert, and report the fallback to the caller.
      if (exact && error.code == 'exact_alarms_not_permitted') {
        try {
          await _zonedSchedule(
            id: notificationId,
            target: target,
            title: title,
            sound: sound,
            vibration: vibration,
            mode: AndroidScheduleMode.inexactAllowWhileIdle,
            kind: kind,
          );
          return TimerScheduleResult(
            TimerScheduleOutcome.scheduledInexact,
            scheduledAt: target,
            notificationId: notificationId,
            message: 'Exact alarms are off, so this alert may arrive late.',
          );
        } on PlatformException catch (fallback) {
          return TimerScheduleResult(
            TimerScheduleOutcome.failed,
            message:
                fallback.message ?? 'The timer alert could not be scheduled.',
          );
        } on MissingPluginException {
          return const TimerScheduleResult(
            TimerScheduleOutcome.unavailable,
            message: 'Timer alerts need the Android app.',
          );
        }
      }
      return TimerScheduleResult(
        TimerScheduleOutcome.failed,
        message: error.message ?? 'The timer alert could not be scheduled.',
      );
    } on MissingPluginException {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts need the Android app.',
      );
    } on ArgumentError {
      return const TimerScheduleResult(
        TimerScheduleOutcome.expired,
        message: 'The timer deadline has already passed.',
      );
    }
  }

  Future<void> _zonedSchedule({
    required int id,
    required DateTime target,
    required String title,
    required bool sound,
    required bool vibration,
    required AndroidScheduleMode mode,
    required _TimerKind kind,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: 'Your timer finished.',
    scheduledDate: tz.TZDateTime.from(target, tz.UTC),
    notificationDetails: NotificationDetails(
      android: _details(sound: sound, vibration: vibration),
    ),
    androidScheduleMode: mode,
    payload: _payload(kind, target),
  );

  /// Cancels pending alerts for [id]'s timer kind.
  ///
  /// A notification that already posted is left in place. This is the same
  /// policy as passing a null deadline to [schedule], exposed for startup
  /// recovery where the app only wants to remove a stale pending alarm.
  Future<TimerScheduleResult> clear({required int id}) => schedule(
    id: id,
    deadline: null,
    title: '',
    enabled: true,
    sound: false,
  );

  /// Posts an immediate notification on the same channel a timer would use.
  ///
  /// This is the Settings preview path. It gives a visible result instead of a
  /// silent no-op when notifications are blocked.
  Future<TimerScheduleResult> showTestNotification({
    required bool sound,
    required bool vibration,
  }) async {
    if (!available) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts need the Android app.',
      );
    }
    if (!await _initialize()) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts could not start.',
      );
    }
    if (!await hasPermission()) {
      return const TimerScheduleResult(
        TimerScheduleOutcome.notificationsDisabled,
        message: 'Notifications are blocked in Android settings.',
      );
    }
    try {
      await _plugin.show(
        id: testId,
        title: 'Timer alert test',
        body: 'A finished timer will alert you like this.',
        notificationDetails: NotificationDetails(
          android: _details(sound: sound, vibration: vibration),
        ),
        payload: '$_payloadPrefix:test',
      );
      return const TimerScheduleResult(
        TimerScheduleOutcome.testPosted,
        notificationId: testId,
        message: 'Test alert sent.',
      );
    } on PlatformException catch (error) {
      return TimerScheduleResult(
        TimerScheduleOutcome.failed,
        message: error.message ?? 'The test alert could not be shown.',
      );
    } on MissingPluginException {
      return const TimerScheduleResult(
        TimerScheduleOutcome.unavailable,
        message: 'Timer alerts need the Android app.',
      );
    }
  }

  /// Decides the foreground completion for one timer kind and deadline.
  ///
  /// The operation covers the completion that just happened, not a restored
  /// checkpoint:
  /// 1. a pending alarm for the same kind and deadline is withdrawn when it is
  ///    not already posted, so it cannot fire after the user saw the timer
  ///    finish;
  /// 2. a notification that already posted under [scheduledId] is never
  ///    cancelled, and [TimerCompletionOutcome.alreadyPosted] suppresses the
  ///    chime so the user is not alerted twice;
  /// 3. otherwise the foreground chime plays, even when Android blocks
  ///    notifications or the app's channel does not exist yet.
  ///
  /// [scheduledId] is the optional [TimerScheduleResult.notificationId].
  /// Android returns no payload for a posted notification, so only a retained
  /// ID can recognise a completion alert that already posted. A pending alarm
  /// is matched by that ID when it was kept, and by kind and deadline from its
  /// payload otherwise.
  ///
  /// This is best effort. Android exposes pending alarms and posted
  /// notifications through two separate calls with no transaction between
  /// them, so an alarm that fires between the two reads can be cancelled just
  /// after it posts, or can post just after the reads and be heard as a
  /// duplicate. On versions where `getActiveNotifications()` returns nothing,
  /// the posted check cannot succeed and only the pending cache is used.
  Future<TimerCompletionResult> completeInForeground({
    required int id,
    required DateTime? deadline,
    int? scheduledId,
    required bool sound,
    required bool vibration,
  }) async {
    if (!available) {
      return const TimerCompletionResult(TimerCompletionOutcome.unsupported);
    }
    final kind = _kindForId(id);
    if (kind == null) {
      return const TimerCompletionResult(
        TimerCompletionOutcome.failed,
        message: 'Unknown timer kind.',
      );
    }

    final active = await _activeNotifications();
    final pending = await _pendingRequests();

    var withdrawn = 0;
    var withdrawFailed = false;
    // A pending alert is only cancelled when the posted state is known, so a
    // notification that already posted is never removed. An unreadable state
    // is reported instead of guessed.
    final stateUnknown = active == null || pending == null;
    if (active != null && pending != null) {
      for (final request in pending) {
        if (!kind.contains(request.id)) continue;
        if (active.containsKey(request.id)) continue;
        if (!_matches(kind, deadline, scheduledId, request.id, request.payload)) {
          continue;
        }
        try {
          await _android?.cancel(id: request.id);
          withdrawn++;
        } on PlatformException {
          withdrawFailed = true;
          break;
        } on MissingPluginException {
          withdrawFailed = true;
          break;
        }
      }
    }

    final posted =
        active != null &&
        active.entries.any(
          (entry) =>
              _matches(kind, deadline, scheduledId, entry.key, entry.value),
        );
    if (posted) {
      return TimerCompletionResult(
        TimerCompletionOutcome.alreadyPosted,
        withdrawn: withdrawn,
        pendingWithdrawFailed: withdrawFailed,
        stateUnknown: stateUnknown,
        message: withdrawFailed
            ? 'The completion alert is already posted, but a late pending '
                  'alert could not be withdrawn.'
            : stateUnknown
            ? 'The completion alert is already posted; Android could not '
                  'report the pending state.'
            : 'The completion alert is already posted.',
      );
    }
    if (withdrawFailed) {
      return TimerCompletionResult(
        TimerCompletionOutcome.pendingWithdrawFailed,
        withdrawn: withdrawn,
        pendingWithdrawFailed: true,
        stateUnknown: stateUnknown,
        message: 'A late timer alert could not be withdrawn, so the foreground '
            'chime was suppressed to avoid a duplicate.',
      );
    }
    if (!sound && !vibration) {
      return TimerCompletionResult(
        TimerCompletionOutcome.muted,
        withdrawn: withdrawn,
        stateUnknown: stateUnknown,
      );
    }

    final played = await playCompletion(sound: sound, vibration: vibration);
    return TimerCompletionResult(
      played
          ? TimerCompletionOutcome.played
          : TimerCompletionOutcome.unavailable,
      withdrawn: withdrawn,
      stateUnknown: stateUnknown,
      message: played ? _completionNote(active, pending) : 'No feedback host is '
          'attached, so the completion chime could not play.',
    );
  }

  String? _completionNote(
    Map<int, String?>? active,
    List<PendingNotificationRequest>? pending,
  ) {
    if (active == null) {
      return 'Android could not list posted notifications, so a duplicate '
          'alert is possible.';
    }
    if (pending == null) {
      return 'Android could not list pending alarms, so a duplicate alert is '
          'possible.';
    }
    return null;
  }

  /// Plays foreground completion feedback through the Android host.
  ///
  /// The host reads the same channel the scheduled alert would use, so a user
  /// who silenced or disabled vibration for that channel is respected. When
  /// the channel does not exist yet, the host plays the app-owned chime
  /// instead, so a blocked notification permission cannot suppress an in-app
  /// completion. Sound and vibration remain independent.
  Future<bool> playCompletion({
    required bool sound,
    required bool vibration,
  }) {
    if (!available) return Future<bool>.value(false);
    return TimerFeedback.playCompletion(
      sound: sound,
      vibration: vibration,
      channelId: channelIdFor(sound: sound, vibration: vibration),
    );
  }

  Future<({bool ok, int withdrawn})> _cancelPending(
    _TimerKind kind,
    DateTime now,
  ) async {
    final plugin = _android;
    if (plugin == null) return (ok: true, withdrawn: 0);
    final pending = await _pendingRequests();
    // Without the pending list the withdrawal cannot be verified. Report it
    // instead of scheduling a second alarm beside an unknown one.
    if (pending == null) return (ok: false, withdrawn: 0);
    // A posted alert and a pending alarm never share an ID because IDs roll.
    // Still check the active set before cancelling: the receiver can post and
    // then remove its cache entry in one pass, and that notification must stay.
    final active = await _activeNotifications();
    var withdrawn = 0;
    for (final request in pending) {
      if (!kind.contains(request.id)) continue;
      if (active != null && active.containsKey(request.id)) continue;
      final deadline = _payloadInfo(request.payload)?.deadline;
      if (active == null) {
        // Without a reliable active set, cancel only alarms that have not
        // reached their deadline. A due alarm may be about to post and must not
        // be removed.
        if (deadline == null || !deadline.isAfter(now)) continue;
      }
      try {
        await plugin.cancel(id: request.id);
        withdrawn++;
      } on MissingPluginException {
        return (ok: false, withdrawn: withdrawn);
      } on PlatformException {
        return (ok: false, withdrawn: withdrawn);
      }
    }
    return (ok: true, withdrawn: withdrawn);
  }

  Future<int> _allocateId(_TimerKind kind) async {
    final active = await _activeNotifications() ?? const <int, String?>{};
    final pending =
        await _pendingRequests() ?? const <PendingNotificationRequest>[];
    final used = <int>{
      for (final request in pending) request.id,
      ...active.keys,
    };
    final start = DateTime.now().microsecondsSinceEpoch % _idSpan;
    for (var offset = 0; offset < _idSpan; offset++) {
      final candidate = kind.base + ((start + offset) % _idSpan);
      if (!used.contains(candidate)) return candidate;
    }
    return kind.base + start;
  }

  Future<List<PendingNotificationRequest>?> _pendingRequests() async {
    final plugin = _android;
    if (plugin == null) return null;
    try {
      return await plugin.pendingNotificationRequests();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<int, String?>?> _activeNotifications() async {
    final plugin = _android;
    if (plugin == null) return null;
    try {
      final active = await plugin.getActiveNotifications();
      final posted = <int, String?>{};
      for (final notification in active) {
        final id = notification.id;
        // The parser accepts an entry without a usable ID; it can neither be
        // matched nor cancelled, so it must not fail the whole read.
        if (id == null) continue;
        // Android reports no payload for an active notification; a posted alert
        // is recognised by the ID the caller retained.
        posted[id] = notification.payload;
      }
      return posted;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  _TimerKind? _kindForId(int id) {
    if (id == focusId || id == _legacyFocusId) return _focusKind;
    if (id == countdownId || id == _legacyCountdownId) return _countdownKind;
    return null;
  }

  String _payload(_TimerKind kind, DateTime deadline) =>
      '$_payloadPrefix:${kind.base}:${deadline.millisecondsSinceEpoch}';

  ({int kindBase, DateTime deadline})? _payloadInfo(String? payload) {
    if (payload == null || !payload.startsWith('$_payloadPrefix:')) return null;
    final parts = payload.split(':');
    if (parts.length != 4) return null;
    final kindBase = int.tryParse(parts[2]);
    final milliseconds = int.tryParse(parts[3]);
    if (kindBase == null || milliseconds == null) return null;
    return (
      kindBase: kindBase,
      deadline: DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
    );
  }

  bool _matches(
    _TimerKind kind,
    DateTime? deadline,
    int? scheduledId,
    int notificationId,
    String? payload,
  ) {
    if (scheduledId != null && notificationId == scheduledId) return true;
    if (deadline == null) return false;
    final info = _payloadInfo(payload);
    if (info == null || info.kindBase != kind.base) return false;
    return info.deadline.difference(deadline.toUtc()).abs() <=
        _deadlineTolerance;
  }
}

class _TimerKind {
  const _TimerKind({required this.base, required this.legacyIds});

  final int base;
  final Set<int> legacyIds;

  bool contains(int id) =>
      (id >= base && id < base + TimerNotifications._idSpan) ||
      legacyIds.contains(id);
}

const _focusKind = _TimerKind(
  base: TimerNotifications.focusId,
  legacyIds: <int>{1},
);

const _countdownKind = _TimerKind(
  base: TimerNotifications.countdownId,
  legacyIds: <int>{2},
);
