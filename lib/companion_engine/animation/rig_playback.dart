import '../rig/rig_model.dart';

/// A sampled animation override for one layer. Null fields keep the layer rest
/// value. Tracks are absolute overrides, so a clip replaces the values it
/// declares without disturbing properties it does not declare.
final class LayerAnimation {
  const LayerAnimation({
    this.offsetX,
    this.offsetY,
    this.rotationDegrees,
    this.scaleX,
    this.scaleY,
    this.opacity,
    this.frame,
  });

  final double? offsetX;
  final double? offsetY;
  final double? rotationDegrees;
  final double? scaleX;
  final double? scaleY;
  final double? opacity;
  final SpriteRegion? frame;
}

final class ClipInstance {
  ClipInstance({required this.clip, this.timeMs = 0});

  final ClipDefinition clip;
  double timeMs;
  bool _reportedCompletion = false;

  bool get isComplete => !clip.loop && timeMs >= clip.durationMs;
}

final class RigPlaybackEvent {
  const RigPlaybackEvent({
    required this.clipId,
    required this.looped,
    required this.completed,
  });

  final String clipId;
  final bool looped;
  final bool completed;
}

/// Runs independent clip instances. The default clip provides the base state;
/// overlay clips are applied in activation order, so later clips win the
/// properties they declare. A one-shot overlay is removed after it completes,
/// revealing the default state again.
final class RigPlayback {
  RigPlayback({
    required this.rig,
    String? defaultClip,
    double speed = 1,
  }) : _speed = _checkedSpeed(speed) {
    final id = defaultClip ?? rig.defaultClip;
    if (id == null) return;
    final clip = rig.clipById(id);
    if (clip == null) {
      throw ArgumentError.value(id, 'defaultClip', 'Unknown clip id.');
    }
    _base = ClipInstance(clip: clip);
  }

  final CompanionRig rig;
  ClipInstance? _base;
  final List<ClipInstance> _overlays = <ClipInstance>[];
  double _speed;

  /// Multiplier applied to elapsed time. Scrubbing is unaffected.
  double get speed => _speed;

  set speed(double value) => _speed = _checkedSpeed(value);

  static double _checkedSpeed(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'speed',
        'Playback speed must be finite and positive.',
      );
    }
    return value;
  }

  ClipInstance? get base => _base;

  ClipInstance? instanceFor(String clipId) {
    final base = _base;
    if (base != null && base.clip.id == clipId) return base;
    for (final overlay in _overlays) {
      if (overlay.clip.id == clipId) return overlay;
    }
    return null;
  }

  bool isPlaying(String clipId) => instanceFor(clipId) != null;

  double? timeOf(String clipId) => instanceFor(clipId)?.timeMs;

  ClipInstance play(String clipId, {bool restart = true}) {
    final clip = rig.clipById(clipId);
    if (clip == null) {
      throw ArgumentError.value(clipId, 'clipId', 'Unknown clip id.');
    }
    final existing = instanceFor(clipId);
    if (existing != null) {
      if (restart) {
        existing.timeMs = 0;
        existing._reportedCompletion = false;
      }
      return existing;
    }
    final instance = ClipInstance(clip: clip);
    _overlays.add(instance);
    return instance;
  }

  bool stop(String clipId) {
    final before = _overlays.length;
    _overlays.removeWhere((instance) => instance.clip.id == clipId);
    return _overlays.length != before;
  }

  /// Scrubs every active instance to [timeMs].
  void seek(double timeMs) {
    final base = _base;
    if (base != null) {
      base.timeMs = _clampTime(base.clip, timeMs);
      base._reportedCompletion = base.isComplete;
    }
    for (final overlay in _overlays) {
      overlay.timeMs = _clampTime(overlay.clip, timeMs);
      overlay._reportedCompletion = overlay.isComplete;
    }
  }

  List<RigPlaybackEvent> advance(double deltaMs) {
    final events = <RigPlaybackEvent>[];
    final scaledDelta = deltaMs * _speed;
    if (scaledDelta <= 0 || !scaledDelta.isFinite) return events;

    final base = _base;
    if (base != null) _advanceInstance(base, scaledDelta, events);
    for (final overlay in List<ClipInstance>.of(_overlays)) {
      _advanceInstance(overlay, scaledDelta, events);
    }
    _overlays.removeWhere((instance) => instance.isComplete);
    return events;
  }

  /// Samples all active instances at their independent times.
  Map<String, LayerAnimation> sample() {
    final builders = <String, _LayerAnimationBuilder>{};

    void apply(ClipInstance instance) {
      final time = instance.timeMs;
      for (final layerClip in instance.clip.layers) {
        final builder = builders.putIfAbsent(
          layerClip.layerId,
          _LayerAnimationBuilder.new,
        );
        if (layerClip.frames case final frames?) {
          builder.frame = frames.regionAt(time);
        }
        for (final track in layerClip.tracks) {
          final value = track.valueAt(time);
          switch (track.property) {
            case LayerProperty.offsetX:
              builder.offsetX = value;
            case LayerProperty.offsetY:
              builder.offsetY = value;
            case LayerProperty.rotationDegrees:
              builder.rotationDegrees = value;
            case LayerProperty.scaleX:
              builder.scaleX = value;
            case LayerProperty.scaleY:
              builder.scaleY = value;
            case LayerProperty.opacity:
              builder.opacity = value;
          }
        }
      }
    }

    final base = _base;
    if (base != null) apply(base);
    for (final overlay in _overlays) {
      apply(overlay);
    }
    return <String, LayerAnimation>{
      for (final entry in builders.entries) entry.key: entry.value.build(),
    };
  }

  static void _advanceInstance(
    ClipInstance instance,
    double deltaMs,
    List<RigPlaybackEvent> events,
  ) {
    if (instance.isComplete) return;
    final duration = instance.clip.durationMs.toDouble();
    instance.timeMs += deltaMs;
    if (instance.clip.loop) {
      if (instance.timeMs >= duration) {
        instance.timeMs %= duration;
        events.add(RigPlaybackEvent(
          clipId: instance.clip.id,
          looped: true,
          completed: false,
        ));
      }
      return;
    }
    if (instance.timeMs >= duration) {
      instance.timeMs = duration;
      if (!instance._reportedCompletion) {
        instance._reportedCompletion = true;
        events.add(RigPlaybackEvent(
          clipId: instance.clip.id,
          looped: false,
          completed: true,
        ));
      }
    }
  }

  static double _clampTime(ClipDefinition clip, double timeMs) {
    final duration = clip.durationMs.toDouble();
    if (timeMs <= 0) return 0;
    if (clip.loop) return timeMs % duration;
    return timeMs >= duration ? duration : timeMs;
  }
}

final class _LayerAnimationBuilder {
  double? offsetX;
  double? offsetY;
  double? rotationDegrees;
  double? scaleX;
  double? scaleY;
  double? opacity;
  SpriteRegion? frame;

  LayerAnimation build() => LayerAnimation(
    offsetX: offsetX,
    offsetY: offsetY,
    rotationDegrees: rotationDegrees,
    scaleX: scaleX,
    scaleY: scaleY,
    opacity: opacity,
    frame: frame,
  );
}
