import 'package:companion_focus/companion_engine/animation/rig_playback.dart';
import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:companion_focus/companion_engine/rig/rig_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tracks', () {
    test('interpolates linear keyframes and holds step keyframes', () {
      final linear = PropertyTrack(
        property: LayerProperty.rotationDegrees,
        keyframes: const <Keyframe>[
          Keyframe(timeMs: 0, value: 0),
          Keyframe(timeMs: 100, value: 10),
        ],
      );
      expect(linear.valueAt(-10), 0);
      expect(linear.valueAt(50), closeTo(5, 0.0001));
      expect(linear.valueAt(150), 10);

      final step = PropertyTrack(
        property: LayerProperty.opacity,
        keyframes: const <Keyframe>[
          Keyframe(timeMs: 0, value: 1, easing: KeyframeEasing.step),
          Keyframe(timeMs: 100, value: 0.25),
        ],
      );
      expect(step.valueAt(99), 1);
      expect(step.valueAt(100), 0.25);
    });

    test('frame tracks loop or hold their last frame independently', () {
      final open = GeometricRigFixture.eyeOpenRegion;
      final closed = GeometricRigFixture.eyeClosedRegion;
      final looping = FrameTrack(
        frames: <SpriteRegion>[open, closed],
        frameDurationMs: 100,
      );
      expect(looping.indexAt(0), 0);
      expect(looping.indexAt(99), 0);
      expect(looping.indexAt(100), 1);
      expect(looping.indexAt(250), 0);

      final held = FrameTrack(
        frames: <SpriteRegion>[open, closed],
        frameDurationMs: 100,
        loop: false,
      );
      expect(held.indexAt(250), 1);
    });
  });

  group('playback', () {
    test('samples the default clip at the scrub time', () {
      final playback = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
      );
      playback.seek(800);
      final sample = playback.sample();
      expect(sample['body']?.scaleY, closeTo(1.03, 0.0001));
      expect(sample['body']?.offsetY, closeTo(33, 0.0001));
      expect(sample['tail']?.rotationDegrees, closeTo(-18, 0.0001));
      expect(sample['eye']?.frame?.x, GeometricRigFixture.eyeOpenRegion.x);
    });

    test('loops the default clip and reports the wrap', () {
      final playback = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
      );
      final events = playback.advance(1700);
      expect(playback.timeOf('idle'), closeTo(100, 0.001));
      expect(events.where((event) => event.looped), hasLength(1));
    });

    test('one-shot overlays complete once and reveal the default state', () {
      final playback = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
      );
      playback.play('pet');
      expect(playback.sample()['eye']?.frame?.x, GeometricRigFixture.eyeClosedRegion.x);

      final events = playback.advance(950);
      expect(events.where((event) => event.completed), hasLength(1));
      expect(playback.isPlaying('pet'), isFalse);
      expect(playback.isPlaying('idle'), isTrue);
      expect(playback.sample()['eye']?.frame?.x, GeometricRigFixture.eyeOpenRegion.x);
    });

    test('independent clips keep their own time and later clips win', () {
      final playback = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
      );
      playback.play('walk');
      playback.advance(175);
      final sample = playback.sample();
      expect(playback.timeOf('walk'), closeTo(175, 0.001));
      expect(sample['body']?.offsetY, closeTo(30.5, 0.0001));
      expect(sample['legFront']?.rotationDegrees, closeTo(-18, 0.0001));
      expect(sample['eye']?.frame?.x, GeometricRigFixture.eyeOpenRegion.x);
    });

    test('seek scrubs every active clip', () {
      final playback = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
      );
      playback.play('pet');
      playback.seek(300);
      final sample = playback.sample();
      expect(sample['head']?.rotationDegrees, closeTo(6, 0.0001));
      expect(sample['eye']?.frame?.x, GeometricRigFixture.eyeClosedRegion.x);
    });

    test('scales elapsed time by playback speed', () {
      final half = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
        speed: 0.5,
      );
      half.advance(1000);
      expect(half.timeOf('idle'), closeTo(500, 0.001));

      final fast = RigPlayback(
        rig: GeometricRigFixture.buildRig(),
        defaultClip: 'idle',
        speed: 2,
      );
      final events = fast.advance(1000);
      expect(fast.timeOf('idle'), closeTo(400, 0.001));
      expect(events.where((event) => event.looped), hasLength(1));

      fast.speed = 0.25;
      fast.advance(400);
      expect(fast.timeOf('idle'), closeTo(500, 0.001));

      expect(() => fast.speed = 0, throwsArgumentError);
      expect(
        () => RigPlayback(
          rig: GeometricRigFixture.buildRig(),
          defaultClip: 'idle',
          speed: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
