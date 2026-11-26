import 'dart:typed_data';

import 'package:companion_focus/features/companion/pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('accepts a bounded PCM WAV assigned to a scene event', () {
    final files = {...fixtureFiles(), 'sounds/tap.wav': _wav()};
    final json = manifestFor(files)
      ..['sounds'] = [
        {'event': 'pet', 'asset': 'sounds/tap.wav', 'volume': 0.5},
      ];
    final manifest = PackManifest.fromJson(json);
    final verified = manifest.verifyAssets(files);
    expect(manifest.sounds.single.volume, 0.5);
    expect(verified['sounds/tap.wav']?.bytes.length, 46);
  });

  test('rejects a sound without an assigned event', () {
    final files = {...fixtureFiles(), 'sounds/tap.wav': _wav()};
    expect(
      () => PackManifest.fromJson(manifestFor(files)),
      throwsFormatException,
    );
  });

  test('rejects a WAV header with an inconsistent byte rate', () {
    final malformed = _wav();
    ByteData.sublistView(malformed).setUint32(28, 33, Endian.little);
    final files = {...fixtureFiles(), 'sounds/tap.wav': malformed};
    final json = manifestFor(files)
      ..['sounds'] = [
        {'event': 'pet', 'asset': 'sounds/tap.wav'},
      ];
    final manifest = PackManifest.fromJson(json);
    expect(() => manifest.verifyAssets(files), throwsFormatException);
  });
}

Uint8List _wav() {
  final bytes = Uint8List(46);
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  bytes.setAll(36, 'data'.codeUnits);
  ByteData.sublistView(bytes)
    ..setUint32(4, 38, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 8000, Endian.little)
    ..setUint32(28, 16000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, 2, Endian.little);
  return bytes;
}
