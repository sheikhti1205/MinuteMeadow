import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PackAudio {
  static const _channel = MethodChannel('app.companionfocus/pack_sound');

  static bool get _available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> play(Uint8List wav, double volume) async {
    if (!_available || volume <= 0) return;
    await _call('playWav', {'bytes': wav, 'volume': volume});
  }

  static Future<void> stop() async {
    if (_available) await _call('stop');
  }

  static Future<void> _call(String method, [Map<String, Object>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // A sound failure does not interrupt the scene interaction.
    } on MissingPluginException {
      // Tests and alternate runners may not include the platform sound bridge.
    }
  }
}
