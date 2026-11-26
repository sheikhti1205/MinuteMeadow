import 'dart:math' as math;
import 'dart:ui';

import '../animation/rig_playback.dart';
import '../rig/rig_model.dart';
import 'affine2.dart';
import 'debug_geometry.dart';

final class CompanionQuad {
  const CompanionQuad({
    required this.layerId,
    required this.region,
    required this.transform,
    required this.opacity,
  });

  final String layerId;
  final SpriteRegion region;

  /// Maps frame-local pixels to scene pixels.
  final Affine2 transform;
  final double opacity;

  Size get frameSize => region.size;

  Rect get bounds => transform.transformRect(Offset.zero & frameSize);
}

final class CompanionPose {
  CompanionPose({
    required List<CompanionQuad> quads,
    required List<LayerPoseInfo> layers,
  }) : quads = List<CompanionQuad>.unmodifiable(quads),
       layers = List<LayerPoseInfo>.unmodifiable(layers);

  /// Draw order, back to front.
  final List<CompanionQuad> quads;

  /// Every layer, including hidden ones, for the inspection panel.
  final List<LayerPoseInfo> layers;
}

/// Composes ordered layer transforms into draw quads. Parenting affects the
/// transform; list order still decides overlap. Hidden ancestors hide their
/// descendants, and opacity multiplies down the tree.
CompanionPose buildCompanionPose(
  CompanionRig rig, {
  Map<String, LayerAnimation> animations = const <String, LayerAnimation>{},
  Set<String> hiddenLayers = const <String>{},
  Map<String, double> layerOpacity = const <String, double>{},
  Affine2 rootTransform = Affine2.identity,
}) {
  final byId = <String, LayerDefinition>{
    for (final layer in rig.layers) layer.id: layer,
  };
  final matrices = <String, Affine2>{};
  final visible = <String, bool>{};
  final opacities = <String, double>{};
  final frames = <String, SpriteRegion>{};

  void resolve(LayerDefinition layer, Set<String> resolving) {
    if (matrices.containsKey(layer.id)) return;
    if (!resolving.add(layer.id)) {
      matrices[layer.id] = rootTransform;
      return;
    }

    var parentMatrix = rootTransform;
    var parentVisible = true;
    var parentOpacity = 1.0;
    final parent = layer.parent == null ? null : byId[layer.parent];
    if (parent != null) {
      resolve(parent, resolving);
      parentMatrix = matrices[parent.id] ?? rootTransform;
      parentVisible = visible[parent.id] ?? true;
      parentOpacity = opacities[parent.id] ?? 1.0;
    }

    final animation = animations[layer.id];
    final offset = Offset(
      animation?.offsetX ?? layer.offset.dx,
      animation?.offsetY ?? layer.offset.dy,
    );
    final pivot = layer.pivot;
    final rotation =
        (animation?.rotationDegrees ?? layer.rotationDegrees) * math.pi / 180;
    final scale = Offset(
      animation?.scaleX ?? layer.scale.dx,
      animation?.scaleY ?? layer.scale.dy,
    );
    final local =
        Affine2.translation(offset.dx, offset.dy) *
        Affine2.translation(pivot.dx, pivot.dy) *
        Affine2.rotation(rotation) *
        Affine2.scale(scale.dx, scale.dy) *
        Affine2.translation(-pivot.dx, -pivot.dy);
    final matrix = parentMatrix * local;
    final ownOpacity =
        (animation?.opacity ?? layer.opacity) * (layerOpacity[layer.id] ?? 1);
    final opacity = (parentOpacity * ownOpacity).clamp(0.0, 1.0).toDouble();

    matrices[layer.id] = matrix;
    visible[layer.id] =
        parentVisible && layer.visible && !hiddenLayers.contains(layer.id);
    opacities[layer.id] = opacity;
    frames[layer.id] = animation?.frame ?? layer.defaultFrame;
    resolving.remove(layer.id);
  }

  for (final layer in rig.layers) {
    resolve(layer, <String>{});
  }

  final quads = <CompanionQuad>[];
  final infos = <LayerPoseInfo>[];
  for (final layer in rig.layers) {
    final matrix = matrices[layer.id] ?? rootTransform;
    final frame = frames[layer.id] ?? layer.defaultFrame;
    final opacity = opacities[layer.id] ?? 0;
    final isVisible = visible[layer.id] ?? false;
    infos.add(LayerPoseInfo(
      id: layer.id,
      visible: isVisible,
      opacity: opacity,
      pivot: matrix.transform(layer.pivot),
      bounds: matrix.transformRect(Offset.zero & frame.size),
      frame: frame,
    ));
    if (isVisible && opacity > 0) {
      quads.add(CompanionQuad(
        layerId: layer.id,
        region: frame,
        transform: matrix,
        opacity: opacity,
      ));
    }
  }

  return CompanionPose(quads: quads, layers: infos);
}
