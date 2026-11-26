import 'dart:ui';

import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:companion_focus/companion_engine/scene/companion_scene.dart';
import 'package:flutter_test/flutter_test.dart';

const _tick = Duration(milliseconds: 16);

List<CompanionSceneEventType> _drain(CompanionScene scene) => scene
    .takeEvents()
    .map((event) => event.type)
    .toList();

void _run(CompanionScene scene, Duration duration) {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    scene.advance(_tick);
    elapsed += _tick;
  }
}

void main() {
  test('throttles petting while the pointer stays on the companion', () {
    final scene = CompanionScene();
    expect(scene.startPet(scene.companionCenter), isTrue);
    expect(_drain(scene), <CompanionSceneEventType>[
      CompanionSceneEventType.pet,
    ]);
    expect(scene.motion, CompanionMotion.petting);

    scene.advance(const Duration(milliseconds: 100));
    expect(_drain(scene), isEmpty);
    scene.advance(const Duration(milliseconds: 120));
    expect(_drain(scene), <CompanionSceneEventType>[
      CompanionSceneEventType.pet,
    ]);
    expect(scene.petCount, 2);

    scene.endPet();
    scene.advance(const Duration(seconds: 1));
    expect(_drain(scene), isEmpty);
    expect(scene.isPetting, isFalse);
    expect(scene.motion, CompanionMotion.idle);
  });

  test('ignores petting that misses or leaves the companion', () {
    final scene = CompanionScene();
    expect(scene.startPet(Offset.zero), isFalse);
    expect(scene.isPetting, isFalse);

    expect(scene.startPet(scene.companionCenter), isTrue);
    scene.updatePet(const Offset(-100, -100));
    expect(scene.isPetting, isFalse);
    expect(scene.takeEvents(), hasLength(1));
  });

  test('throws, bounces, chases, catches and returns deterministically', () {
    final scene = CompanionScene();
    expect(scene.throwBall(), isTrue);
    expect(_drain(scene), <CompanionSceneEventType>[
      CompanionSceneEventType.ballThrown,
    ]);
    expect(scene.ballPhase, BallPhase.flying);

    final events = <CompanionSceneEventType>[];
    var elapsed = Duration.zero;
    while (elapsed < const Duration(seconds: 8)) {
      scene.advance(_tick);
      elapsed += _tick;
      events.addAll(_drain(scene));
      if (events.contains(CompanionSceneEventType.ballReturned)) break;
    }

    expect(events.first, CompanionSceneEventType.ballBounced);
    expect(events, contains(CompanionSceneEventType.ballCaught));
    expect(events, contains(CompanionSceneEventType.ballReturned));
    expect(
      events.indexOf(CompanionSceneEventType.ballCaught),
      lessThan(events.indexOf(CompanionSceneEventType.ballReturned)),
    );
    expect(
      events.where((type) => type == CompanionSceneEventType.ballBounced),
      isNotEmpty,
    );
    expect(scene.ballPhase, BallPhase.none);
    expect(scene.motion, CompanionMotion.idle);
    expect(scene.companionTopLeft, scene.home);
  });

  test('repeats the same trajectory for the same inputs', () {
    final first = CompanionScene();
    final second = CompanionScene();
    first.throwBall();
    second.throwBall();
    for (var step = 0; step < 30; step++) {
      first.advance(_tick);
      second.advance(_tick);
    }
    expect(first.ballPosition, second.ballPosition);
    expect(first.companionTopLeft, second.companionTopLeft);
    expect(_drain(first), _drain(second));
  });

  test('blocks throwing and petting while the ball is live', () {
    final scene = CompanionScene();
    expect(scene.throwBall(), isTrue);
    expect(scene.throwBall(), isFalse);
    expect(scene.startPet(scene.companionCenter), isFalse);
    expect(scene.hitboxes.map((hitbox) => hitbox.id), contains('ball'));

    _run(scene, const Duration(milliseconds: 400));
    expect(scene.ballPhase, isNot(BallPhase.none));
    expect(scene.ballQuad(GeometricRigFixture.ballRegion), isNotNull);
    scene.reset();
    expect(_drain(scene), isEmpty);
    expect(scene.ballPhase, BallPhase.none);
    expect(scene.hitboxes.map((hitbox) => hitbox.id), isNot(contains('ball')));
    expect(scene.throwBall(), isTrue);
  });

  test('overlays the ball at the scene position', () {
    final scene = CompanionScene();
    expect(scene.ballQuad(GeometricRigFixture.ballRegion), isNull);
    scene.throwBall();
    final quad = scene.ballQuad(GeometricRigFixture.ballRegion);
    expect(quad, isNotNull);
    final placed = quad!;
    expect(placed.region, GeometricRigFixture.ballRegion);
    expect(
      placed.bounds.center,
      offsetMoreOrLessEquals(scene.ballPosition, epsilon: 0.0001),
    );
  });

  test('resets the ball when the chase times out', () {
    final scene = CompanionScene(
      field: const Size(400, 120),
      walkSpeed: 1,
      catchRadius: 0.5,
      chaseTimeout: const Duration(seconds: 1),
    );
    scene.throwBall(target: const Offset(395, 108));
    final events = <CompanionSceneEventType>[];
    var elapsed = Duration.zero;
    while (elapsed < const Duration(seconds: 3)) {
      scene.advance(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
      events.addAll(_drain(scene));
      if (events.contains(CompanionSceneEventType.ballMissed)) break;
    }
    expect(events, contains(CompanionSceneEventType.ballMissed));
    expect(scene.ballPhase, BallPhase.none);
    expect(scene.motion, CompanionMotion.idle);
  });
}
