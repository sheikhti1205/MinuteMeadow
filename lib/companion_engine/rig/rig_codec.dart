import 'dart:convert';
import 'dart:ui';

import 'rig_model.dart';
import 'rig_validator.dart';

/// Versioned JSON codec for companion rigs. Decoding is strict: unknown fields
/// and unsupported schema versions are rejected, and every decoded rig is
/// validated before it is returned.
abstract final class RigCodec {
  static const _topLevelFields = <String>{
    'schemaVersion',
    'canvas',
    'atlases',
    'layers',
    'clips',
    'defaultClip',
  };

  static String encode(CompanionRig rig) =>
      const JsonEncoder.withIndent('  ').convert(toJson(rig));

  static CompanionRig decode(String source) {
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (error) {
      throw RigFormatException(r'$', 'Invalid JSON: ${error.message}');
    }
    return decodeJson(json);
  }

  static CompanionRig decodeJson(Object? json) {
    final root = _object(json, r'$');
    _checkFields(root, _topLevelFields, r'$');

    final schemaVersion = _int(root['schemaVersion'], r'$.schemaVersion');
    if (schemaVersion != CompanionRig.currentSchemaVersion) {
      throw RigFormatException(
        r'$.schemaVersion',
        'Unsupported schema version $schemaVersion.',
      );
    }

    final canvas = _object(root['canvas'], r'$.canvas');
    _checkFields(canvas, const <String>{'width', 'height'}, r'$.canvas');
    final canvasWidth = _int(canvas['width'], r'$.canvas.width');
    final canvasHeight = _int(canvas['height'], r'$.canvas.height');

    final atlasList = _list(root['atlases'], r'$.atlases');
    final atlases = <String, AtlasDefinition>{};
    for (var index = 0; index < atlasList.length; index++) {
      final path = '\$.atlases[$index]';
      final map = _object(atlasList[index], path);
      _checkFields(
        map,
        const <String>{'id', 'width', 'height', 'imageKey'},
        path,
      );
      final id = _string(map['id'], '$path.id');
      if (atlases.containsKey(id)) {
        throw RigFormatException('$path.id', 'Duplicate atlas id "$id".');
      }
      final imageKey = map['imageKey'];
      atlases[id] = AtlasDefinition(
        id: id,
        width: _int(map['width'], '$path.width'),
        height: _int(map['height'], '$path.height'),
        imageKey: imageKey == null ? null : _string(imageKey, '$path.imageKey'),
      );
    }

    final layerList = _list(root['layers'], r'$.layers');
    final layers = <LayerDefinition>[];
    for (var index = 0; index < layerList.length; index++) {
      layers.add(_layer(layerList[index], '\$.layers[$index]'));
    }

    final clipList = _list(root['clips'], r'$.clips');
    final clips = <String, ClipDefinition>{};
    for (var index = 0; index < clipList.length; index++) {
      final clip = _clip(clipList[index], '\$.clips[$index]');
      if (clips.containsKey(clip.id)) {
        throw RigFormatException(
          '\$.clips[$index].id',
          'Duplicate clip id "${clip.id}".',
        );
      }
      clips[clip.id] = clip;
    }

    final defaultClip = root['defaultClip'];
    final rig = CompanionRig(
      schemaVersion: schemaVersion,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      atlases: atlases,
      layers: layers,
      clips: clips,
      defaultClip: defaultClip == null
          ? null
          : _string(defaultClip, r'$.defaultClip'),
    );

    final issues = RigValidator.validate(rig);
    if (issues.isNotEmpty) throw RigValidationException(issues);
    return rig;
  }

  static Map<String, Object?> toJson(CompanionRig rig) => <String, Object?>{
    'schemaVersion': rig.schemaVersion,
    'canvas': <String, Object?>{
      'width': rig.canvasWidth,
      'height': rig.canvasHeight,
    },
    'atlases': <Object?>[
      for (final atlas in rig.atlases.values)
        <String, Object?>{
          'id': atlas.id,
          'width': atlas.width,
          'height': atlas.height,
          if (atlas.imageKey != null) 'imageKey': atlas.imageKey,
        },
    ],
    'layers': <Object?>[
      for (final layer in rig.layers) _layerJson(layer),
    ],
    'clips': <Object?>[
      for (final clip in rig.clips.values) _clipJson(clip),
    ],
    if (rig.defaultClip != null) 'defaultClip': rig.defaultClip,
  };

