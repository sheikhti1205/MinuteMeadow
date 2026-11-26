import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BootSample {
  const BootSample({required this.bootCount, required this.elapsed});

  final int bootCount;
  final Duration elapsed;
}

class BootClock {
  static const _channel = MethodChannel('app.companionfocus/boot_clock');

  static Future<BootSample?> sample() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final result = await _channel.invokeMapMethod<String, int>('sample');
      final bootCount = result?['bootCount'];
      final elapsedMs = result?['elapsedMs'];
      if (bootCount == null || bootCount < 0 || elapsedMs == null || elapsedMs < 0) {
        return null;
      }
      return BootSample(
        bootCount: bootCount,
        elapsed: Duration(milliseconds: elapsedMs),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
