import 'package:flutter/services.dart';

/// Foreground completion feedback hosted by the Android runner.
///
/// The runner answers [playCompletion] on [channelName]. Sound and vibration
/// are separate requests so the timer can honour the user's sound and haptics
/// settings without reusing touch haptics. The host also owns the system
/// notification-settings intent, because the notification plugin has no API for
/// opening an app's notification page.
///
/// This class carries no asset of its own. The runner owns the app's
/// `timer_completion_chime` resource and plays it when the completion channel
/// has not been created yet; that is the same sound the audible notification
/// channels use. When the channel exists, the runner reads its current sound
/// instead, so the user's channel-level sound and vibration choices win.
class TimerFeedback {
  TimerFeedback._();

  static const channelName = 'app.companionfocus/timer_feedback';

  static const _channel = MethodChannel(channelName);

  /// Asks the runner to play the completion chime and/or vibrate.
  ///
  /// [sound] and [vibration] are independent. [channelId] lets the host read
  /// the user's channel sound and vibration settings before playing. A host
  /// that has not been attached, or that rejects the request, returns false.
  static Future<bool> playCompletion({
    required bool sound,
    required bool vibration,
    String? channelId,
  }) async {
    try {
      final accepted = await _channel.invokeMethod<bool>('playCompletion', {
        'sound': sound,
        'vibration': vibration,
        if (channelId != null) 'channelId': channelId,
      });
      // A host that accepts the call returns true. A null reply means the
      // request reached the channel and the host chose not to report an error.
      return accepted ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens this app's notification settings page.
  ///
  /// Returns false when the runner is missing or the settings activity could
  /// not be resolved. The caller keeps the explanatory text visible in that
  /// case rather than pretending the settings page opened.
  static Future<bool> openNotificationSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>('openNotificationSettings');
      return opened ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Stops a completion chime that is still playing.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No host is attached.
    } on PlatformException {
      // Stopping feedback is best effort.
    }
  }
}
