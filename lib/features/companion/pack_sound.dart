import 'dart:typed_data';

import 'pack_json.dart';

class PackSound {
  const PackSound({
    required this.event,
    required this.asset,
    required this.volume,
  });

  final String event;
  final String asset;
  final double volume;

  Map<String, Object> toJson() => {
    'event': event,
    'asset': asset,
    'volume': volume,
  };

  static List<PackSound> readList(Object? json) {
    if (json is! List<Object?> || json.length > 16) {
      throw const FormatException('A pack supports up to 16 sounds.');
    }
    final sounds = <PackSound>[];
    final events = <String>{};
    for (final value in json) {
      final map = packObject(
        value,
        'A sound',
        required: const {'event', 'asset'},
        optional: const {'volume'},
      );
      final event = packText(map['event'], 'Sound event', max: 24, pattern: _event);
      if (!events.add(event)) throw const FormatException('A sound event is repeated.');
      final asset = packText(map['asset'], 'Sound asset', min: 5, max: 120);
      final volume = map['volume'] ?? 1;
      if (volume is! num || !volume.isFinite || volume < 0 || volume > 1) {
        throw const FormatException('Sound volume must be between 0 and 1.');
      }
      sounds.add(PackSound(event: event, asset: asset, volume: volume.toDouble()));
    }
    return List.unmodifiable(sounds);
  }
}

final _event = RegExp(r'^[a-z0-9_-]{1,24}$');

bool isWaveAsset(String path) => path.startsWith('sounds/') && path.toLowerCase().endsWith('.wav');

void verifyWave(Uint8List bytes, String path) {
  Never invalid() => throw FormatException('$path is not a supported PCM WAV sound.');
  if (bytes.length < 44) invalid();
  final data = ByteData.sublistView(bytes);
  String nameAt(int offset) => String.fromCharCodes(bytes, offset, offset + 4);
  int word(int offset) => data.getUint16(offset, Endian.little);
  int length(int offset) => data.getUint32(offset, Endian.little);

  if (nameAt(0) != 'RIFF' || nameAt(8) != 'WAVE' || length(4) != bytes.length - 8) {
    invalid();
  }
  int? align;
  int? byteRate;
  var samples = 0;
  var offset = 12;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) invalid();
    final name = nameAt(offset);
    final size = length(offset + 4);
    final start = offset + 8;
    final end = start + size + (size.isOdd ? 1 : 0);
    if (end > bytes.length) invalid();
    if (name == 'fmt ') {
      if (size < 16 || align != null) invalid();
      final channels = word(start + 2);
      final sampleRate = length(start + 4);
      final blockAlign = word(start + 12);
      final rate = length(start + 8);
      if (word(start) != 1 || channels < 1 || channels > 2 ||
          sampleRate < 8000 || sampleRate > 48000 ||
          word(start + 14) != 16 || blockAlign != channels * 2 ||
          rate != blockAlign * sampleRate) {
        invalid();
      }
      align = blockAlign;
      byteRate = rate;
    } else if (name == 'data') {
      if (align == null || samples != 0 || size == 0 ||
          size % align != 0 || size > byteRate! * 3) {
        invalid();
      }
      samples = size;
    }
    offset = end;
  }
  if (samples == 0) invalid();
}
