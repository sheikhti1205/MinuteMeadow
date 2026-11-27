import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quiet watch-style face drawn behind an exact digital clock readout.
///
/// The dial paints a hairline rim, sixty quiet minute ticks and one progress
/// hand on the chapter ring. The Clock screen uses it now and the Focus session
/// readout is the other intended consumer; the caller supplies the normalized
/// [progress] and keeps its own digital child, so the exact elapsed or
/// remaining text stays the accessible readout.
///
/// [progress] is a fraction of one clockwise revolution: `0` places the hand
/// at twelve o'clock and `1` returns it there after a full turn. Values
/// outside `0..1`, including infinities and `NaN`, clamp through
/// [clampProgress]. The dial is deliberately convention-free: a stopwatch
/// repeats one revolution each minute, and the Clock page advances a countdown
/// hand with consumed time (`elapsed / duration`). A caller that instead passes
/// remaining time gets the same clamped behavior and an unwinding hand.
///
/// The hand stops at the chapter ring instead of crossing the face, so the
/// exact digits are never obscured by decoration. The face only draws. It
/// starts no animation, absorbs no pointers and adds no semantics of its own,
/// so surrounding actions and the child readout keep their existing access.
/// The child is fitted inside the face so compact slots, long exact values and
/// large text never clip it.
class WatchTimerDial extends StatelessWidget {
  const WatchTimerDial({
    required this.progress,
    required this.child,
    this.diameter = 240,
    super.key,
  }) : assert(diameter > 0);

  /// Normalized progress along the dial, clamped when painted.
  final double progress;

  /// The exact digital readout. It is never replaced or abbreviated.
  final Widget child;

  /// Preferred face diameter in logical pixels.
  ///
  /// The face is always square. It shrinks to the smaller of the incoming
  /// width and height, and stays centered when a parent hands out a
  /// rectangular slot.
  final double diameter;

  /// Clamps [value] into the dial's single clockwise revolution.
  static double clampProgress(double value) {
    if (value.isNaN) {
      return 0;
    }
    if (value <= 0) {
      return 0;
    }
    if (value >= 1) {
      return 1;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final clamped = clampProgress(progress);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boundedWidth = constraints.hasBoundedWidth;
        final boundedHeight = constraints.hasBoundedHeight;
        final double available;
        if (boundedWidth && boundedHeight) {
          available = math.min(constraints.maxWidth, constraints.maxHeight);
        } else if (boundedWidth) {
          available = constraints.maxWidth;
        } else if (boundedHeight) {
          available = constraints.maxHeight;
        } else {
          available = diameter;
        }
        final side = math.min(diameter, available);
        if (side <= 0) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.center,
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  painter: _WatchDialPainter(
                    progress: clamped,
                    rim: colors.outlineVariant,
                    minorTick: colors.outlineVariant,
                    majorTick: colors.onSurfaceVariant.withValues(alpha: 0.55),
                    hand: colors.onSurface,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side * 0.12),
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: child),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WatchDialPainter extends CustomPainter {
  _WatchDialPainter({
    required this.progress,
    required this.rim,
    required this.minorTick,
    required this.majorTick,
    required this.hand,
  });

  final double progress;
  final Color rim;
  final Color minorTick;
  final Color majorTick;
  final Color hand;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    if (radius <= 0) {
      return;
    }
    final center = size.center(Offset.zero);

    canvas.drawCircle(
      center,
      math.max(0.0, radius - 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim,
    );

    // Tick lengths shrink with the face so a tiny dial can never invert the
    // inner and outer radius. At normal sizes the caps are never reached and
    // the default geometry is unchanged.
    final tickOuter = math.max(0.0, radius - math.min(5.0, radius * 0.08));
    final majorLength = math.min(6.0, radius * 0.10);
    final minorLength = math.min(3.0, radius * 0.05);
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var minute = 0; minute < 60; minute++) {
      final major = minute % 5 == 0;
      final angle = -math.pi / 2 + minute * math.pi / 30;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final inner = math.max(
        0.0,
        tickOuter - (major ? majorLength : minorLength),
      );
      tickPaint
        ..color = major ? majorTick : minorTick
        ..strokeWidth = major ? 1.4 : 1.0;
      canvas.drawLine(
        center + direction * inner,
        center + direction * tickOuter,
        tickPaint,
      );
    }

    final angle = -math.pi / 2 + progress * 2 * math.pi;
    final handDirection = Offset(math.cos(angle), math.sin(angle));
    final handOuter = math.max(0.0, radius - math.min(4.0, radius * 0.08));
    final handInner = math.min(radius * 0.84, handOuter);
    canvas.drawLine(
      center + handDirection * handInner,
      center + handDirection * handOuter,
      Paint()
        ..color = hand
        ..strokeWidth = math.max(1.0, radius * 0.038)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WatchDialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.rim != rim ||
      oldDelegate.minorTick != minorTick ||
      oldDelegate.majorTick != majorTick ||
      oldDelegate.hand != hand;
}