  static Map<String, Object?> _layerJson(LayerDefinition layer) =>
      <String, Object?>{
        'id': layer.id,
        if (layer.parent != null) 'parent': layer.parent,
        'frame': _regionJson(layer.defaultFrame),
        'offset': _pointJson(layer.offset),
        'pivot': _pointJson(layer.pivot),
        'rotationDegrees': layer.rotationDegrees,
        'scale': _pointJson(layer.scale),
        'opacity': layer.opacity,
        'visible': layer.visible,
      };

  static Map<String, Object?> _clipJson(ClipDefinition clip) =>
      <String, Object?>{
        'id': clip.id,
        'durationMs': clip.durationMs,
        'loop': clip.loop,
        'layers': <Object?>[
          for (final layerClip in clip.layers) _layerClipJson(layerClip),
        ],
      };

  static Map<String, Object?> _layerClipJson(LayerClip layerClip) {
    final frames = layerClip.frames;
    return <String, Object?>{
      'layer': layerClip.layerId,
      if (frames != null)
        'frames': <String, Object?>{
          'frames': <Object?>[
            for (final region in frames.frames) _regionJson(region),
          ],
          'frameDurationMs': frames.frameDurationMs,
          'loop': frames.loop,
        },
      'tracks': <Object?>[
        for (final track in layerClip.tracks)
          <String, Object?>{
            'property': track.property.name,
            'keyframes': <Object?>[
              for (final keyframe in track.keyframes)
                <String, Object?>{
                  'timeMs': keyframe.timeMs,
                  'value': keyframe.value,
                  'easing': keyframe.easing.name,
                },
            ],
          },
      ],
    };
  }

  static Map<String, Object?> _regionJson(SpriteRegion region) =>
      <String, Object?>{
        'atlas': region.atlas,
        'x': region.x,
        'y': region.y,
        'width': region.width,
        'height': region.height,
      };

  static Map<String, Object?> _pointJson(Offset point) =>
      <String, Object?>{'x': point.dx, 'y': point.dy};

