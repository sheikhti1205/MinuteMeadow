import 'dart:math' as math;
import 'dart:ui';

import '../render/affine2.dart';
import '../render/companion_pose.dart';
import '../render/debug_geometry.dart';
import '../rig/rig_model.dart';
import 'companion_move.dart';

enum CompanionMotion { idle, petting, chasing, returning, walking, running, jumping }

enum BallPhase { none, flying, rolling, chasing, returning }

enum CompanionSceneEventType {
  pet,
  ballThrown,
  ballBounced,
  ballRolling,
  ballCaught,
  ballReturned,
  ballMissed,
  movementCompleted,
}

final class CompanionSceneEvent {
  const CompanionSceneEvent({required this.type, required this.atMs});

  final CompanionSceneEventType type;
  final double atMs;
}

/// Scene-owned movement and touch state. The rig decides what to draw; this
/// class only owns positions, hitboxes and interaction milestones.
///
/// The ball follows a deterministic throw, bounce, chase, catch and return
/// sequence. Petting emits at a throttled cadence while the pointer stays on
/// the companion.
final class CompanionScene {
  CompanionScene({
    this.field = const Size(160, 120),
    this.companionSize = const Size(64, 64),
    this.walkSpeed = 110,
    this.gravity = 900,
    this.groundInset = 6,
    this.ballRadius = 6,
    this.maxBounces = 3,
    this.throwFlightSeconds = 0.55,
    this.petInterval = const Duration(milliseconds: 220),
    this.catchRadius = 22,
    this.chaseTimeout = const Duration(seconds: 5),
    this.maxStep = const Duration(milliseconds: 100),
  }) {
    assert(walkSpeed > 0);
    assert(gravity > 0);
    assert(ballRadius > 0);
    assert(maxBounces >= 1);
    assert(throwFlightSeconds > 0);
    assert(maxStep >= const Duration(milliseconds: 1));
    _position = home;
  }

  final Size field;
  final Size companionSize;
  final double walkSpeed;
  final double gravity;
  final double groundInset;
  final double ballRadius;
  final int maxBounces;
  final double throwFlightSeconds;
  final Duration petInterval;
  final double catchRadius;
  final Duration chaseTimeout;

  /// Longest physics step within a display frame.
  final Duration maxStep;

  late Offset _position;
  double _facing = 1;
  double _nowMs = 0;

  CompanionMotion _motion = CompanionMotion.idle;
  bool _petting = false;
  double _nextPetAtMs = 0;
  int _petCount = 0;

  BallPhase _ballPhase = BallPhase.none;
  Offset _ball = Offset.zero;
  Offset _ballVelocity = Offset.zero;
  int _bounces = 0;
  double _chaseElapsedSeconds = 0;

  final List<CompanionSceneEvent> _events = <CompanionSceneEvent>[];
  List<CompanionMove> _route = const [];
  int _routeIndex = 0;
  late Offset _moveFrom;
  double _moveElapsed = 0;

  double get nowMs => _nowMs;

  Offset get home => Offset(
    (field.width - companionSize.width) / 2,
    field.height - groundInset - companionSize.height,
  );

  Offset get companionTopLeft => _position;
  Rect get companionRect => _position & companionSize;
  Offset get companionCenter => companionRect.center;
  double get facing => _facing;
  CompanionMotion get motion => _motion;
  bool get isPetting => _petting;
  bool get isMoving => _route.isNotEmpty;
  int get petCount => _petCount;

  BallPhase get ballPhase => _ballPhase;
  Offset get ballPosition => _ball;
  Offset get ballVelocity => _ballVelocity;
  int get bounces => _bounces;

  Rect get companionHitbox => companionRect;

  List<SpriteHitbox> get hitboxes => <SpriteHitbox>[
    SpriteHitbox(
      id: 'companion',
      label: 'companion',
      rect: companionRect,
    ),
    if (_ballPhase != BallPhase.none)
      SpriteHitbox(
        id: 'ball',
        label: 'ball',
        rect: Rect.fromCircle(center: _ball, radius: ballRadius),
      ),
  ];

