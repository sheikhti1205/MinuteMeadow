import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../rig/rig_model.dart';

final class RigFileException implements Exception {
  const RigFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Development-only file picking and bounded reads for external rig manifests
/// and atlas images. Reads are capped before and after loading so a large file
/// cannot enter the laboratory.
abstract final class RigFileLoader {
  static const int maxManifestBytes = 512 * 1024;
  static const int maxAtlasBytes = 16 * 1024 * 1024;

  static const List<XTypeGroup> manifestTypes = <XTypeGroup>[
    XTypeGroup(
      label: 'Rig manifest',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json'],
    ),
  ];

  static const List<XTypeGroup> atlasTypes = <XTypeGroup>[
    XTypeGroup(
      label: 'Atlas image',
      extensions: <String>['png', 'webp'],
      mimeTypes: <String>['image/png', 'image/webp'],
    ),
  ];

  static Future<XFile?> pickManifest() =>
      openFile(acceptedTypeGroups: manifestTypes);

  static Future<XFile?> pickAtlas() => openFile(acceptedTypeGroups: atlasTypes);

  static Future<String> readManifestText(
    XFile file, {
    int maxBytes = maxManifestBytes,
  }) async {
    final bytes = await readBytes(
      file,
      maxBytes: maxBytes,
      label: 'Manifest',
    );
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const RigFileException('The manifest is not valid UTF-8.');
    }
  }

  static Future<Uint8List> readAtlasBytes(
    XFile file, {
    int maxBytes = maxAtlasBytes,
  }) => readBytes(file, maxBytes: maxBytes, label: 'Atlas image');

  /// Chooses the atlas a picked image belongs to. Exact id or image-key matches
  /// win; a rig with one atlas always resolves; otherwise a single unfilled
  /// atlas in the manifest is used.
  static String resolveAtlasId(
    CompanionRig rig,
    String fileName, {
    required Set<String> loadedAtlasIds,
  }) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final matches = <String>[
      for (final atlas in rig.atlases.values)
        if (atlas.imageKey == fileName ||
            atlas.id == fileName ||
            atlas.id == stem)
          atlas.id,
    ];
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) {
      throw RigFileException(
        '"$fileName" matches more than one atlas: ${matches.join(', ')}.',
      );
    }
    if (rig.atlases.length == 1) return rig.atlases.keys.first;
    final missing = <String>[
      for (final atlas in rig.atlases.values)
        if (!loadedAtlasIds.contains(atlas.id)) atlas.id,
    ];
    if (missing.length == 1) return missing.single;
    throw RigFileException(
      'Could not match "$fileName" to an atlas. '
      'Expected ${rig.atlases.keys.join(', ')}.',
    );
  }

  static Future<Uint8List> readBytes(
    XFile file, {
    required int maxBytes,
    required String label,
  }) async {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
    }
    final length = await file.length();
    if (length > maxBytes) {
      throw RigFileException(
        '$label is $length bytes; the limit is $maxBytes bytes.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw RigFileException(
        '$label grew to ${bytes.length} bytes; the limit is $maxBytes bytes.',
      );
    }
    return bytes;
  }
}
