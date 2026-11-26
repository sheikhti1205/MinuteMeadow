import 'package:companion_focus/features/companion/pack_manifest.dart';
import 'package:companion_focus/features/companion/pack_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('round-trips parent transforms, timed tracks, and event markers', () {
    final files = fixtureFiles();
    final json = manifestFor(
      files,
      layers: [
        {'id': 'body', 'z': 0},
        {
          'id': 'head',
          'z': 1,
          'parent': 'body',
          'pivot': {'x': 2, 'y': 3},
          'opacity': 0.75,
        },
      ],
      clips: [
        {
          ..._clip,
          'tracks': [
            {
              'layer': 'head',
              'property': 'rotationDegrees',
              'keyframes': [
                {'timeMs': 0, 'value': 0},
                {'timeMs': 400, 'value': 25, 'easing': 'step'},
              ],
            },
          ],
          'events': [
            {'id': 'turn', 'timeMs': 400},
          ],
          'state': {'priority': 5, 'interruptible': false, 'transitionMs': 120},
        },
      ],
    );
    final decoded = PackManifest.fromJson(json);
    final restored = PackManifest.fromJson(decoded.toJson());
    expect(restored.layers.last.pose.parent, 'body');
    expect(restored.layers.last.pose.pivot?.y, 3);
    expect(restored.clips.single.tracks.single.keyframes.last.easing, PackMotionEasing.step);
    expect(restored.clips.single.events.single.id, 'turn');
    expect(restored.clips.single.timelineDurationMs, 600);
    expect(restored.clips.single.state?.interruptible, isFalse);
  });

  test('rejects a cycle between two parent layers', () {
    final json = manifestFor(
      fixtureFiles(),
      layers: [
        {'id': 'body', 'z': 0, 'parent': 'head'},
        {'id': 'head', 'z': 1, 'parent': 'body'},
      ],
      clips: [_clip],
    );
    expect(() => PackManifest.fromJson(json), throwsFormatException);
  });

  test('rejects an event after the end of a clip', () {
    final json = manifestFor(
      fixtureFiles(),
      layers: [
        {'id': 'body', 'z': 0},
        {'id': 'head', 'z': 1},
      ],
      clips: [
        {
          ..._clip,
          'events': [
            {'id': 'late', 'timeMs': 601},
          ],
        },
      ],
    );
    expect(() => PackManifest.fromJson(json), throwsFormatException);
  });
}

const _clip = <String, Object?>{
  'id': 'idle',
  'fps': 8,
  'loop': true,
  'durationMs': 600,
  'frames': [
    {'layer': 'body', 'asset': 'preview.png', 'rect': {'x': 0, 'y': 0, 'w': 4, 'h': 4}},
    {'layer': 'head', 'asset': 'preview.png', 'rect': {'x': 0, 'y': 0, 'w': 4, 'h': 4}},
  ],
};
