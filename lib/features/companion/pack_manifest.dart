import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pack_json.dart';
import 'pack_motion.dart';
import 'pack_sound.dart';
import 'png.dart';

/// Hard limits applied to every pack document and asset.
abstract final class PackLimits {
  static const manifestCharacters = 256 * 1024;
  static const bundleCharacters = 8 * 1024 * 1024;
  static const catalogueCharacters = 16 * 1024 * 1024;
  static const snapshotCharacters = 12 * 1024 * 1024;

  static const assetBytes = 512 * 1024;
  static const totalAssetBytes = 2 * 1024 * 1024;

  static const maxAssets = 16;
  static const maxLayers = 8;
  static const maxClips = 16;
  static const maxFrames = 120;
  static const maxPalette = 32;
  static const maxPacks = 64;
  static const maxCataloguePacks = 64;

  static const minImage = 1;
  static const maxImage = 512;
  static const minCanvas = 8;
  static const maxCanvas = 512;
}

const _packIdPattern = r'^[a-z0-9]+(?:-[a-z0-9]+)*(?:\.[a-z0-9]+(?:-[a-z0-9]+)*)+$';
const _versionPattern = r'^\d{1,3}\.\d{1,3}\.\d{1,3}$';
const _licensePattern = r'^[A-Za-z0-9][A-Za-z0-9 .+()\-]{0,63}$';
const _colourPattern = r'^#[0-9a-fA-F]{6}$';
const _shaPattern = r'^[0-9a-f]{64}$';
const _namePattern = r'^[a-z0-9_-]{1,24}$';
const _segmentPattern = r'^[A-Za-z0-9._-]+$';
const _pathPattern = r'^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+){0,3}$';

final _id = RegExp(_packIdPattern);
final _version = RegExp(_versionPattern);
final _license = RegExp(_licensePattern);
final _colour = RegExp(_colourPattern);
final _sha = RegExp(_shaPattern);
final _name = RegExp(_namePattern);
final _segment = RegExp(_segmentPattern);
final _path = RegExp(_pathPattern);

/// Rejects asset paths that could escape the pack or name a non-image.
String validateAssetPath(String path, {bool allowSound = false}) {
  if (path.length < 5 || path.length > 120) {
    throw const FormatException('An asset path has an invalid length.');
  }
  if (!_path.hasMatch(path)) {
    throw const FormatException('An asset path is not safe.');
  }
  for (final part in path.split('/')) {
    if (!_segment.hasMatch(part) || part == '.' || part == '..') {
      throw const FormatException('An asset path is not safe.');
    }
  }
  if (!path.toLowerCase().endsWith('.png') && !(allowSound && isWaveAsset(path))) {
    throw const FormatException('Use PNG images or WAV files under sounds/.');
  }
  return path;
}

/// Compares two `MAJOR.MINOR.PATCH` versions.
int comparePackVersions(String left, String right) {
  final a = _versionNumbers(left);
  final b = _versionNumbers(right);
  for (var i = 0; i < 3; i++) {
    final difference = a[i] - b[i];
    if (difference != 0) return difference;
  }
  return 0;
}

List<int> _versionNumbers(String version) {
  if (!_version.hasMatch(version)) {
    throw const FormatException('A pack version is not valid.');
  }
  final parts = version.split('.');
  return [for (final part in parts) int.parse(part)];
}

class PackLayer {
  const PackLayer({required this.id, required this.z, this.pose = const PackLayerPose()});

  final String id;
  final int z;
  final PackLayerPose pose;

  Map<String, Object?> toJson() => {'id': id, 'z': z, ...pose.toJson()};
}

class PackRect {
  const PackRect({required this.x, required this.y, required this.width, required this.height});

  final int x;
  final int y;
  final int width;
  final int height;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': width, 'h': height};
}

class PackFrame {
  const PackFrame({required this.layer, required this.asset, required this.rect});

  final String layer;
  final String asset;
  final PackRect rect;

  Map<String, Object?> toJson() => {
    'layer': layer,
    'asset': asset,
    'rect': rect.toJson(),
  };
}

class PackClip {
  const PackClip({
    required this.id,
    required this.fps,
    required this.loop,
    required this.frames,
    this.durationMs,
    this.tracks = const [],
    this.events = const [],
    this.state,
  });

