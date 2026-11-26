import 'dart:math' as math;
import 'dart:ui';

/// A rectangle in atlas pixel space.
final class SpriteRegion {
  const SpriteRegion({
    required this.atlas,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String atlas;
  final int x;
  final int y;
  final int width;
  final int height;

  Rect get sourceRect => Rect.fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  Size get size => Size(width.toDouble(), height.toDouble());

  bool fitsWithin(int atlasWidth, int atlasHeight) =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= atlasWidth &&
      y + height <= atlasHeight;

  @override
  String toString() => 'SpriteRegion($atlas, $x, $y, $width x $height)';
}

/// An atlas image and the loader key that resolves it.
final class AtlasDefinition {
  const AtlasDefinition({
    required this.id,
    required this.width,
    required this.height,
    this.imageKey,
  });

  final String id;
  final int width;
  final int height;

  /// Opaque key for an image loader. The engine never resolves paths itself.
  final String? imageKey;
}

/// A transform property that a clip track can drive.
enum LayerProperty {
  offsetX,
  offsetY,
  rotationDegrees,
  scaleX,
  scaleY,
  opacity,
}

enum KeyframeEasing { step, linear }

final class Keyframe {
  const Keyframe({
    required this.timeMs,
    required this.value,
    this.easing = KeyframeEasing.linear,
  });

  final int timeMs;
  final double value;

  /// Easing of the segment that starts at this keyframe.
  final KeyframeEasing easing;
}

/// A timeline of values for one layer property. Values are absolute overrides:
/// a track replaces the layer rest value for as long as the clip is active.
final class PropertyTrack {
  PropertyTrack({
    required this.property,
    required List<Keyframe> keyframes,
  }) : keyframes = List<Keyframe>.unmodifiable(keyframes);

  final LayerProperty property;
  final List<Keyframe> keyframes;

  double valueAt(double timeMs) {
    final frames = keyframes;
    if (frames.isEmpty) {
      throw StateError('Track has no keyframes.');
    }
    if (timeMs <= frames.first.timeMs) return frames.first.value;
    for (var index = 1; index < frames.length; index++) {
      final next = frames[index];
      if (timeMs <= next.timeMs) {
        final previous = frames[index - 1];
        if (previous.easing == KeyframeEasing.step) return previous.value;
        final span = next.timeMs - previous.timeMs;
        final progress = span == 0 ? 1.0 : (timeMs - previous.timeMs) / span;
        return previous.value + (next.value - previous.value) * progress;
      }
    }
    return frames.last.value;
  }
}

/// An independent sequence of image frames for one layer.
final class FrameTrack {
  FrameTrack({
    required List<SpriteRegion> frames,
    required this.frameDurationMs,
    this.loop = true,
  }) : frames = List<SpriteRegion>.unmodifiable(frames);

  final List<SpriteRegion> frames;
  final int frameDurationMs;
  final bool loop;

  int indexAt(double timeMs) {
    if (frames.isEmpty) throw StateError('Frame track has no frames.');
    final raw = (timeMs / frameDurationMs).floor();
    final index = raw < 0 ? 0 : raw;
    if (loop) return index % frames.length;
    return math.min(index, frames.length - 1);
  }

  SpriteRegion regionAt(double timeMs) => frames[indexAt(timeMs)];
}

/// The animation data a clip contributes to one layer.
final class LayerClip {
  LayerClip({
    required this.layerId,
    this.frames,
    List<PropertyTrack> tracks = const <PropertyTrack>[],
  }) : tracks = List<PropertyTrack>.unmodifiable(tracks);

  final String layerId;
  final FrameTrack? frames;
  final List<PropertyTrack> tracks;
}

/// A named animation clip. A looping clip wraps; a one-shot clip completes.
final class ClipDefinition {
  ClipDefinition({
    required this.id,
    required this.durationMs,
    this.loop = true,
    List<LayerClip> layers = const <LayerClip>[],
  }) : layers = List<LayerClip>.unmodifiable(layers);

  final String id;
  final int durationMs;
  final bool loop;
  final List<LayerClip> layers;
}

final class LayerDefinition {
  const LayerDefinition({
    required this.id,
    required this.defaultFrame,
    this.parent,
    this.offset = Offset.zero,
    this.pivot = Offset.zero,
    this.rotationDegrees = 0,
    this.scale = const Offset(1, 1),
    this.opacity = 1,
    this.visible = true,
  });

  final String id;
  final String? parent;
  final SpriteRegion defaultFrame;

  /// Rest translation in the parent layer's local pixel space.
  final Offset offset;

  /// Rotation and scale origin in frame-local pixels.
  final Offset pivot;
  final double rotationDegrees;
  final Offset scale;
  final double opacity;
  final bool visible;
}

/// A declared, versioned companion rig. List order is draw order.
final class CompanionRig {
  CompanionRig({
    required this.canvasWidth,
    required this.canvasHeight,
    required Map<String, AtlasDefinition> atlases,
    required List<LayerDefinition> layers,
    required Map<String, ClipDefinition> clips,
    this.defaultClip,
    this.schemaVersion = currentSchemaVersion,
  }) : atlases = Map<String, AtlasDefinition>.unmodifiable(atlases),
       layers = List<LayerDefinition>.unmodifiable(layers),
       clips = Map<String, ClipDefinition>.unmodifiable(clips);

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int canvasWidth;
  final int canvasHeight;
  final Map<String, AtlasDefinition> atlases;
  final List<LayerDefinition> layers;
  final Map<String, ClipDefinition> clips;
  final String? defaultClip;

  Size get canvasSize => Size(canvasWidth.toDouble(), canvasHeight.toDouble());

  LayerDefinition? layerById(String id) {
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  ClipDefinition? clipById(String id) => clips[id];
}
