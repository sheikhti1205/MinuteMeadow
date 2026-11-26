import 'dart:ui';

import '../rig/rig_model.dart';

/// A touch region owned by the scene, in scene pixel space.
final class SpriteHitbox {
  const SpriteHitbox({
    required this.id,
    required this.label,
    required this.rect,
  });

  final String id;
  final String label;
  final Rect rect;
}

/// Computed debug information for one layer at a sampled pose.
final class LayerPoseInfo {
  const LayerPoseInfo({
    required this.id,
    required this.visible,
    required this.opacity,
    required this.pivot,
    required this.bounds,
    required this.frame,
  });

  final String id;
  final bool visible;
  final double opacity;
  final Offset pivot;
  final Rect bounds;
  final SpriteRegion frame;
}