  final String id;
  final int fps;
  final bool loop;
  final List<PackFrame> frames;
  final int? durationMs;
  final List<PackMotionTrack> tracks;
  final List<PackMotionMarker> events;
  final PackStatePolicy? state;

  int get frameDurationMs => (1000 / fps).round();
  int get timelineDurationMs => durationMs ?? _frameSpan(frames, fps);

  Map<String, Object?> toJson() => {
    'id': id,
    'fps': fps,
    'loop': loop,
    'frames': [for (final frame in frames) frame.toJson()],
    if (durationMs != null) 'durationMs': durationMs,
    if (tracks.isNotEmpty) 'tracks': [for (final track in tracks) track.toJson()],
    if (events.isNotEmpty) 'events': [for (final event in events) event.toJson()],
    if (state != null) 'state': state!.toJson(),
  };

  static int _frameSpan(List<PackFrame> frames, int fps) {
    final totals = <String, int>{};
    var longest = 1;
    for (final frame in frames) {
      final count = (totals[frame.layer] ?? 0) + 1;
      totals[frame.layer] = count;
      if (count > longest) longest = count;
    }
    return (1000 / fps).round() * longest;
  }
}

class PackAssetRef {
  const PackAssetRef({required this.path, required this.sha256, required this.bytes});

  final String path;
  final String sha256;
  final int bytes;

  Map<String, Object?> toJson() => {'path': path, 'sha256': sha256, 'bytes': bytes};
}

