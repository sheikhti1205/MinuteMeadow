import 'dart:typed_data';

import 'package:archive/archive.dart';

class PackArchive {
  static const maximumBytes = 16 * 1024 * 1024;
  static const maximumEntryBytes = 4 * 1024 * 1024;
  static const maximumEntries = 128;
  static final _component = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$');

  static Map<String, Uint8List> read(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const FormatException('Pack archive is empty or too large.');
    }

    final directory = ZipDirectory();
    try {
      directory.read(InputMemoryStream(bytes), verify: true);
    } on ArchiveException {
      throw const FormatException('The pack archive is damaged.');
    } on RangeError {
      throw const FormatException('The pack archive is damaged.');
    }

    if (directory.filePosition < 0 ||
        directory.fileHeaders.isEmpty ||
        directory.fileHeaders.length > maximumEntries) {
      throw const FormatException('Invalid pack archive directory.');
    }

    final candidates = <String, ZipFile>{};
    final paths = <String>{};
    var totalBytes = 0;

    for (final header in directory.fileHeaders) {
      final file = header.file;
      if (file == null) throw const FormatException('Missing ZIP entry.');
      final entryPath = file.filename;
      final isDirectory = entryPath.endsWith('/');
      final path = isDirectory
          ? entryPath.substring(0, entryPath.length - 1)
          : entryPath;
      final type = (header.externalFileAttributes >>> 16) & 0xf000;
      if (path.length > 200 ||
          path.split('/').any((part) => !_component.hasMatch(part)) ||
          !paths.add(path.toLowerCase()) ||
          (file.flags & 1) != 0 ||
          (type != 0 && type != (isDirectory ? 0x4000 : 0x8000))) {
        throw const FormatException('Unsafe or duplicate pack path.');
      }
      if (isDirectory) {
        if (file.uncompressedSize != 0) {
          throw const FormatException('A pack folder contains unexpected data.');
        }
        continue;
      }
      final size = file.uncompressedSize;
      if (size < 0 ||
          size > maximumEntryBytes ||
          size > maximumBytes - totalBytes ||
          file.unsupportedMethod != null ||
          (file.compressionMethod != CompressionType.none &&
              file.compressionMethod != CompressionType.deflate)) {
        throw const FormatException('Unsupported or oversized pack entry.');
      }
      totalBytes += size;
      candidates[path] = file;
    }

    final filePaths = candidates.keys.map((path) => path.toLowerCase()).toSet();
    for (final path in paths) {
      var separator = path.indexOf('/');
      while (separator != -1) {
        if (filePaths.contains(path.substring(0, separator))) {
          throw const FormatException('A pack file is also used as a folder.');
        }
        separator = path.indexOf('/', separator + 1);
      }
    }

    if (!candidates.containsKey('manifest.json')) {
      throw const FormatException('The archive has no manifest.json at its root.');
    }

    final contents = <String, Uint8List>{};
    try {
      for (final MapEntry(:key, value: file) in candidates.entries) {
        file
          ..verify = true
          ..throwOnError = true;
        contents[key] = file.getStream().toUint8List();
      }
    } on ArchiveException {
      throw const FormatException('Could not read the pack archive.');
    } on RangeError {
      throw const FormatException('Could not read the pack archive.');
    }
    return Map.unmodifiable(contents);
  }
}