  List<CompanionSceneEvent> get events =>
      List<CompanionSceneEvent>.unmodifiable(_events);

  List<CompanionSceneEvent> takeEvents() {
    final copy = List<CompanionSceneEvent>.of(_events);
    _events.clear();
    return copy;
  }

  bool hitTestCompanion(Offset point) =>
      companionRect.inflate(4).contains(point);

  /// Starts or continues a petting stroke. Returns false when the scene is busy
  /// with the ball or when the point misses the companion.
  bool startPet(Offset point) {
    if (_ballPhase != BallPhase.none || isMoving) return false;
    if (_motion == CompanionMotion.chasing ||
        _motion == CompanionMotion.returning) {
      return false;
    }
    if (!hitTestCompanion(point)) return false;
    if (_petting) return true;
    _petting = true;
    _motion = CompanionMotion.petting;
    _nextPetAtMs = _nowMs + petInterval.inMicroseconds / 1000;
    _petCount += 1;
    _emit(CompanionSceneEventType.pet);
    return true;
  }

  void updatePet(Offset point) {
    if (!_petting) return;
    if (!companionRect.inflate(8).contains(point)) endPet();
  }

  void endPet() {
    if (!_petting) return;
    _petting = false;
    _motion = CompanionMotion.idle;
  }

  /// Tosses the ball from the companion toward [target], or a deterministic
  /// default in front of the companion.
  bool throwBall({Offset? target}) {
    if (_ballPhase != BallPhase.none) return false;
    endPet();
    _route = const [];
    final groundCenter = _ground - ballRadius;
    final start = Offset(
      (companionCenter.dx + _facing * 10)
          .clamp(ballRadius, field.width - ballRadius)
          .toDouble(),
      companionCenter.dy - 12,
    );
    final requested = target ??
        Offset(companionCenter.dx + _facing * 70, groundCenter);
    final destination = Offset(
      requested.dx
          .clamp(ballRadius, field.width - ballRadius)
          .toDouble(),
      requested.dy.clamp(ballRadius, groundCenter).toDouble(),
    );
    final flight = throwFlightSeconds;
    _ball = start;
    _ballVelocity = Offset(
      (destination.dx - start.dx) / flight,
      (destination.dy -
              start.dy -
              0.5 * gravity * flight * flight) /
          flight,
    );
    _ballPhase = BallPhase.flying;
    _bounces = 0;
    _chaseElapsedSeconds = 0;
    _motion = CompanionMotion.idle;
    _facing = destination.dx >= start.dx ? 1 : -1;
    _emit(CompanionSceneEventType.ballThrown);
    return true;
  }

  /// Advances movement and interaction state by [delta].
  void advance(Duration delta) {
    if (delta <= Duration.zero) return;
    _nowMs += delta.inMicroseconds / 1000;
    _advancePetting();
    // Recover from dropped frames without simulating an entire background gap.
    var remaining = math.min(delta.inMicroseconds, Duration.microsecondsPerSecond);
    final stepLimit = math.max(maxStep.inMicroseconds, 1000);
    while (remaining > 0 && (_ballPhase != BallPhase.none || isMoving)) {
      final step = math.min(remaining, stepLimit);
      _advanceMotion(step / Duration.microsecondsPerSecond);
      remaining -= step;
    }
  }

  void _advanceMotion(double step) {
    switch (_ballPhase) {
      case BallPhase.none:
        _advanceRoute(step);
        break;
      case BallPhase.flying:
        _advanceFlying(step);
      case BallPhase.rolling:
        _advanceRolling(step);
      case BallPhase.chasing:
        _advanceChasing(step);
      case BallPhase.returning:
        _advanceReturning(step);
    }
  }

  void reset() {
    _position = home;
    _facing = 1;
    _petting = false;
    _ballPhase = BallPhase.none;
    _ball = Offset.zero;
    _ballVelocity = Offset.zero;
    _bounces = 0;
    _chaseElapsedSeconds = 0;
    _motion = CompanionMotion.idle;
    _nextPetAtMs = 0;
    _route = const [];
    _events.clear();
  }

