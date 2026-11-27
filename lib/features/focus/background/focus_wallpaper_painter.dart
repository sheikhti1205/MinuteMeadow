import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../design/appearance_preferences.dart';

/// Paints a built-in live wallpaper over the whole surface.
///
/// The effects are simple, original procedural drawings made for this app.
/// They use only the two monochrome tones the host passes in, so the wallpaper
/// follows the active theme instead of importing a palette or image asset.
///
/// [time] is in seconds and only advances while motion is allowed. A host that
/// wants a still wallpaper keeps the same time, or sets [active] false for the
/// quieter rest state. The painter never starts a ticker of its own.
class FocusWallpaperPainter extends CustomPainter {
  const FocusWallpaperPainter({
    required this.type,
    required this.time,
    required this.base,
    required this.ink,
    required this.shade,
    required this.active,
  });

  final WallpaperType type;
  final double time;
  final Color base;
  final Color ink;
  final Color shade;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    switch (type) {
      case WallpaperType.none:
        return;
      case WallpaperType.dunes:
        _drawDunes(canvas, size);
        return;
      case WallpaperType.rain:
        _drawRain(canvas, size);
        return;
      case WallpaperType.embers:
        _drawEmbers(canvas, size);
        return;
      case WallpaperType.aurora:
        _drawAurora(canvas, size);
        return;
      case WallpaperType.mesh:
        _drawMesh(canvas, size);
        return;
    }
  }

  // ───────────────────────────── Dunes ─────────────────────────────

  void _drawDunes(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double strength = active ? 1.0 : 0.8;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h * 0.9),
          <Color>[
            ink.withValues(alpha: 0.10 * strength),
            base.withValues(alpha: 0),
          ],
        ),
    );

    final double sunX = w * (0.20 + 0.60 * _drift(time / 52));
    final double sunY = h * (0.28 - 0.06 * math.sin(time / 52 * _tau));
    _radialWash(
      canvas,
      Offset(sunX, sunY),
      h * 0.30,
      ink.withValues(alpha: 0.18 * strength),
      ink.withValues(alpha: 0),
    );
    canvas.drawCircle(
      Offset(sunX, sunY),
      h * 0.035,
      Paint()..color = ink.withValues(alpha: 0.24 * strength),
    );

    for (var index = 0; index < 4; index++) {
      final double band = index / 3;
      final Path path = Path()..moveTo(0, h);
      for (var step = 0; step <= 48; step++) {
        final double x = w * step / 48;
        final double swell =
            0.55 +
            0.30 * math.sin(x / w * _tau * (1.1 + band * 1.2) + time * 0.05) +
            0.15 * math.sin(x / w * _tau * 2.4 + index * 1.7);
        final double y =
            h * (0.54 + band * 0.20) - h * 0.10 * swell * (1 - band * 0.4);
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, h * (0.35 + band * 0.3)),
            Offset(0, h),
            <Color>[
              ink.withValues(alpha: (0.05 + band * 0.05) * strength),
              shade.withValues(alpha: (0.03 + band * 0.03) * strength),
            ],
          ),
      );
    }
  }

  // ───────────────────────────── Rain ─────────────────────────────

  void _drawRain(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double strength = active ? 1.0 : 0.75;

    _radialWash(
      canvas,
      Offset(w * 0.2, -h * 0.2),
      h * 0.9,
      ink.withValues(alpha: 0.06 * strength),
      ink.withValues(alpha: 0),
    );

    for (var index = 0; index < 76; index++) {
      final Offset seed = _scatter(index + 120);
      final double speed = 0.10 + 0.035 * (index % 4);
      final double q = _fraction(time * speed + seed.dy);
      final double length = h * (0.025 + 0.02 * (index % 4));
      final double x = seed.dx * w + (q - 0.5) * w * 0.10;
      final double y = -length + q * (h + length * 2);
      final double alpha = (0.07 + 0.05 * (index % 3)) * strength;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - length * 0.12, y + length),
        Paint()
          ..color = ink.withValues(alpha: alpha)
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var index = 0; index < 18; index++) {
      final Offset seed = _scatter(index + 520);
      final double q = _fraction(time * 0.05 + seed.dx);
      final double x = seed.dx * w;
      final double y = h * (0.55 + 0.40 * seed.dy);
      final double ripple = 0.5 + 0.5 * math.sin(q * _tau + index);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: (4 + 8 * ripple) * strength,
          height: (1.5 + 3 * ripple) * strength,
        ),
        Paint()
          ..color = ink.withValues(alpha: 0.10 * strength * (1 - ripple * 0.5))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  // ───────────────────────────── Embers ─────────────────────────────

  void _drawEmbers(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double motion = active ? 1.0 : 0.55;
    final double flicker =
        0.5 +
        0.25 * math.sin(time * 1.6 * _tau) +
        0.15 * math.sin(time * 2.7 * _tau + 1.2);

    _radialWash(
      canvas,
      Offset(w * 0.62, h * 1.05),
      w * (0.65 + 0.06 * flicker),
      ink.withValues(alpha: 0.16 * (0.6 + 0.4 * motion)),
      ink.withValues(alpha: 0),
    );

    for (var index = 0; index < 30; index++) {
      final Offset seed = _scatter(index + 260);
      final double speed = 0.018 + 0.012 * (index % 3);
      final double q = _fraction(time * speed + seed.dy);
      final double lift = math.sin(q * math.pi);
      final double x =
          w * (0.16 + 0.68 * seed.dx) +
          math.sin((q * 2.2 + seed.dx) * _tau) * w * 0.025;
      final double y = h * (1.02 - q * 0.88);
      final double radius = 0.9 + (index % 3) * 0.55;
      final double alpha = 0.32 * lift * (0.55 + 0.45 * motion);
      canvas.drawCircle(
        Offset(x, y),
        radius * 3.2,
        Paint()..color = ink.withValues(alpha: alpha * 0.22),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = ink.withValues(alpha: alpha),
      );
    }
  }

  // ───────────────────────────── Aurora ─────────────────────────────

  void _drawAurora(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double phase = time / 34 * _tau;
    final double strength = active ? 1.0 : 0.85;

    for (var index = 0; index < 4; index++) {
      final double topX =
          w * (0.10 + index * 0.24) + w * 0.07 * math.sin(phase + index * 1.4);
      final double midX =
          w * (0.28 + index * 0.18) + w * 0.10 * math.cos(phase + index);
      final double bottomX =
          w * (0.50 + index * 0.12) + w * 0.08 * math.sin(phase * 0.7 + index);
      final Path ribbon = Path()
        ..moveTo(topX, -h * 0.05)
        ..cubicTo(
          midX,
          h * 0.24,
          midX + w * 0.12,
          h * 0.52,
          bottomX,
          h * 1.05,
        );
      canvas.drawPath(
        ribbon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * (0.16 + index * 0.015)
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, h),
            <Color>[
              ink.withValues(alpha: 0),
              ink.withValues(alpha: 0.09 * strength),
              shade.withValues(alpha: 0.07 * strength),
              ink.withValues(alpha: 0),
            ],
            <double>[0, 0.28, 0.66, 1],
          ),
      );
    }
  }

  // ───────────────────────────── Mesh ─────────────────────────────

  void _drawMesh(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double phase = time / 40 * _tau;
    final double strength = active ? 1.0 : 0.85;

    for (var index = 0; index < 6; index++) {
      final int xTurns = 1 + index % 2;
      final int yTurns = 1 + (index + 1) % 3;
      final Offset center = Offset(
        w * (0.5 + 0.42 * math.sin(phase * xTurns + index * 1.7)),
        h * (0.5 + 0.40 * math.cos(phase * yTurns + index * 2.3)),
      );
      final double radius = w * (0.30 + 0.07 * (index % 3));
      final Color tone = index.isEven ? ink : shade;
      _radialWash(
        canvas,
        center,
        radius,
        tone.withValues(alpha: (0.10 + 0.02 * (index % 2)) * strength),
        tone.withValues(alpha: 0),
      );
    }

    _radialWash(
      canvas,
      Offset(w * (0.22 + 0.08 * math.sin(phase)), h * 0.18),
      w * 0.32,
      ink.withValues(alpha: 0.08 * strength),
      ink.withValues(alpha: 0),
    );
  }

  @override
  bool shouldRepaint(covariant FocusWallpaperPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.time != time ||
      oldDelegate.base != base ||
      oldDelegate.ink != ink ||
      oldDelegate.shade != shade ||
      oldDelegate.active != active;
}

const double _tau = 2 * math.pi;

double _fraction(double value) => value - value.floorToDouble();

double _drift(double value) => 0.5 + 0.5 * math.sin(value * _tau);

Offset _scatter(int index) => Offset(
  _fraction(0.11 + index * 0.7548777),
  _fraction(0.27 + index * 0.5698403),
);

void _radialWash(
  Canvas canvas,
  Offset center,
  double radius,
  Color inner,
  Color outer,
) {
  if (radius <= 0) return;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = ui.Gradient.radial(center, radius, <Color>[inner, outer]),
  );
}
