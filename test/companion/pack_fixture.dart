import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_focus/features/companion/companion_library.dart';
import 'package:companion_focus/features/companion/pack_bundle.dart';
import 'package:crypto/crypto.dart';

/// Builds a small, valid RGBA PNG without any external codec dependency.
Uint8List buildPng({
  int width = 4,
  int height = 4,
  int red = 0x87,
  int green = 0x38,
  int blue = 0x29,
}) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add(<int>[red, green, blue, 255]);
    }
  }
  final header = BytesBuilder()
    ..add(_uint32(width))
    ..add(_uint32(height))
    ..addByte(8)
    ..addByte(6)
    ..addByte(0)
    ..addByte(0)
    ..addByte(0);
  final out = BytesBuilder()..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  out.add(_chunk('IHDR', header.takeBytes()));
  out.add(_chunk('IDAT', _zlibStored(raw.takeBytes())));
  out.add(_chunk('IEND', const <int>[]));
  return out.takeBytes();
}

Map<String, Uint8List> fixtureFiles({int width = 4, int height = 4}) => {
  'preview.png': buildPng(width: width, height: height),
};

Map<String, Object?> manifestFor(
  Map<String, Uint8List> files, {
  String id = 'dev.example.geometric',
  String version = '1.0.0',
  String name = 'Geometric',
  String author = 'Example Studio',
  String preview = 'preview.png',
  String? description,
  String? homepage,
  String? minimumAppVersion,
  List<String> palette = const ['#873829', '#4E5940'],
  Map<String, Object?>? canvas,
  List<Map<String, Object?>>? layers,
  List<Map<String, Object?>>? clips,
}) {
  final paths = files.keys.toList()..sort();
  final assets = <Map<String, Object?>>[
    for (final path in paths)
      {
        'path': path,
        'sha256': sha256.convert(files[path]!).toString(),
        'bytes': files[path]!.length,
      },
  ];
  final first = paths.first;
  return {
    'schema': 'companion.pack/1',
    'id': id,
    'version': version,
    'name': name,
    'author': author,
    'license': 'CC-BY-4.0',
    'preview': preview,
    if (description != null) 'description': description,
    if (homepage != null) 'homepage': homepage,
    if (minimumAppVersion != null) 'application': {'minVersion': minimumAppVersion},
    'canvas': canvas ?? {'width': 32, 'height': 32},
    'palette': palette,
    'layers': layers ?? [
      {'id': 'body', 'z': 0},
    ],
    'clips': clips ?? [
      {
        'id': 'idle',
        'fps': 8,
        'loop': true,
        'frames': [
          {
            'layer': 'body',
            'asset': first,
            'rect': {'x': 0, 'y': 0, 'w': 4, 'h': 4},
          },
        ],
      },
    ],
    'assets': assets,
  };
}

Map<String, Object?> bundleFor(
  Map<String, Uint8List> files, {
  String id = 'dev.example.geometric',
  String version = '1.0.0',
  String name = 'Geometric',
  String author = 'Example Studio',
  String? minimumAppVersion,
  List<String> palette = const ['#873829', '#4E5940'],
}) => {
  'schema': 'companion.bundle/1',
  'manifest': manifestFor(
    files,
    id: id,
    version: version,
    name: name,
    author: author,
    minimumAppVersion: minimumAppVersion,
    palette: palette,
  ),
  'assets': {
    for (final entry in files.entries) entry.key: base64.encode(entry.value),
  },
};

String bundleText(
  Map<String, Uint8List> files, {
  String id = 'dev.example.geometric',
  String version = '1.0.0',
  String name = 'Geometric',
  String author = 'Example Studio',
  String? minimumAppVersion,
  List<String> palette = const ['#873829', '#4E5940'],
}) => jsonEncode(
  bundleFor(
    files,
    id: id,
    version: version,
    name: name,
    author: author,
    minimumAppVersion: minimumAppVersion,
    palette: palette,
  ),
);

String catalogueText(
  List<Map<String, Object?>> bundles, {
  List<String> categories = const ['geometric'],
  int schema = 1,
}) => jsonEncode({
  'schema': schema,
  'packs': [
    for (var index = 0; index < bundles.length; index++)
      {
        'category': index < categories.length ? categories[index] : 'geometric',
        'bundle': bundles[index],
      },
  ],
});

InstalledPack installedFixture({
  String id = 'dev.example.geometric',
  String version = '1.0.0',
  String name = 'Geometric',
  Map<String, Uint8List>? files,
}) {
  final bundle = PackBundle.decode(
    bundleText(files ?? fixtureFiles(), id: id, version: version, name: name),
  );
  return InstalledPack(
    manifest: bundle.manifest,
    assets: bundle.assets,
    installedAt: DateTime.utc(2026, 1, 2),
  );
}

Uint8List _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  out.add(_uint32(data.length));
  final typeBytes = ascii.encode(type);
  out.add(typeBytes);
  out.add(data);
  out.add(_uint32(_crc32(Uint8List.fromList(<int>[...typeBytes, ...data]))));
  return out.takeBytes();
}

Uint8List _zlibStored(Uint8List data) {
  final out = BytesBuilder()..add(const <int>[0x78, 0x01]);
  if (data.isEmpty) {
    out.add(const <int>[1, 0, 0, 0xFF, 0xFF]);
  }
  var offset = 0;
  while (offset < data.length) {
    final size = data.length - offset > 65535 ? 65535 : data.length - offset;
    out.addByte(offset + size == data.length ? 1 : 0);
    out.addByte(size & 0xFF);
    out.addByte((size >> 8) & 0xFF);
    out.addByte(~size & 0xFF);
    out.addByte((~size >> 8) & 0xFF);
    out.add(Uint8List.sublistView(data, offset, offset + size));
    offset += size;
  }
  out.add(_uint32(_adler32(data)));
  return out.takeBytes();
}

int _adler32(Uint8List data) {
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

Uint8List _uint32(int value) => Uint8List.fromList(<int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

Uint32List? _crcTable;

int _crc32(Uint8List bytes) {
  final table = _crcTable ??= _buildCrcTable();
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var value = n;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 1 ? 0xEDB88320 ^ (value >> 1) : value >> 1;
    }
    table[n] = value;
  }
  return table;
}
