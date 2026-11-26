import 'dart:typed_data';

import 'pack_manifest.dart';

/// The declared geometry of a pack image.
class PngInfo {
  const PngInfo({required this.width, required this.height, required this.colorType});

  final int width;
  final int height;
  final int colorType;
}

/// Validates a PNG container without decoding pixels.
///
/// It checks the signature, walks every chunk, verifies each chunk CRC, reads
/// the header geometry and requires the image to end with a single IEND chunk
/// and no trailing bytes. Image pixels are decoded later by the render surface,
/// which must treat a decode failure as a missing image.
PngInfo inspectPng(Uint8List bytes, String name) {
  if (bytes.length < 45) {
    throw FormatException('$name is not a PNG image.');
  }
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) {
      throw FormatException('$name is not a PNG image.');
    }
  }

  var width = 0;
  var height = 0;
  var colorType = 0;
  var hasHeader = false;
  var offset = 8;

  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) {
      throw FormatException('$name is not a complete PNG image.');
    }
    final length = _uint32(bytes, offset);
    if (length > bytes.length - offset - 12) {
      throw FormatException('$name is not a complete PNG image.');
    }
    final typeStart = offset + 4;
    for (var i = 0; i < 4; i++) {
      final unit = bytes[typeStart + i];
      final letter = (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
      if (!letter) {
        throw FormatException('$name has an invalid PNG block.');
      }
    }
    final dataStart = offset + 8;
    if (_uint32(bytes, dataStart + length) != _crc32(bytes, typeStart, length + 4)) {
      throw FormatException('$name has a damaged PNG block.');
    }
    final type = String.fromCharCodes(bytes, typeStart, typeStart + 4);
    if (!hasHeader) {
      if (type != 'IHDR' || length != 13) {
        throw FormatException('$name has no PNG header.');
      }
      width = _uint32(bytes, dataStart);
      height = _uint32(bytes, dataStart + 4);
      final bitDepth = bytes[dataStart + 8];
      colorType = bytes[dataStart + 9];
      if (bytes[dataStart + 10] != 0 ||
          bytes[dataStart + 11] != 0 ||
          bytes[dataStart + 12] != 0) {
        throw FormatException('$name uses an unsupported PNG encoding.');
      }
      if (bitDepth != 8) {
        throw FormatException('$name must use 8-bit colour.');
      }
      if (colorType != 0 && colorType != 2 && colorType != 3 && colorType != 4 && colorType != 6) {
        throw FormatException('$name uses an unsupported PNG colour type.');
      }
      if (width < 1 ||
          height < 1 ||
          width > PackLimits.maxImage ||
          height > PackLimits.maxImage) {
        throw FormatException('$name must be between 1 and ${PackLimits.maxImage} pixels.');
      }
      hasHeader = true;
    } else if (type == 'IHDR') {
      throw FormatException('$name has a repeated PNG header.');
    }
    if (type == 'IEND') {
      if (length != 0) {
        throw FormatException('$name has an invalid PNG trailer.');
      }
      offset = dataStart + 4;
      break;
    }
    offset = dataStart + length + 4;
  }

  if (!hasHeader) {
    throw FormatException('$name has no PNG header.');
  }
  if (offset != bytes.length) {
    throw FormatException('$name has trailing data.');
  }
  return PngInfo(width: width, height: height, colorType: colorType);
}

int _uint32(Uint8List bytes, int start) =>
    (bytes[start] << 24 | bytes[start + 1] << 16 | bytes[start + 2] << 8 | bytes[start + 3]) &
    0xFFFFFFFF;

Uint32List? _crcTable;

int _crc32(Uint8List bytes, int start, int length) {
  final table = _crcTable ??= _buildCrcTable();
  var crc = 0xFFFFFFFF;
  final end = start + length;
  for (var i = start; i < end; i++) {
    crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
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
