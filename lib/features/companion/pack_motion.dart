import 'pack_json.dart';

class PackPoint {
  const PackPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, Object> toJson() => {'x': x, 'y': y};

  static PackPoint read(
    Object? json,
    String field, {
    double minimum = -2048,
    double maximum = 2048,
  }) {
    final map = packObject(json, field, required: const {'x', 'y'});
    return PackPoint(
      _number(map['x'], field, minimum, maximum),
      _number(map['y'], field, minimum, maximum),
    );
  }
}

class PackLayerPose {
  const PackLayerPose({
    this.parent,
    this.offset,
    this.pivot,
    this.rotationDegrees = 0,
    this.scale = const PackPoint(1, 1),
    this.opacity = 1,
    this.visible = true,
  });

  final String? parent;
  final PackPoint? offset;
  final PackPoint? pivot;
  final double rotationDegrees;
  final PackPoint scale;
  final double opacity;
  final bool visible;

  Map<String, Object> toJson() => {
    if (parent != null) 'parent': parent!,
    if (offset != null) 'offset': offset!.toJson(),
    if (pivot != null) 'pivot': pivot!.toJson(),
    if (rotationDegrees != 0) 'rotationDegrees': rotationDegrees,
    if (scale.x != 1 || scale.y != 1) 'scale': scale.toJson(),
    if (opacity != 1) 'opacity': opacity,
    if (!visible) 'visible': visible,
  };

  static PackLayerPose read(Map<String, Object?> data) => PackLayerPose(
    parent: data.containsKey('parent') ? _identifier(data['parent'], 'Parent layer') : null,
    offset: data.containsKey('offset') ? PackPoint.read(data['offset'], 'Layer offset') : null,
    pivot: data.containsKey('pivot') ? PackPoint.read(data['pivot'], 'Layer pivot') : null,
    rotationDegrees: data.containsKey('rotationDegrees')
        ? _number(data['rotationDegrees'], 'Layer rotation', -3600, 3600)
        : 0,
    scale: data.containsKey('scale')
        ? PackPoint.read(data['scale'], 'Layer scale', minimum: 0.05, maximum: 8)
        : const PackPoint(1, 1),
    opacity: data.containsKey('opacity') ? _number(data['opacity'], 'Layer opacity', 0, 1) : 1,
    visible: data.containsKey('visible') ? packFlag(data['visible'], 'Layer visibility') : true,
  );
}

enum PackMotionProperty {
  offsetX(-2048, 2048),
  offsetY(-2048, 2048),
  rotationDegrees(-3600, 3600),
  scaleX(0.05, 8),
  scaleY(0.05, 8),
  opacity(0, 1);

  const PackMotionProperty(this.minimum, this.maximum);

  final double minimum;
  final double maximum;
}

enum PackMotionEasing { step, linear }

class PackMotionKeyframe {
  const PackMotionKeyframe(this.timeMs, this.value, this.easing);

  final int timeMs;
  final double value;
  final PackMotionEasing easing;

  Map<String, Object> toJson() => {
    'timeMs': timeMs,
    'value': value,
    'easing': easing.name,
  };
}

class PackMotionTrack {
  const PackMotionTrack(this.layer, this.property, this.keyframes);

  final String layer;
  final PackMotionProperty property;
  final List<PackMotionKeyframe> keyframes;

  Map<String, Object> toJson() => {
    'layer': layer,
    'property': property.name,
    'keyframes': [for (final frame in keyframes) frame.toJson()],
  };

  static List<PackMotionTrack> readList(Object? json, int durationMs) {
    if (json is! List<Object?> || json.length > 48) {
      throw const FormatException('A clip supports at most 48 transform tracks.');
    }
    final tracks = <PackMotionTrack>[];
    final seen = <(String, PackMotionProperty)>{};
    for (final item in json) {
      final map = packObject(item, 'Transform track', required: const {'layer', 'property', 'keyframes'});
      final layer = _identifier(map['layer'], 'Track layer');
      final property = _enumValue(PackMotionProperty.values, map['property'], 'Track property');
      if (!seen.add((layer, property))) {
        throw const FormatException('Two tracks animate the same layer property.');
      }
      final frames = map['keyframes'];
      if (frames is! List<Object?> || frames.isEmpty || frames.length > 120) {
        throw const FormatException('A track requires 1 to 120 keyframes.');
      }
      var last = -1;
      final keyframes = <PackMotionKeyframe>[];
      for (final item in frames) {
        final frame = packObject(
          item,
          'Keyframe',
          required: const {'timeMs', 'value'},
          optional: const {'easing'},
        );
        final time = packInteger(frame['timeMs'], 'Keyframe time', min: 0, max: durationMs);
        if (time <= last) throw const FormatException('Keyframe times must increase.');
        last = time;
        keyframes.add(PackMotionKeyframe(
          time,
          _number(frame['value'], 'Keyframe value', property.minimum, property.maximum),
          frame.containsKey('easing')
              ? _enumValue(PackMotionEasing.values, frame['easing'], 'Keyframe easing')
              : PackMotionEasing.linear,
        ));
      }
      tracks.add(PackMotionTrack(layer, property, List.unmodifiable(keyframes)));
    }
    return List.unmodifiable(tracks);
  }
}

class PackMotionMarker {
  const PackMotionMarker(this.id, this.timeMs);

  final String id;
  final int timeMs;

  Map<String, Object> toJson() => {'id': id, 'timeMs': timeMs};

  static List<PackMotionMarker> readList(Object? json, int durationMs) {
    if (json is! List<Object?> || json.length > 32) {
      throw const FormatException('A clip supports at most 32 event markers.');
    }
    final markers = <PackMotionMarker>[];
    var last = -1;
    final seen = <(String, int)>{};
    for (final item in json) {
      final map = packObject(item, 'Event marker', required: const {'id', 'timeMs'});
      final id = _identifier(map['id'], 'Event name');
      final time = packInteger(map['timeMs'], 'Event time', min: 0, max: durationMs);
      if (time < last || !seen.add((id, time))) {
        throw const FormatException('Event markers must be ordered without duplicates.');
      }
      last = time;
      markers.add(PackMotionMarker(id, time));
    }
    return List.unmodifiable(markers);
  }
}

class PackStatePolicy {
  const PackStatePolicy({
    this.priority = 0,
    this.interruptible = true,
    this.transitionMs = 90,
  });

  final int priority;
  final bool interruptible;
  final int transitionMs;

  Map<String, Object> toJson() => {
    'priority': priority,
    'interruptible': interruptible,
    'transitionMs': transitionMs,
  };

  static PackStatePolicy read(Object? json) {
    final map = packObject(
      json,
      'Animation state policy',
      required: const {},
      optional: const {'priority', 'interruptible', 'transitionMs'},
    );
    return PackStatePolicy(
      priority: map.containsKey('priority')
          ? packInteger(map['priority'], 'Animation priority', min: -10, max: 100)
          : 0,
      interruptible: map.containsKey('interruptible')
          ? packFlag(map['interruptible'], 'Animation interruptibility')
          : true,
      transitionMs: map.containsKey('transitionMs')
          ? packInteger(map['transitionMs'], 'Animation transition', min: 0, max: 1000)
          : 90,
    );
  }
}

final _id = RegExp(r'^[a-z0-9_-]{1,24}$');

String _identifier(Object? value, String field) =>
    packText(value, field, min: 1, max: 24, pattern: _id);

T _enumValue<T extends Enum>(List<T> values, Object? value, String field) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$field is not supported.');
}

double _number(Object? value, String field, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    throw FormatException('$field is out of range.');
  }
  return value.toDouble();
}