  bool walkTo(Offset target) => _travel(target, CompanionGait.walk, walkSpeed);

  bool runTo(Offset target) => _travel(target, CompanionGait.run, walkSpeed * 1.8);

  bool jumpTo(Offset target, {double height = 24}) => playRoute([
    CompanionMove(
      target: target,
      duration: const Duration(milliseconds: 420),
      gait: CompanionGait.jump,
      jumpHeight: height,
    ),
  ]);

  bool _travel(Offset target, CompanionGait gait, double speed) {
    if (!target.isFinite) return false;
    final distance = (_bound(target) - _position).distance;
    return playRoute([
      CompanionMove(
        target: target,
        duration: Duration(milliseconds: math.max(1, (distance / speed * 1000).round())),
        gait: gait,
      ),
    ]);
  }

  bool playRoute(List<CompanionMove> moves) {
    if (_ballPhase != BallPhase.none || moves.isEmpty || moves.length > 32 ||
        moves.any((move) => !move.target.isFinite || move.duration <= Duration.zero ||
            move.duration > const Duration(seconds: 10) ||
            !move.jumpHeight.isFinite || move.jumpHeight < 0 || move.jumpHeight > field.height)) {
      return false;
    }
    endPet();
    _route = List.unmodifiable(moves);
    _routeIndex = 0;
    _startMove();
    return true;
  }

  void _startMove() {
    _moveFrom = _position;
    _moveElapsed = 0;
    final move = _route[_routeIndex];
    final dx = _bound(move.target).dx - _position.dx;
    if (dx != 0) _facing = dx.sign;
    _motion = switch (move.gait) {
      CompanionGait.walk => CompanionMotion.walking,
      CompanionGait.run => CompanionMotion.running,
      CompanionGait.jump => CompanionMotion.jumping,
    };
  }

  void _advanceRoute(double seconds) {
    while (_route.isNotEmpty && seconds > 0) {
      final move = _route[_routeIndex];
      final duration = move.duration.inMicroseconds / Duration.microsecondsPerSecond;
      final left = duration - _moveElapsed;
      final used = math.min(seconds, left);
      _moveElapsed += used;
      seconds -= used;
      final progress = _moveElapsed / duration;
      final target = _bound(move.target);
      final position = Offset.lerp(_moveFrom, target, progress)!;
      final height = move.gait == CompanionGait.jump
          ? 4 * move.jumpHeight * progress * (1 - progress)
          : 0.0;
      _position = Offset(position.dx, math.max(0.0, position.dy - height));
      if (used < left) return;
      _position = target;
      _routeIndex++;
      if (_routeIndex == _route.length) {
        _route = const [];
        _motion = CompanionMotion.idle;
        _emit(CompanionSceneEventType.movementCompleted);
      } else {
        _startMove();
      }
    }
  }

  Offset _bound(Offset point) => Offset(
    point.dx.clamp(0.0, math.max(0, field.width - companionSize.width)).toDouble(),
    point.dy.clamp(0.0, math.max(0, _ground - companionSize.height)).toDouble(),
  );

  /// The ball sprite over the scene, or null when the ball is put away.
  CompanionQuad? ballQuad(SpriteRegion region) {
    if (_ballPhase == BallPhase.none) return null;
    final topLeft = Offset(
      _ball.dx - region.width / 2,
      _ball.dy - region.height / 2,
    );
    return CompanionQuad(
      layerId: 'ball',
      region: region,
      transform: Affine2.translation(topLeft.dx, topLeft.dy),
      opacity: 1,
    );
  }

  void _advancePetting() {
    if (!_petting) return;
    final intervalMs = petInterval.inMicroseconds / 1000;
    if (intervalMs <= 0) return;
    if (_nowMs >= _nextPetAtMs) {
      _petCount += 1;
      _emit(CompanionSceneEventType.pet);
      _nextPetAtMs = _nowMs + intervalMs;
    }
  }

