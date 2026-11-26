import 'package:companion_focus/companion_engine/animation/rig_playback.dart';
import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:companion_focus/companion_engine/render/companion_pose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all fixture regions fit the generated atlas', () {
    final rig = GeometricRigFixture.buildRig();
    final atlas = rig.atlases[GeometricRigFixture.atlasId];
    expect(atlas, isNotNull);
    for (final layer in rig.layers) {
      expect(
        layer.defaultFrame.fitsWithin(atlas!.width, atlas.height),
        isTrue,
        reason: 'layer ${layer.id} default frame',
      );
    }
    for (final clip in rig.clips.values) {
      for (final layerClip in clip.layers) {
        final frames = layerClip.frames;
        if (frames == null) continue;
        for (final frame in frames.frames) {
          expect(
            frame.fitsWithin(atlas!.width, atlas.height),
            isTrue,
            reason: 'clip ${clip.id} layer ${layerClip.layerId}',
          );
        }
      }
    }
  });

  test('idle sampled pose uses every layer and independent eye frames', () {
    final rig = GeometricRigFixture.buildRig();
    final playback = RigPlayback(rig: rig, defaultClip: 'idle');
    playback.seek(600);
    final pose = buildCompanionPose(rig, animations: playback.sample());
    expect(
      pose.quads.map((quad) => quad.layerId).toList(),
      <String>[
        'tail',
        'legBack',
        'body',
        'legFront',
        'head',
        'earLeft',
        'earRight',
        'eye',
      ],
    );
    final eye = pose.layers.firstWhere((layer) => layer.id == 'eye');
    expect(eye.frame.x, GeometricRigFixture.eyeClosedRegion.x);
  });
}
