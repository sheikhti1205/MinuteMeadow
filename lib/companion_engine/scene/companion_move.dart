import 'dart:ui';

enum CompanionGait { walk, run, jump }

class CompanionMove {
  const CompanionMove({
    required this.target,
    required this.duration,
    this.gait = CompanionGait.walk,
    this.jumpHeight = 24,
  });

  final Offset target;
  final Duration duration;
  final CompanionGait gait;
  final double jumpHeight;
}