  void _advanceFlying(double seconds) {
    var position = _ball + _ballVelocity * seconds;
    var velocity = Offset(
      _ballVelocity.dx,
      _ballVelocity.dy + gravity * seconds,
    );

    if (position.dx < ballRadius) {
      position = Offset(ballRadius, position.dy);
      velocity = Offset(-velocity.dx * 0.6, velocity.dy);
    } else if (position.dx > field.width - ballRadius) {
      position = Offset(field.width - ballRadius, position.dy);
      velocity = Offset(-velocity.dx * 0.6, velocity.dy);
    }

    final ground = _ground - ballRadius;
    if (position.dy >= ground && velocity.dy > 0) {
      position = Offset(position.dx, ground);
      final impact = velocity.dy;
      velocity = Offset(velocity.dx * 0.7, -impact * 0.55);
      _bounces += 1;
      _emit(CompanionSceneEventType.ballBounced);
      if (_bounces >= maxBounces || velocity.dy.abs() < 40) {
        _ballPhase = BallPhase.rolling;
        _motion = CompanionMotion.chasing;
        _chaseElapsedSeconds = 0;
        velocity = Offset(velocity.dx, 0);
        _emit(CompanionSceneEventType.ballRolling);
      }
    }

    _ball = position;
    _ballVelocity = velocity;
  }

  void _advanceRolling(double seconds) {
    final speed = _ballVelocity.dx;
    final nextSpeed = math.max(0.0, speed.abs() - 180 * seconds) * speed.sign;
    final nextX = _ball.dx + (speed + nextSpeed) * seconds / 2;
    final bounded = nextX.clamp(ballRadius, field.width - ballRadius).toDouble();
    _ball = Offset(bounded, _ground - ballRadius);
    if (nextSpeed == 0 || nextX != bounded) {
      _ballVelocity = Offset.zero;
      _ballPhase = BallPhase.chasing;
    } else {
      _ballVelocity = Offset(nextSpeed, 0);
    }
  }

  void _advanceChasing(double seconds) {
    _chaseElapsedSeconds += seconds;
    if (_chaseElapsedSeconds > chaseTimeout.inMicroseconds / 1e6) {
      _ballPhase = BallPhase.none;
      _ballVelocity = Offset.zero;
      _bounces = 0;
      _motion = CompanionMotion.idle;
      _emit(CompanionSceneEventType.ballMissed);
      return;
    }
    _moveToward(_ball.dx - companionSize.width / 2, seconds);
    if ((companionCenter.dx - _ball.dx).abs() <= catchRadius) {
      _ballPhase = BallPhase.returning;
      _motion = CompanionMotion.returning;
      _emit(CompanionSceneEventType.ballCaught);
    }
  }

  void _advanceReturning(double seconds) {
    _moveToward(home.dx, seconds);
    if ((_position.dx - home.dx).abs() <= 0.5) {
      _position = home;
      _ballPhase = BallPhase.none;
      _ballVelocity = Offset.zero;
      _bounces = 0;
      _motion = CompanionMotion.idle;
      _emit(CompanionSceneEventType.ballReturned);
      return;
    }
    _ball = companionCenter + Offset(_facing * 12, -8);
  }

  void _moveToward(double targetX, double seconds) {
    final delta = targetX - _position.dx;
    final maxDistance = walkSpeed * seconds;
    if (delta.abs() <= maxDistance) {
      _position = Offset(
        targetX.clamp(0.0, field.width - companionSize.width).toDouble(),
        _position.dy,
      );
    } else {
      _position = Offset(
        (_position.dx + delta.sign * maxDistance)
            .clamp(0.0, field.width - companionSize.width)
            .toDouble(),
        _position.dy,
      );
    }
    if (delta.abs() > 0.01) _facing = delta.sign;
  }

  double get _ground => field.height - groundInset;

  void _emit(CompanionSceneEventType type) {
    _events.add(CompanionSceneEvent(type: type, atMs: _nowMs));
  }
}
