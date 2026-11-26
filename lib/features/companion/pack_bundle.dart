import 'dart:convert';
import 'dart:typed_data';

import '../../core/storage/pack_archive.dart';
import 'pack_json.dart';
import 'pack_manifest.dart';

/// The number of base64 characters a padded encoding of [bytes] uses.
int base64Length(int bytes) => 4 * ((bytes + 2) ~/ 3);

final _base64 = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

/// Reads the encoded asset map of a bundle and checks it matches the manifest.
Map<String, String> readEncodedAssets(Object? value, PackManifest manifest) {
  final declared = {for (final asset in manifest.assets) asset.path: asset};
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('Pack assets must be an object.');
  }
  if (value.length != declared.length) {
    throw const FormatException('The pack must contain exactly its declared assets.');
  }
  final encoded = <String, String>{};
  for (final entry in value.entries) {
    final path = entry.key;
    if (path is! String) {
      throw const FormatException('Pack assets must be named.');
    }
    final ref = declared[path];
    if (ref == null) {
      throw FormatException('The pack has an unexpected asset "$path".');
    }
    final text = entry.value;
    if (text is! String ||
        text.length != base64Length(ref.bytes) ||
        !_base64.hasMatch(text)) {
      throw FormatException('${ref.path} is not valid base64.');
    }
    encoded[ref.path] = text;
  }
  return encoded;
}

Uint8List decodeAssetText(String path, String text) {
  try {
    return base64.decode(text);
  } on FormatException {
    throw FormatException('$path is not valid base64.');
  }
}

/// A pack document carrying a strict manifest and verified asset bytes.
///
/// The JSON envelope is the import form shared by the web build and local
/// development. A packaged archive is read by [PackArchive] and bridged through
/// [fromArchive] so both paths reach the same validator.
class PackBundle {
  PackBundle._({required this.manifest, required this.assets});

  final PackManifest manifest;
  final Map<String, PackAsset> assets;

  static PackBundle decode(String source) {
    if (source.length > PackLimits.bundleCharacters) {
      throw const FormatException('The pack file is too large to import.');
    }
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      throw const FormatException('The pack file is not valid JSON.');
    }
    return fromJson(json);
  }

  static PackBundle fromJson(Object? json) {
    final map = packObject(
      json,
      'The pack file',
      required: const {'schema', 'manifest', 'assets'},
    );
    if (map['schema'] != PackManifest.applicationSchema) {
      throw FormatException(
        'Unsupported pack file version. This build reads ${PackManifest.applicationSchema}.',
      );
    }
    final manifestValue = map['manifest'];
    final manifestSize = jsonEncode(manifestValue).length;
    if (manifestSize > PackLimits.manifestCharacters) {
      throw const FormatException('The pack manifest is too large.');
    }
    final manifest = PackManifest.fromJson(manifestValue);
    final encoded = readEncodedAssets(map['assets'], manifest);
    final provided = <String, Uint8List>{
      for (final entry in encoded.entries)
        entry.key: decodeAssetText(entry.key, entry.value),
    };
    return PackBundle._(manifest: manifest, assets: manifest.verifyAssets(provided));
  }

  /// Bridges a validated archive directory to the same manifest validator.
  ///
  /// ZIP CRCs prove the archive is intact; they never stand in for a manifest
  /// hash. Each asset is still checked against the SHA-256 the manifest
  /// declares.
  static PackBundle fromArchive(Map<String, Uint8List> contents) {
    final manifestBytes = contents['manifest.json'];
    if (manifestBytes == null) {
      throw const FormatException('The pack archive has no manifest.json at its root.');
    }
    if (manifestBytes.length > PackLimits.manifestCharacters) {
      throw const FormatException('The pack manifest is too large.');
    }
    final String text;
    try {
      text = utf8.decode(manifestBytes);
    } on FormatException {
      throw const FormatException('The pack manifest is not valid UTF-8.');
    }
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The pack manifest is not valid JSON.');
    }
    final manifest = PackManifest.fromJson(json);
    final declared = {for (final asset in manifest.assets) asset.path: asset};
    final provided = <String, Uint8List>{};
    for (final entry in contents.entries) {
      final path = entry.key;
      if (path == 'manifest.json' || path == 'LICENSE' || path == 'LICENSE.txt') {
        continue;
      }
      if (!declared.containsKey(path)) {
        throw FormatException('The pack archive has an undeclared file "$path".');
      }
      provided[path] = entry.value;
    }
    return PackBundle._(manifest: manifest, assets: manifest.verifyAssets(provided));
  }

  /// Reads either a packaged archive or a JSON envelope.
  static PackBundle fromUpload(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('The pack file is empty.');
    }
    if (bytes.length > PackArchive.maximumBytes) {
      throw const FormatException('The pack file is too large to import.');
    }
    final zipped =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (zipped) {
      return fromArchive(PackArchive.read(bytes));
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('The pack file is neither a pack archive nor readable text.');
    }
    return decode(text);
  }
}
