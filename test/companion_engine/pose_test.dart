import 'dart:ui';

import 'package:companion_focus/companion_engine/animation/rig_playback.dart';
import 'package:companion_focus/companion_engine/render/affine2.dart';
import 'package:companion_focus/companion_engine/render/companion_pose.dart';
import 'package:companion_focus/companion_engine/rig/rig_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _atlas = AtlasDefinition(id: 'main', width: 100, height: 100);
const _parentFrame = SpriteRegion(
  atlas: 'main',
  x: 0,
  y: 0,
  width: 10,
  height: 10,
);
const _childFrame = SpriteRegion(
  atlas: 'main',
  x: 20,
  y: 0,
  width: 4,
  height: 4,
);
const _backFrame = SpriteRegion(
  atlas: 'main',
  x: 30,
  y: 0,
  width: 8,
  height: 8,
);

CompanionRig _rig({
  List<LayerDefinition>? layers,
  double parentOpacity = 0.5,
  double childOpacity = 0.5,
}) => CompanionRig(
  canvasWidth: 100,
  canvasHeight: 100,
  atlases: const <String, AtlasDefinition>{'main': _atlas},
  layers:
      layers ??
      <LayerDefinition>[
        const LayerDefinition(id: 'back', defaultFrame: _backFrame),
        LayerDefinition(
          id: 'parent',
          defaultFrame: _parentFrame,
          offset: const Offset(10, 10),
          pivot: const Offset(5, 5),
          opacity: parentOpacity,
        ),
        LayerDefinition(
          id: 'child',
          parent: 'parent',
          defaultFrame: _childFrame,
          offset: const Offset(5, 5),
          opacity: childOpacity,
        ),
      ],
  clips: <String, ClipDefinition>{
    'idle': ClipDefinition(id: 'idle', durationMs: 100),
  },
);

void main() {
  test('keeps list order as draw order independently of parenting', () {
    final pose = buildCompanionPose(_rig());
    expect(
      pose.quads.map((quad) => quad.layerId).toList(),
      <String>['back', 'parent', 'child'],
    );
    expect(pose.quads[1].bounds, const Rect.fromLTRB(10, 10, 20, 20));
    expect(pose.quads[2].bounds, const Rect.fromLTRB(15, 15, 19, 19));
  });

  test('applies parent transforms to child offsets and pivots', () {
    final pose = buildCompanionPose(_rig());
    final parent = pose.layers.firstWhere((layer) => layer.id == 'parent');
    final child = pose.layers.firstWhere((layer) => layer.id == 'child');
    expect(parent.pivot, const Offset(15, 15));
    expect(child.pivot, const Offset(15, 15));
  });

  test('rotates around the layer pivot', () {
    final rig = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'parent',
          defaultFrame: _parentFrame,
          offset: Offset(20, 20),
          pivot: Offset(0, 0),
          rotationDegrees: 90,
        ),
      ],
    );
    final pose = buildCompanionPose(rig);
    final bounds = pose.quads.single.bounds;
    expect(bounds.left, closeTo(10, 0.0001));
    expect(bounds.top, closeTo(20, 0.0001));
    expect(bounds.right, closeTo(20, 0.0001));
    expect(bounds.bottom, closeTo(30, 0.0001));
  });

  test('rotating around the center keeps the frame in place', () {
    final rig = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'parent',
          defaultFrame: _parentFrame,
          offset: Offset(20, 20),
          pivot: Offset(5, 5),
          rotationDegrees: 90,
        ),
      ],
    );
    final pose = buildCompanionPose(rig);
    final bounds = pose.quads.single.bounds;
    expect(bounds.left, closeTo(20, 0.0001));
    expect(bounds.top, closeTo(20, 0.0001));
    expect(bounds.right, closeTo(30, 0.0001));
    expect(bounds.bottom, closeTo(30, 0.0001));
    expect(pose.layers.single.pivot, const Offset(25, 25));
  });

  test('hides a layer and its descendants', () {
    final rig = _rig(
      layers: <LayerDefinition>[
        const LayerDefinition(id: 'back', defaultFrame: _backFrame),
        const LayerDefinition(
          id: 'parent',
          defaultFrame: _parentFrame,
          offset: Offset(10, 10),
          visible: false,
        ),
        const LayerDefinition(
          id: 'child',
          parent: 'parent',
          defaultFrame: _childFrame,
          offset: Offset(5, 5),
        ),
      ],
    );
    final pose = buildCompanionPose(rig);
    expect(pose.quads.map((quad) => quad.layerId), <String>['back']);
    expect(
      pose.layers.where((layer) => layer.id == 'child').single.visible,
      isFalse,
    );

    final isolated = buildCompanionPose(
      _rig(),
      hiddenLayers: const <String>{'parent'},
    );
    expect(isolated.quads.map((quad) => quad.layerId), <String>['back']);
  });

  test('multiplies opacity down the tree and with lab overrides', () {
    final pose = buildCompanionPose(_rig());
    expect(pose.quads[1].opacity, closeTo(0.5, 0.0001));
    expect(pose.quads[2].opacity, closeTo(0.25, 0.0001));

    final dimmed = buildCompanionPose(
      _rig(),
      layerOpacity: const <String, double>{'parent': 0.5},
    );
    expect(dimmed.quads[1].opacity, closeTo(0.25, 0.0001));
    expect(dimmed.quads[2].opacity, closeTo(0.125, 0.0001));

    final transparent = buildCompanionPose(
      _rig(),
      layerOpacity: const <String, double>{'parent': 0},
    );
    expect(transparent.quads.map((quad) => quad.layerId), <String>['back']);
  });

  test('applies animation overrides to offsets and frames', () {
    final pose = buildCompanionPose(
      _rig(),
      animations: const <String, LayerAnimation>{
        'parent': LayerAnimation(offsetX: 0, offsetY: 0),
        'child': LayerAnimation(frame: _backFrame),
      },
    );
    expect(pose.quads[1].bounds, const Rect.fromLTRB(0, 0, 10, 10));
    expect(pose.quads[2].region, _backFrame);
    expect(pose.quads[2].bounds, const Rect.fromLTRB(5, 5, 13, 13));
  });

  test('applies a root transform to every quad and pivot', () {
    final pose = buildCompanionPose(
      _rig(),
      rootTransform: Affine2.translation(100, 50),
    );
    expect(pose.quads[1].bounds, const Rect.fromLTRB(110, 60, 120, 70));
    expect(pose.layers[1].pivot, const Offset(115, 65));
  });
}
