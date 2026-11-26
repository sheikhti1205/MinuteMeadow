import 'dart:convert';
import 'dart:typed_data';

import 'pack_bundle.dart';
import 'pack_json.dart';
import 'pack_manifest.dart';

/// A validated pack installed on this device.
class InstalledPack {
  InstalledPack({
    required this.manifest,
    required Map<String, PackAsset> assets,
    required this.installedAt,
  }) : assets = Map.unmodifiable(assets);

  final PackManifest manifest;
  final Map<String, PackAsset> assets;
  final DateTime installedAt;

  String get id => manifest.id;
  String get version => manifest.version;

  Map<String, Object?> toJson() {
    final paths = assets.keys.toList()..sort();
    return {
      'installedAt': installedAt.millisecondsSinceEpoch,
      'manifest': manifest.toJson(),
      'assets': {
        for (final path in paths) path: base64.encode(assets[path]!.bytes),
      },
    };
  }

  static InstalledPack fromJson(String id, Object? json) {
    final map = packObject(
      json,
      'The installed companion',
      required: const {'installedAt', 'manifest', 'assets'},
    );
    final manifest = PackManifest.fromJson(map['manifest']);
    if (manifest.id != id) {
      throw const FormatException('An installed companion has a mismatched id.');
    }
    final installedAt = map['installedAt'];
    if (installedAt is! int || installedAt < 0) {
      throw const FormatException('An installed companion has an invalid date.');
    }
    final encoded = readEncodedAssets(map['assets'], manifest);
    final provided = <String, Uint8List>{
      for (final entry in encoded.entries)
        entry.key: decodeAssetText(entry.key, entry.value),
    };
    return InstalledPack(
      manifest: manifest,
      assets: manifest.verifyAssets(provided),
      installedAt: DateTime.fromMillisecondsSinceEpoch(installedAt, isUtc: true),
    );
  }
}

/// The outcome of reading a stored library snapshot.
class LibraryReadResult {
  const LibraryReadResult({required this.library, this.rejected = 0, this.error});

  final CompanionLibrary library;
  final int rejected;
  final String? error;
}

/// The packs installed on this device, stored as one bounded snapshot.
///
/// Every change is built as a new value, validated, written through the
/// snapshot callback and only then adopted, so a failed write leaves the
/// previous version usable.
class CompanionLibrary {
  CompanionLibrary._(Map<String, InstalledPack> packs)
    : _packs = Map.unmodifiable(packs);

  static final empty = CompanionLibrary._(const <String, InstalledPack>{});

  static const schema = 'companion.library/1';

  final Map<String, InstalledPack> _packs;

  bool get isEmpty => _packs.isEmpty;
  int get length => _packs.length;

  List<InstalledPack> get packs {
    final sorted = _packs.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(sorted);
  }

  InstalledPack? pack(String id) => _packs[id];

  CompanionLibrary install(InstalledPack pack) {
    if (!_packs.containsKey(pack.id) && _packs.length >= PackLimits.maxPacks) {
      throw const FormatException('Too many companions are installed.');
    }
    final next = Map<String, InstalledPack>.of(_packs)..[pack.id] = pack;
    return CompanionLibrary._(next);
  }

  CompanionLibrary remove(String id) {
    if (!_packs.containsKey(id)) return this;
    final next = Map<String, InstalledPack>.of(_packs)..remove(id);
    return CompanionLibrary._(next);
  }

  String encode() {
    final encoded = jsonEncode({
      'schema': schema,
      'packs': {
        for (final pack in packs) pack.id: pack.toJson(),
      },
    });
    if (encoded.length > PackLimits.snapshotCharacters) {
      throw const FormatException('The companion library is too large to save.');
    }
    return encoded;
  }

  static LibraryReadResult decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return LibraryReadResult(library: empty);
    }
    if (source.length > PackLimits.snapshotCharacters) {
      return LibraryReadResult(
        library: empty,
        error: 'The companion library is too large to read.',
      );
    }
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return LibraryReadResult(
        library: empty,
        error: 'The companion library could not be read.',
      );
    }
    if (json is! Map<Object?, Object?>) {
      return LibraryReadResult(
        library: empty,
        error: 'The companion library could not be read.',
      );
    }
    if (json['schema'] != schema) {
      return LibraryReadResult(
        library: empty,
        error: 'Unsupported companion library version.',
      );
    }
    final packsValue = json['packs'];
    if (packsValue is! Map<Object?, Object?>) {
      return LibraryReadResult(
        library: empty,
        error: 'The companion library could not be read.',
      );
    }

    var rejected = 0;
    final packs = <String, InstalledPack>{};
    for (final entry in packsValue.entries) {
      final id = entry.key;
      if (id is! String) {
        rejected++;
        continue;
      }
      if (packs.length >= PackLimits.maxPacks) {
        rejected++;
        continue;
      }
      try {
        final pack = InstalledPack.fromJson(id, entry.value);
        packs[pack.id] = pack;
      } on FormatException {
        rejected++;
      } catch (_) {
        rejected++;
      }
    }
    return LibraryReadResult(
      library: CompanionLibrary._(packs),
      rejected: rejected,
    );
  }
}
