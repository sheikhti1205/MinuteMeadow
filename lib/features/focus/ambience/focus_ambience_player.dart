import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'focus_ambience_engine.dart';
import 'focus_ambience_preferences.dart';

/// Android bridge for the quiet Focus ambience loop.
///
/// The channel is separate from `app.companionfocus/pack_sound` and
/// `app.companionfocus/timer_feedback`, so an ambience loop can never replace a
/// pack interaction or a timer alert. The native host owns the AudioTrack and
/// never requests audio focus. Native also reports a headphone disconnect back
/// over the same channel; one player instance owns those callbacks for the life
/// of the Focus surface.
class FocusAmbiencePlayer implements FocusAmbienceEngine {
  FocusAmbiencePlayer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const channelName = 'app.companionfocus/focus_ambience';
  static const startMethod = 'start';
  static const setVolumeMethod = 'setVolume';
  static const stopMethod = 'stop';
  static const headphonesConnectedEvent = 'headphonesConnected';
  static const headphonesDisconnectedEvent = 'headphonesDisconnected';

  final MethodChannel _channel;

  void Function()? onHeadphonesConnected;
  void Function()? onHeadphonesDisconnected;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> start(FocusAmbienceTrack track, double volume) async {
    if (!isSupported || !_isAudible(track, volume)) return;
    await _invoke(startMethod, <String, Object>{
      'track': track.id,
      'volume': volume,
    });
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!isSupported || volume <= 0 || volume > 1) return;
    await _invoke(setVolumeMethod, <String, Object>{'volume': volume});
  }

  @override
  Future<void> stop() async {
    if (!isSupported) return;
    await _invoke(stopMethod);
  }

  /// Releases the Dart-side handler. The controller must be disposed first.
  void detach() {
    onHeadphonesConnected = null;
    onHeadphonesDisconnected = null;
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == headphonesConnectedEvent) {
      onHeadphonesConnected?.call();
    } else if (call.method == headphonesDisconnectedEvent) {
      onHeadphonesDisconnected?.call();
    }
    return null;
  }

  Future<void> _invoke(String method, [Map<String, Object>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // A failed request leaves the previous ambience state intact.
    } on MissingPluginException {
      // Alternate runners and tests may not include the platform bridge.
    }
  }

  static bool _isAudible(FocusAmbienceTrack track, double volume) =>
      track != FocusAmbienceTrack.off && volume > 0 && volume <= 1;
}