  static LayerDefinition _layer(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{
        'id',
        'parent',
        'frame',
        'offset',
        'pivot',
        'rotationDegrees',
        'scale',
        'opacity',
        'visible',
      },
      path,
    );
    final parent = map['parent'];
    return LayerDefinition(
      id: _string(map['id'], '$path.id'),
      parent: parent == null ? null : _string(parent, '$path.parent'),
      defaultFrame: _region(map['frame'], '$path.frame'),
      offset: map['offset'] == null
          ? Offset.zero
          : _point(map['offset'], '$path.offset'),
      pivot: map['pivot'] == null
          ? Offset.zero
          : _point(map['pivot'], '$path.pivot'),
      rotationDegrees: map['rotationDegrees'] == null
          ? 0
          : _double(map['rotationDegrees'], '$path.rotationDegrees'),
      scale: map['scale'] == null
          ? const Offset(1, 1)
          : _point(map['scale'], '$path.scale'),
      opacity: map['opacity'] == null
          ? 1
          : _double(map['opacity'], '$path.opacity'),
      visible: map['visible'] == null
          ? true
          : _bool(map['visible'], '$path.visible'),
    );
  }

  static ClipDefinition _clip(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{'id', 'durationMs', 'loop', 'layers'},
      path,
    );
    final layerList = map['layers'] == null
        ? const <Object?>[]
        : _list(map['layers'], '$path.layers');
    return ClipDefinition(
      id: _string(map['id'], '$path.id'),
      durationMs: _int(map['durationMs'], '$path.durationMs'),
      loop: map['loop'] == null ? true : _bool(map['loop'], '$path.loop'),
      layers: <LayerClip>[
        for (var index = 0; index < layerList.length; index++)
          _layerClip(layerList[index], '$path.layers[$index]'),
      ],
    );
  }

  static LayerClip _layerClip(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{'layer', 'frames', 'tracks'},
      path,
    );
    final framesValue = map['frames'];
    final trackList = map['tracks'] == null
        ? const <Object?>[]
        : _list(map['tracks'], '$path.tracks');
    return LayerClip(
      layerId: _string(map['layer'], '$path.layer'),
      frames: framesValue == null ? null : _frames(framesValue, '$path.frames'),
      tracks: <PropertyTrack>[
        for (var index = 0; index < trackList.length; index++)
          _track(trackList[index], '$path.tracks[$index]'),
      ],
    );
  }

  static FrameTrack _frames(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{'frames', 'frameDurationMs', 'loop'},
      path,
    );
    final regions = _list(map['frames'], '$path.frames');
    return FrameTrack(
      frames: <SpriteRegion>[
        for (var index = 0; index < regions.length; index++)
          _region(regions[index], '$path.frames[$index]'),
      ],
      frameDurationMs: _int(map['frameDurationMs'], '$path.frameDurationMs'),
      loop: map['loop'] == null ? true : _bool(map['loop'], '$path.loop'),
    );
  }

  static PropertyTrack _track(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(map, const <String>{'property', 'keyframes'}, path);
    final keyframeList = _list(map['keyframes'], '$path.keyframes');
    return PropertyTrack(
      property: _property(
        _string(map['property'], '$path.property'),
        '$path.property',
      ),
      keyframes: <Keyframe>[
        for (var index = 0; index < keyframeList.length; index++)
          _keyframe(keyframeList[index], '$path.keyframes[$index]'),
      ],
    );
  }

  static Keyframe _keyframe(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{'timeMs', 'value', 'easing'},
      path,
    );
    final easing = map['easing'];
    return Keyframe(
      timeMs: _int(map['timeMs'], '$path.timeMs'),
      value: _double(map['value'], '$path.value'),
      easing: easing == null
          ? KeyframeEasing.linear
          : _easing(_string(easing, '$path.easing'), '$path.easing'),
    );
  }

  static SpriteRegion _region(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(
      map,
      const <String>{'atlas', 'x', 'y', 'width', 'height'},
      path,
    );
    return SpriteRegion(
      atlas: _string(map['atlas'], '$path.atlas'),
      x: _int(map['x'], '$path.x'),
      y: _int(map['y'], '$path.y'),
      width: _int(map['width'], '$path.width'),
      height: _int(map['height'], '$path.height'),
    );
  }

  static Offset _point(Object? value, String path) {
    final map = _object(value, path);
    _checkFields(map, const <String>{'x', 'y'}, path);
    return Offset(
      _double(map['x'], '$path.x'),
      _double(map['y'], '$path.y'),
    );
  }

  static LayerProperty _property(String value, String path) => switch (value) {
    'offsetX' => LayerProperty.offsetX,
    'offsetY' => LayerProperty.offsetY,
    'rotationDegrees' => LayerProperty.rotationDegrees,
    'scaleX' => LayerProperty.scaleX,
    'scaleY' => LayerProperty.scaleY,
    'opacity' => LayerProperty.opacity,
    _ => throw RigFormatException(path, 'Unknown property "$value".'),
  };

  static KeyframeEasing _easing(String value, String path) => switch (value) {
    'step' => KeyframeEasing.step,
    'linear' => KeyframeEasing.linear,
    _ => throw RigFormatException(path, 'Unknown easing "$value".'),
  };

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is Map<String, Object?>) return value;
    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw RigFormatException(path, 'Object keys must be strings.');
        }
        result[key] = entry.value;
      }
      return result;
    }
    throw RigFormatException(path, 'Expected an object.');
  }

  static List<Object?> _list(Object? value, String path) {
    if (value is List<Object?>) return value;
    throw RigFormatException(path, 'Expected a list.');
  }

  static String _string(Object? value, String path) {
    if (value is String) return value;
    throw RigFormatException(path, 'Expected a string.');
  }

  static int _int(Object? value, String path) {
    if (value is int) return value;
    throw RigFormatException(path, 'Expected an integer.');
  }

  static double _double(Object? value, String path) {
    if (value is num) return value.toDouble();
    throw RigFormatException(path, 'Expected a number.');
  }

  static bool _bool(Object? value, String path) {
    if (value is bool) return value;
    throw RigFormatException(path, 'Expected a boolean.');
  }

  static void _checkFields(
    Map<String, Object?> map,
    Set<String> allowed,
    String path,
  ) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw RigFormatException(path, 'Unknown field "$key".');
      }
    }
  }
}