/// Verified image bytes and their declared geometry.
class PackAsset {
  const PackAsset({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;
  final int width;
  final int height;
}

/// A validated declarative pack manifest. It contains no executable content.
class PackManifest {
  PackManifest({
    required this.id,
    required this.version,
    required this.name,
    required this.author,
    required this.license,
    required this.preview,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.palette,
    required this.layers,
    required this.clips,
    required this.assets,
    this.description,
    this.attribution,
    this.homepage,
    this.minimumAppVersion,
    this.sounds = const [],
  }) : _assetsByPath = {for (final asset in assets) asset.path: asset};

  static const schema = 'companion.pack/1';
  static const applicationSchema = 'companion.bundle/1';

  final String id;
  final String version;
  final String name;
  final String author;
  final String license;
  final String preview;
  final int canvasWidth;
  final int canvasHeight;
  final List<String> palette;
  final List<PackLayer> layers;
  final List<PackClip> clips;
  final List<PackAssetRef> assets;
  final String? description;
  final String? attribution;
  final String? homepage;
  final String? minimumAppVersion;
  final List<PackSound> sounds;
  final Map<String, PackAssetRef> _assetsByPath;

  PackAssetRef? asset(String path) => _assetsByPath[path];

  int get byteSize => assets.fold(0, (total, asset) => total + asset.bytes);

  bool isCompatibleWith(String appVersion) {
    final required = minimumAppVersion;
    return required == null || comparePackVersions(appVersion, required) >= 0;
  }

  Map<String, Object?> toJson() {
    final sortedAssets = [...assets]..sort((a, b) => a.path.compareTo(b.path));
    return {
      'schema': schema,
      'id': id,
      'version': version,
      'name': name,
      'author': author,
      'license': license,
      'preview': preview,
      if (description != null) 'description': description,
      if (attribution != null) 'attribution': attribution,
      if (homepage != null) 'homepage': homepage,
      if (minimumAppVersion != null) 'application': {'minVersion': minimumAppVersion},
      'canvas': {'width': canvasWidth, 'height': canvasHeight},
      'palette': palette,
      'layers': [for (final layer in layers) layer.toJson()],
      'clips': [for (final clip in clips) clip.toJson()],
      'assets': [for (final asset in sortedAssets) asset.toJson()],
      if (sounds.isNotEmpty) 'sounds': [for (final sound in sounds) sound.toJson()],
    };
  }

  static PackManifest fromJson(Object? json) {
    final map = packObject(
      json,
      'The manifest',
      required: const {'schema', 'id', 'version', 'name', 'author', 'license', 'preview', 'canvas', 'palette', 'layers', 'clips', 'assets'},
      optional: const {'description', 'attribution', 'homepage', 'application', 'sounds'},
    );
    if (map['schema'] != schema) {
      throw FormatException('Unsupported manifest version. This build reads $schema.');
    }
    final id = packText(
      map['id'],
      'The pack id',
      min: 3,
      max: 128,
      pattern: _id,
      complaint: 'The pack id must be a lowercase dotted name.',
    );
    final version = packText(
      map['version'],
      'The pack version',
      min: 5,
      max: 18,
      pattern: _version,
      complaint: 'Pack versions use MAJOR.MINOR.PATCH.',
    );
    final name = packText(map['name'], 'The name', min: 1, max: 64);
    final author = packText(map['author'], 'The author', min: 1, max: 64);
    final license = packText(
      map['license'],
      'The license',
      max: 64,
      pattern: _license,
      complaint: 'The license must be a short identifier.',
    );
    final preview = packText(map['preview'], 'The preview', min: 5, max: 120);
    validateAssetPath(preview);
    final description = map['description'] == null
        ? null
        : packText(map['description'], 'The description', min: 1, max: 280);
    final attribution = map['attribution'] == null
        ? null
        : packText(map['attribution'], 'The attribution', min: 1, max: 512);
    final homepage = map['homepage'] == null ? null : _homepage(map['homepage']);
    final minimumAppVersion = _minimumAppVersion(map['application']);

    final canvas = packObject(
      map['canvas'],
      'The canvas',
      required: const {'width', 'height'},
    );
    final canvasWidth = packInteger(
      canvas['width'],
      'The canvas width',
      min: PackLimits.minCanvas,
      max: PackLimits.maxCanvas,
    );
    final canvasHeight = packInteger(
      canvas['height'],
      'The canvas height',
      min: PackLimits.minCanvas,
      max: PackLimits.maxCanvas,
    );

    final paletteValue = map['palette'];
    if (paletteValue is! List<Object?> ||
        paletteValue.isEmpty ||
        paletteValue.length > PackLimits.maxPalette) {
      throw const FormatException('The palette must hold 1 to 32 colours.');
    }
    final palette = <String>[];
    for (final colour in paletteValue) {
      final text = packText(
        colour,
        'A palette colour',
        min: 7,
        max: 7,
        pattern: _colour,
        complaint: 'Palette colours use #RRGGBB.',
      );
      final upper = text.toUpperCase();
      if (palette.contains(upper)) {
        throw const FormatException('The palette repeats a colour.');
      }
      palette.add(upper);
    }

    final assets = _assets(map['assets']);
    final layers = _layers(map['layers']);
    final clips = _clips(map['clips']);

    final manifest = PackManifest(
      id: id,
      version: version,
      name: name,
      author: author,
      license: license,
      preview: preview,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      palette: palette,
      layers: layers,
      clips: clips,
      assets: assets,
      description: description,
      attribution: attribution,
      homepage: homepage,
      minimumAppVersion: minimumAppVersion,
      sounds: map.containsKey('sounds') ? PackSound.readList(map['sounds']) : const [],
    );
    manifest._crossCheck();
    return manifest;
  }

  void _crossCheck() {
    final paths = _assetsByPath.keys.toSet();
    if (!paths.contains(preview)) {
      throw const FormatException('The preview must be one of the pack assets.');
    }
    for (final sound in sounds) {
      validateAssetPath(sound.asset, allowSound: true);
      if (!isWaveAsset(sound.asset) || !paths.contains(sound.asset)) {
        throw const FormatException('A sound must reference a declared WAV asset.');
      }
    }
    final usedSounds = {for (final sound in sounds) sound.asset};
    if (paths.any((path) => isWaveAsset(path) && !usedSounds.contains(path))) {
      throw const FormatException('A WAV asset must be assigned to a sound event.');
    }
    final layerIds = {for (final layer in layers) layer.id};
    final parents = {for (final layer in layers) layer.id: layer.pose.parent};
    for (final layer in layers) {
      final visited = <String>{layer.id};
      var parent = layer.pose.parent;
      while (parent != null) {
        if (!layerIds.contains(parent) || !visited.add(parent)) {
          throw FormatException('Layer ${layer.id} has an invalid parent chain.');
        }
        parent = parents[parent];
      }
    }
    final drawnLayers = {
      for (final clip in clips)
        for (final frame in clip.frames) frame.layer,
    };
    for (final layer in layers) {
      final parent = layer.pose.parent;
      if (parent != null && drawnLayers.contains(layer.id) && !drawnLayers.contains(parent)) {
        throw FormatException('Layer ${layer.id} has a parent without a sprite.');
      }
    }
    final clipIds = <String>{};
    for (final clip in clips) {
      if (!clipIds.add(clip.id)) {
        throw const FormatException('The pack repeats a clip id.');
      }
      for (final frame in clip.frames) {
        if (!layerIds.contains(frame.layer)) {
          throw FormatException('Clip ${clip.id} names an unknown layer.');
        }
        if (!paths.contains(frame.asset)) {
          throw FormatException('Clip ${clip.id} names an unknown asset.');
        }
      }
      for (final track in clip.tracks) {
        if (!layerIds.contains(track.layer) || !drawnLayers.contains(track.layer)) {
          throw FormatException('Clip ${clip.id} animates a layer without a sprite.');
        }
      }
    }
  }

  /// Checks bytes, checksums, PNG containers and frame regions.
  Map<String, PackAsset> verifyAssets(Map<String, Uint8List> provided) {
    if (provided.length != assets.length) {
      throw const FormatException('The pack must contain exactly its declared assets.');
    }
    final verified = <String, PackAsset>{};
    var total = 0;
    for (final ref in assets) {
      final data = provided[ref.path];
      if (data == null) {
        throw FormatException('The pack is missing ${ref.path}.');
      }
      if (data.length != ref.bytes) {
        throw FormatException('${ref.path} does not match its declared size.');
      }
      total += data.length;
      if (total > PackLimits.totalAssetBytes) {
        throw const FormatException('The pack assets are too large.');
      }
      if (sha256.convert(data).toString() != ref.sha256) {
        throw FormatException('${ref.path} does not match its declared checksum.');
      }
      if (isWaveAsset(ref.path)) {
        verifyWave(data, ref.path);
        verified[ref.path] = PackAsset(bytes: data, width: 0, height: 0);
      } else {
        final image = inspectPng(data, ref.path);
        verified[ref.path] = PackAsset(bytes: data, width: image.width, height: image.height);
      }
    }
    for (final clip in clips) {
      for (final frame in clip.frames) {
        final image = verified[frame.asset];
        if (image == null) {
          throw FormatException('Clip ${clip.id} names an unknown asset.');
        }
        final rect = frame.rect;
        if (rect.x + rect.width > image.width || rect.y + rect.height > image.height) {
          throw FormatException('Clip ${clip.id} has a frame outside ${frame.asset}.');
        }
      }
    }
    return verified;
  }

  static List<PackAssetRef> _assets(Object? value) {
    if (value is! List<Object?> || value.isEmpty || value.length > PackLimits.maxAssets) {
      throw const FormatException('A pack declares 1 to ${PackLimits.maxAssets} assets.');
    }
    final assets = <PackAssetRef>[];
    final paths = <String>{};
    var total = 0;
    for (final item in value) {
      final map = packObject(item, 'An asset', required: const {'path', 'sha256', 'bytes'});
      final path = packText(map['path'], 'An asset path', min: 5, max: 120);
      validateAssetPath(path, allowSound: true);
      if (!paths.add(path)) {
        throw FormatException('The pack repeats the asset $path.');
      }
      final digest = packText(
        map['sha256'],
        'An asset checksum',
        min: 64,
        max: 64,
        pattern: _sha,
        complaint: 'Asset checksums are lowercase SHA-256 hex.',
      );
      final bytes = packInteger(
        map['bytes'],
        'An asset size',
        min: 1,
        max: PackLimits.assetBytes,
      );
      total += bytes;
      assets.add(PackAssetRef(path: path, sha256: digest, bytes: bytes));
    }
    if (total > PackLimits.totalAssetBytes) {
      throw const FormatException('The pack assets are too large.');
    }
    return List.unmodifiable(assets);
  }

  static List<PackLayer> _layers(Object? value) {
    if (value is! List<Object?> || value.isEmpty || value.length > PackLimits.maxLayers) {
      throw const FormatException('A pack declares 1 to ${PackLimits.maxLayers} layers.');
    }
    final layers = <PackLayer>[];
    final ids = <String>{};
    final depths = <int>{};
    for (final item in value) {
      final map = packObject(
        item,
        'A layer',
        required: const {'id', 'z'},
        optional: const {'parent', 'offset', 'pivot', 'rotationDegrees', 'scale', 'opacity', 'visible'},
      );
      final id = packText(
        map['id'],
        'A layer id',
        min: 1,
        max: 24,
        pattern: _name,
        complaint: 'A layer id is 1 to 24 lowercase letters, digits, dashes or underscores.',
      );
      if (!ids.add(id)) {
        throw FormatException('The pack repeats the layer $id.');
      }
      final z = packInteger(map['z'], 'A layer depth', min: 0, max: PackLimits.maxLayers - 1);
      if (!depths.add(z)) {
        throw const FormatException('Two layers share a depth.');
      }
      layers.add(PackLayer(id: id, z: z, pose: PackLayerPose.read(map)));
    }
    return List.unmodifiable(layers);
  }

  static List<PackClip> _clips(Object? value) {
    if (value is! List<Object?> || value.isEmpty || value.length > PackLimits.maxClips) {
      throw const FormatException('A pack declares 1 to ${PackLimits.maxClips} clips.');
    }
    final clips = <PackClip>[];
    for (final item in value) {
      final map = packObject(
        item,
        'A clip',
        required: const {'id', 'fps', 'loop', 'frames'},
        optional: const {'durationMs', 'tracks', 'events', 'state'},
      );
      final id = packText(
        map['id'],
        'A clip id',
        min: 1,
        max: 24,
        pattern: _name,
        complaint: 'A clip id is 1 to 24 lowercase letters, digits, dashes or underscores.',
      );
      final fps = packInteger(map['fps'], 'A clip frame rate', min: 1, max: 30);
      final loop = packFlag(map['loop'], 'A clip loop flag');
      final framesValue = map['frames'];
      if (framesValue is! List<Object?> ||
          framesValue.isEmpty ||
          framesValue.length > PackLimits.maxFrames) {
        throw const FormatException('A clip holds 1 to ${PackLimits.maxFrames} frames.');
      }
      final frames = <PackFrame>[];
      for (final frameValue in framesValue) {
        final frame = packObject(
          frameValue,
          'A frame',
          required: const {'layer', 'asset', 'rect'},
        );
        final layer = packText(
          frame['layer'],
          'A frame layer',
          max: 24,
          pattern: _name,
          complaint: 'A frame layer id is not valid.',
        );
        final assetPath = packText(frame['asset'], 'A frame asset', min: 5, max: 120);
        validateAssetPath(assetPath);
        final rectValue = packObject(
          frame['rect'],
          'A frame region',
          required: const {'x', 'y', 'w', 'h'},
        );
        final rect = PackRect(
          x: packInteger(rectValue['x'], 'A frame x', min: 0, max: PackLimits.maxImage - 1),
          y: packInteger(rectValue['y'], 'A frame y', min: 0, max: PackLimits.maxImage - 1),
          width: packInteger(rectValue['w'], 'A frame width', min: 1, max: PackLimits.maxImage),
          height: packInteger(rectValue['h'], 'A frame height', min: 1, max: PackLimits.maxImage),
        );
        frames.add(PackFrame(layer: layer, asset: assetPath, rect: rect));
      }
      final minimumDuration = PackClip._frameSpan(frames, fps);
      final duration = map.containsKey('durationMs')
          ? packInteger(map['durationMs'], 'A clip duration', min: minimumDuration, max: 120000)
          : null;
      final timeline = duration ?? minimumDuration;
      clips.add(PackClip(
        id: id,
        fps: fps,
        loop: loop,
        frames: List.unmodifiable(frames),
        durationMs: duration,
        tracks: map.containsKey('tracks') ? PackMotionTrack.readList(map['tracks'], timeline) : const [],
        events: map.containsKey('events') ? PackMotionMarker.readList(map['events'], timeline) : const [],
        state: map.containsKey('state') ? PackStatePolicy.read(map['state']) : null,
      ));
    }
    return List.unmodifiable(clips);
  }

  static String? _homepage(Object? value) {
    final text = packText(value, 'The homepage', min: 9, max: 200);
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('The homepage must be an https address.');
    }
    return text;
  }

  static String? _minimumAppVersion(Object? value) {
    if (value == null) return null;
    final map = packObject(value, 'The application requirement', required: const {'minVersion'});
    return packText(
      map['minVersion'],
      'The minimum application version',
      min: 5,
      max: 18,
      pattern: _version,
      complaint: 'The minimum application version uses MAJOR.MINOR.PATCH.',
    );
  }
}
