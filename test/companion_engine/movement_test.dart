import 'dart:ui' show Offset;

import 'package:companion_focus/companion_engine/scene/companion_move.dart';
import 'package:companion_focus/companion_engine/scene/companion_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executes an ordered walk and jump route with updated hitboxes', () {
    final scene = CompanionScene();
    final start = scene.home;
    final first = start + const Offset(-20, 0);
    final last = start + const Offset(20, 0);
    expect(scene.playRoute([
      CompanionMove(target: first, duration: const Duration(milliseconds: 100)),
      CompanionMove(
        target: last,
        duration: const Duration(milliseconds: 200),
        gait: CompanionGait.jump,
        jumpHeight: 20,
      ),
    ]), isTrue);
    expect(scene.facing, -1);

    scene.advance(const Duration(milliseconds: 100));
    expect(scene.companionTopLeft, first);
    expect(scene.motion, CompanionMotion.jumping);
    expect(scene.facing, 1);

    scene.advance(const Duration(milliseconds: 100));
    expect(scene.companionTopLeft, start - const Offset(0, 20));
    expect(scene.companionHitbox.topLeft, scene.companionTopLeft);

    scene.advance(const Duration(milliseconds: 100));
    expect(scene.companionTopLeft, last);
    expect(scene.isMoving, isFalse);
    expect(scene.takeEvents().single.type, CompanionSceneEventType.movementCompleted);
  });

  test('keeps moving targets inside the scene and protects ball play', () {
    final scene = CompanionScene();
    expect(scene.runTo(const Offset(-50, -50)), isTrue);
    expect(scene.motion, CompanionMotion.running);
    expect(scene.throwBall(), isTrue);
    expect(scene.isMoving, isFalse);
    expect(scene.walkTo(scene.home), isFalse);
  });

  test('lets the ball roll before the actor catches and returns it', () {
    final scene = CompanionScene();
    expect(scene.throwBall(), isTrue);
    for (var step = 0; step < 300 && scene.ballPhase != BallPhase.none; step++) {
      scene.advance(const Duration(milliseconds: 33));
    }
    final events = scene.takeEvents().map((event) => event.type).toList();
    expect(events, containsAllInOrder([
      CompanionSceneEventType.ballThrown,
      CompanionSceneEventType.ballBounced,
      CompanionSceneEventType.ballRolling,
      CompanionSceneEventType.ballCaught,
      CompanionSceneEventType.ballReturned,
    ]));
    expect(scene.companionTopLeft, scene.home);
  });
}
