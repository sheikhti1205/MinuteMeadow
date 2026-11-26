import 'rig_model.dart';

/// One semantic problem in a rig. The location names the asset, layer, clip or
/// keyframe that needs correction.
final class RigIssue {
  const RigIssue(this.location, this.message);

  final String location;
  final String message;

  @override
  String toString() => '$location: $message';
}

/// A structural JSON problem found before a rig could be built.
final class RigFormatException implements Exception {
  const RigFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'Invalid rig at $path: $message';
}

/// A rig that decoded but failed semantic validation.
final class RigValidationException implements Exception {
  RigValidationException(List<RigIssue> issues)
    : issues = List<RigIssue>.unmodifiable(issues);

  final List<RigIssue> issues;

  @override
  String toString() =>
      'Invalid rig:\n${issues.map((issue) => ' - $issue').join('\n')}';
}

abstract final class RigValidator {
  static const int maxAtlasDimension = 8192;

  static List<RigIssue> validate(CompanionRig rig) {
    final issues = <RigIssue>[];

    if (rig.schemaVersion != CompanionRig.currentSchemaVersion) {
      issues.add(RigIssue(
        'rig',
        'Unsupported schema version ${rig.schemaVersion}; '
        'expected ${CompanionRig.currentSchemaVersion}.',
      ));
    }
    if (rig.canvasWidth <= 0 || rig.canvasHeight <= 0) {
      issues.add(const RigIssue('canvas', 'Width and height must be positive.'));
    } else if (rig.canvasWidth > maxAtlasDimension ||
        rig.canvasHeight > maxAtlasDimension) {
      issues.add(RigIssue(
        'canvas',
        'Canvas exceeds $maxAtlasDimension pixels.',
      ));
    }

    if (rig.atlases.isEmpty) {
      issues.add(const RigIssue('atlases', 'At least one atlas is required.'));
    }
    for (final atlas in rig.atlases.values) {
      final where = 'atlas "${atlas.id}"';
      if (atlas.id.isEmpty) {
        issues.add(const RigIssue('atlas', 'Atlas id must not be empty.'));
      }
      if (atlas.width <= 0 || atlas.height <= 0) {
        issues.add(RigIssue(where, 'Width and height must be positive.'));
      } else if (atlas.width > maxAtlasDimension ||
          atlas.height > maxAtlasDimension) {
        issues.add(RigIssue(where, 'Atlas exceeds $maxAtlasDimension pixels.'));
      }
    }

    final layerIds = <String>{};
    if (rig.layers.isEmpty) {
      issues.add(const RigIssue('layers', 'At least one layer is required.'));
    }
    for (final layer in rig.layers) {
      final where = 'layer "${layer.id}"';
      if (layer.id.isEmpty) {
        issues.add(RigIssue(
          'layer at index ${rig.layers.indexOf(layer)}',
          'Layer id must not be empty.',
        ));
      } else if (!layerIds.add(layer.id)) {
        issues.add(RigIssue(where, 'Duplicate layer id.'));
      }
      if (!layer.opacity.isFinite || layer.opacity < 0 || layer.opacity > 1) {
        issues.add(RigIssue(where, 'Opacity must be between 0 and 1.'));
      }
      if (!layer.rotationDegrees.isFinite) {
        issues.add(RigIssue(where, 'Rotation must be finite.'));
      }
      if (!layer.offset.dx.isFinite || !layer.offset.dy.isFinite) {
        issues.add(RigIssue(where, 'Offset must be finite.'));
      }
      if (!layer.pivot.dx.isFinite || !layer.pivot.dy.isFinite) {
        issues.add(RigIssue(where, 'Pivot must be finite.'));
      }
      if (!layer.scale.dx.isFinite ||
          !layer.scale.dy.isFinite ||
          layer.scale.dx <= 0 ||
          layer.scale.dy <= 0) {
        issues.add(RigIssue(where, 'Scale must be finite and positive.'));
      }
      _checkRegion(issues, rig, layer.defaultFrame, where, 'default frame');
    }

    final parents = <String, String>{};
    for (final layer in rig.layers) {
      final parent = layer.parent;
      if (parent == null) continue;
      final where = 'layer "${layer.id}"';
      if (parent == layer.id) {
        issues.add(RigIssue(where, 'A layer cannot parent itself.'));
      } else if (!layerIds.contains(parent)) {
        issues.add(RigIssue(where, 'Unknown parent "$parent".'));
      } else {
        parents[layer.id] = parent;
      }
    }
    _checkCycles(issues, parents, rig);

    for (final clip in rig.clips.values) {
      final clipWhere = 'clip "${clip.id}"';
      if (clip.id.isEmpty) {
        issues.add(const RigIssue('clip', 'Clip id must not be empty.'));
      }
      if (clip.durationMs <= 0) {
        issues.add(RigIssue(clipWhere, 'Duration must be positive.'));
      }
      final clipLayers = <String>{};
      for (final layerClip in clip.layers) {
        final where = '$clipWhere, layer "${layerClip.layerId}"';
        if (!layerIds.contains(layerClip.layerId)) {
          issues.add(RigIssue(where, 'Unknown layer.'));
        }
        if (!clipLayers.add(layerClip.layerId)) {
          issues.add(RigIssue(where, 'Duplicate layer entry in clip.'));
        }
        final frames = layerClip.frames;
        if (frames != null) {
          if (frames.frames.isEmpty) {
            issues.add(RigIssue(where, 'Frame track has no frames.'));
          }
          if (frames.frameDurationMs <= 0) {
            issues.add(RigIssue(
              where,
              'Frame duration must be positive.',
            ));
          }
          for (var index = 0; index < frames.frames.length; index++) {
            _checkRegion(
              issues,
              rig,
              frames.frames[index],
              where,
              'frame $index',
            );
          }
        }
        final properties = <LayerProperty>{};
        for (final track in layerClip.tracks) {
          final trackWhere = '$where, ${track.property.name}';
          if (!properties.add(track.property)) {
            issues.add(RigIssue(trackWhere, 'Duplicate property track.'));
          }
          final keyframes = track.keyframes;
          if (keyframes.isEmpty) {
            issues.add(RigIssue(trackWhere, 'Track has no keyframes.'));
          }
          var previousTime = -1;
          for (var index = 0; index < keyframes.length; index++) {
            final keyframe = keyframes[index];
            final keyWhere = '$trackWhere, keyframe $index';
            if (!keyframe.value.isFinite) {
              issues.add(RigIssue(keyWhere, 'Value must be finite.'));
            }
            if (keyframe.timeMs < 0 || keyframe.timeMs > clip.durationMs) {
              issues.add(RigIssue(
                keyWhere,
                'Time ${keyframe.timeMs}ms is outside the clip.',
              ));
            }
            if (keyframe.timeMs <= previousTime) {
              issues.add(RigIssue(keyWhere, 'Keyframe times must increase.'));
            }
            previousTime = keyframe.timeMs;
            switch (track.property) {
              case LayerProperty.opacity:
                if (keyframe.value < 0 || keyframe.value > 1) {
                  issues.add(RigIssue(
                    keyWhere,
                    'Opacity must be between 0 and 1.',
                  ));
                }
              case LayerProperty.scaleX:
              case LayerProperty.scaleY:
                if (keyframe.value <= 0) {
                  issues.add(RigIssue(keyWhere, 'Scale must be positive.'));
                }
              case LayerProperty.offsetX:
              case LayerProperty.offsetY:
              case LayerProperty.rotationDegrees:
                break;
            }
          }
        }
      }
    }

    final defaultClip = rig.defaultClip;
    if (defaultClip != null && !rig.clips.containsKey(defaultClip)) {
      issues.add(RigIssue(
        'defaultClip',
        'Unknown clip "$defaultClip".',
      ));
    }

    return List<RigIssue>.unmodifiable(issues);
  }

  static void _checkRegion(
    List<RigIssue> issues,
    CompanionRig rig,
    SpriteRegion region,
    String where,
    String label,
  ) {
    final atlas = rig.atlases[region.atlas];
    if (atlas == null) {
      issues.add(RigIssue(
        where,
        '$label uses unknown atlas "${region.atlas}".',
      ));
      return;
    }
    if (!region.fitsWithin(atlas.width, atlas.height)) {
      issues.add(RigIssue(
        where,
        '$label does not fit atlas "${atlas.id}" '
        '(${atlas.width}x${atlas.height}).',
      ));
    }
  }

  static void _checkCycles(
    List<RigIssue> issues,
    Map<String, String> parents,
    CompanionRig rig,
  ) {
    final state = <String, int>{};

    void visit(String id) {
      final status = state[id] ?? 0;
      if (status == 2) return;
      if (status == 1) {
        issues.add(RigIssue('layer "$id"', 'Parent cycle detected.'));
        return;
      }
      state[id] = 1;
      final parent = parents[id];
      if (parent != null) visit(parent);
      state[id] = 2;
    }

    for (final layer in rig.layers) {
      visit(layer.id);
    }
  }
}
