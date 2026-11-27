// Card background effects adapted from Sessions v6.0.0
// (https://github.com/MohammadAliUstad/Sessions, commit
// 8e0b7c211dbc31014e46ae231e0ae2d7f55bed1f), file
// app/src/main/java/com/yugentech/sessions/ui/dash/homeScreen/components/hero/
// HeroCardBackground.kt (blob 574817a86273adf8e586624dce8f19f691ccb418).
//
// Copyright 2026 YugenTech.
// Licensed under the Apache License, Version 2.0. A copy is kept in
// third_party/sessions/LICENSE-APACHE-2.0 and registered in
// card_effects_license.dart.
//
// Changes: the Kotlin/Compose draw routines were translated to Dart and ported
// to a Flutter CustomPainter; the themed and warm palettes were replaced by
// this app's monochrome surface roles; effect names were shortened; the effect
// clock is a Flutter Ticker; still frames for reduced motion and low power
// were added.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../design/appearance_preferences.dart';

/// Paints one card animation over the whole card area.
///
/// [time] is effect time in seconds and only advances while the card may move,
/// so a paused card keeps its exact frame. [progress] is the current block's
/// elapsed fraction and [isBreak] settles the scene into its rest state.
/// [active] is false only for a still frame (reduce-motion or low power): it
/// leaves out the wind, rain and embers, so a still card is distinct from a
/// paused one that keeps them. [ink] and [shade] are the two monochrome tones
/// the effect is drawn in, so it follows the app theme instead of importing a
/// palette; rain beads add a white specular glint, which is on the same neutral
/// axis.
class CardEffectPainter extends CustomPainter {
  const CardEffectPainter({
    required this.effect,
    required this.time,
    required this.progress,
    required this.isBreak,
    required this.active,
    required this.ink,
    required this.shade,
  });

  final FocusCardEffect effect;
  final double time;
  final double progress;
  final bool isBreak;
  final bool active;
  final Color ink;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (effect) {
      case FocusCardEffect.off:
        return;
      case FocusCardEffect.dunes:
        _drawDunes(canvas, size);
        return;
      case FocusCardEffect.rain:
        _drawRain(canvas, size);
        return;
      case FocusCardEffect.embers:
        _drawEmbers(canvas, size);
        return;
      case FocusCardEffect.aurora:
        _drawAurora(canvas, size);
        return;
      case FocusCardEffect.mesh:
        _drawMesh(canvas, size);
        return;
    }
  }

  // ───────────────────────────── Dunes ─────────────────────────────

  void _drawDunes(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double p = progress < 0
        ? 0.0
        : (progress > 1 ? 1.0 : progress);
    final double rest = isBreak ? 1.0 : 0.0;
    final double motion = active ? 1.0 : 0.0;

    if (rest > 0) {
      _verticalWash(
        canvas,
        Rect.fromLTWH(0, 0, w, h * 0.75),
        ink.withValues(alpha: 0.16 * rest),
        ink.withValues(alpha: 0),
      );
      for (var i = 0; i < 14; i++) {
        final Offset s = _scatter(i + 800);
        final double twinkle =
            0.5 + 0.5 * math.sin(time * (0.6 + 0.2 * (i % 3)) * _tau + i);
        canvas.drawCircle(
          Offset(s.dx * w, s.dy * h * 0.5),
          0.7 + (i % 3) * 0.3,
          _paint(ink.withValues(alpha: 0.45 * rest * twinkle)),
        );
      }
    }

    // The sun crosses with the block and sinks behind the dunes on a break.
    final Offset sun = Offset(
      w * (0.08 + 0.84 * p),
      h * (0.62 - 0.42 * math.sin(p * math.pi)) + h * 0.38 * rest,
    );
    final double sunRadius = h * 0.07;
    _radialWash(
      canvas,
      sun,
      sunRadius * 4.5,
      ink.withValues(alpha: 0.22),
      ink.withValues(alpha: 0),
    );
    canvas.drawCircle(sun, sunRadius, _paint(ink.withValues(alpha: 0.4)));

    for (var index = 0; index < _duneBands.length; index++) {
      final _DuneBand band = _duneBands[index];
      final double shift = time * band.drift;
      final Path dune = Path()..moveTo(0, h);
      for (var step = 0; step <= _steps; step++) {
        final double x = w * step / _steps;
        dune.lineTo(x, _duneTop(size, band, index, x, shift));
      }
      dune
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
        dune,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, h * (1 - band.height)),
            Offset(0, h),
            <Color>[
              ink.withValues(alpha: math.min(1.0, band.alpha * 1.3)),
              ink.withValues(alpha: band.alpha * 0.6),
            ],
          ),
      );
      if (index == _duneBands.length - 1) {
        final Path crest = Path();
        for (var step = 0; step <= _steps; step++) {
          final double x = w * step / _steps;
          final double y = _duneTop(size, band, index, x, shift);
          if (step == 0) {
            crest.moveTo(x, y);
          } else {
            crest.lineTo(x, y);
          }
        }
        canvas.drawPath(crest, _stroke(ink.withValues(alpha: 0.28), 1));
      }
    }

    if (motion <= 0) return;
    final _DuneBand front = _duneBands.last;
    final double frontShift = time * front.drift;
    for (var i = 0; i < 28; i++) {
      final Offset s = _scatter(i + 900);
      final double speed = 0.05 + 0.03 * (i % 3);
      final double q = _fraction(time * speed + s.dx);
      final double x = -10 + q * (w + 20);
      final double lift = (4 + s.dy * 14) * math.sin(q * math.pi);
      final double y =
          _duneTop(size, front, _duneBands.length - 1, x, frontShift) - lift;
      canvas.drawCircle(
        Offset(x, y),
        0.6 + (i % 3) * 0.3,
        _paint(ink.withValues(alpha: 0.4 * motion * _fadeThrough(q))),
      );
    }
    for (var i = 0; i < 3; i++) {
      final double q = _fraction(time * 0.035 + i / 3);
      final double x = -w * 0.3 + q * w * 1.6;
      final double y = h * (0.62 + 0.08 * i);
      final double length = w * 0.22;
      final Path wisp = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + length * 0.5, y - 6, x + length, y - 2);
      canvas.drawPath(
        wisp,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, y),
            Offset(x + length, y),
            <Color>[
              ink.withValues(alpha: 0),
              ink.withValues(alpha: 0.16 * motion),
              ink.withValues(alpha: 0),
            ],
            <double>[0.0, 0.5, 1.0],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  double _duneTop(Size size, _DuneBand band, int index, double x, double shift) {
    final double u = (x + shift) / size.width;
    final double swell =
        0.55 +
        0.30 * math.sin(u * _tau * band.swells + index * 1.7) +
        0.15 * math.sin(u * _tau * band.swells * 2.3 + index);
    return size.height - size.height * band.height * swell;
  }

  // ───────────────────────────── Rain ─────────────────────────────

  void _drawRain(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double rest = isBreak ? 1.0 : 0.0;
    final double motion = active ? 1.0 : 0.0;

    // Beyond the glass: thin, slanted and very faint.
    final double far = (1 - 0.6 * rest) * motion;
    if (far > 0) {
      for (var i = 0; i < 40; i++) {
        final Offset s = _scatter(i + 300);
        final double length = 10.0 + (i % 3) * 5;
        final double y =
            _fraction(time * (0.9 + 0.25 * (i % 4)) + s.dy) * (h + length) -
            length;
        final double x = s.dx * w + y * 0.12;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + length * 0.12, y + length),
          _stroke(ink.withValues(alpha: 0.10 * far), 0.7),
        );
      }
    }

    // Beads clinging to the glass.
    for (var i = 0; i < 46; i++) {
      final Offset s = _scatter(i + 60);
      _drawBead(canvas, Offset(s.dx * w, s.dy * h), 0.9 + (i % 5) * 0.55);
    }

    // Heavier drops sliding in fits and starts, each leaving a wet trail.
    const int dropCount = 7;
    final double shown = dropCount * (1 - 0.5 * rest);
    for (var i = 0; i < dropCount; i++) {
      final double strength = math.max(0.0, math.min(1.0, shown - i));
      if (strength <= 0) continue;
      final Offset s = _scatter(i + 400);
      final double period = 10.0 + (i % 3) * 4;
      final double phase = _fraction(time / period + s.dy);
      final double travel = phase - math.sin(phase * _tau * 3) / (_tau * 3);
      final double y = -8 + travel * (h + 16);
      final double originX = w * (0.05 + 0.9 * s.dx);
      double xAt(double yy) =>
          originX + math.sin(yy / h * _tau * 0.5 + i) * 0.8;
      final double r = 2.2 + (i % 3) * 0.7;
      final double trailTop = math.max(-8.0, y - h * 0.32);
      if (y > trailTop) {
        canvas.drawLine(
          Offset(xAt(trailTop), trailTop),
          Offset(xAt(y), y - r),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, trailTop),
              Offset(0, y),
              <Color>[
                ink.withValues(alpha: 0),
                ink.withValues(alpha: 0.10 * strength),
              ],
            )
            ..strokeWidth = 0.6
            ..strokeCap = StrokeCap.round,
        );
        for (var k = 1; k <= 6; k++) {
          final double ty = y - r - k * 7;
          if (ty <= trailTop) break;
          _drawBead(
            canvas,
            Offset(xAt(ty), ty),
            r * (0.42 - k * 0.04),
            strength * (1 - k / 7),
          );
        }
      }
      _drawDrop(canvas, Offset(xAt(y), y), r, strength);
    }
  }

  void _drawBead(Canvas canvas, Offset c, double r, [double alpha = 1.0]) {
    _radialWash(
      canvas,
      c,
      r,
      ink.withValues(alpha: 0.03 * alpha),
      ink.withValues(alpha: 0.20 * alpha),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      math.pi * 20 / 180,
      math.pi * 140 / 180,
      false,
      _stroke(ink.withValues(alpha: 0.32 * alpha), 0.6),
    );
    canvas.drawCircle(
      c + Offset(-r * 0.35, -r * 0.35),
      r * 0.3,
      _paint(Colors.white.withValues(alpha: 0.6 * alpha)),
    );
  }

  void _drawDrop(Canvas canvas, Offset c, double r, double alpha) {
    final Path drop = Path()
      ..moveTo(c.dx, c.dy - r * 1.45)
      ..quadraticBezierTo(c.dx + r * 1.02, c.dy - r * 0.85, c.dx + r, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), 0, math.pi, false)
      ..quadraticBezierTo(
        c.dx - r * 1.02,
        c.dy - r * 0.85,
        c.dx,
        c.dy - r * 1.45,
      )
      ..close();
    canvas.drawPath(
      drop,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r * 1.6,
          <Color>[
            ink.withValues(alpha: 0.06 * alpha),
            ink.withValues(alpha: 0.30 * alpha),
          ],
        ),
    );
    canvas.drawPath(drop, _stroke(ink.withValues(alpha: 0.40 * alpha), 0.7));
    canvas.drawCircle(
      c + Offset(-r * 0.35, -r * 0.2),
      r * 0.3,
      _paint(Colors.white.withValues(alpha: 0.7 * alpha)),
    );
  }

  // ───────────────────────────── Embers ─────────────────────────────

  void _drawEmbers(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    // Uneven flicker from slow waves on top of each other.
    final double motion = active ? 1.0 : 0.0;
    final double flicker =
        0.5 +
        0.25 * math.sin(time * 1.7 * _tau) +
        0.15 * math.sin(time * 2.9 * _tau + 1) +
        0.10 * math.sin(time * 4.3 * _tau + 2);
    final double strength = (0.45 + 0.55 * motion) * (0.85 + 0.15 * flicker);

    final Offset glowCentre = Offset(w * 0.62, h * 1.08);
    final double radius = w * (0.55 + 0.04 * flicker);
    _radialWash(
      canvas,
      glowCentre,
      radius,
      ink.withValues(alpha: 0.22 * strength),
      ink.withValues(alpha: 0),
    );
    final double heart = w * 0.22;
    _radialWash(
      canvas,
      glowCentre,
      heart,
      ink.withValues(alpha: 0.18 * strength),
      ink.withValues(alpha: 0),
    );

    if (motion <= 0) return;
    for (var i = 0; i < 16; i++) {
      final double p = _fraction(time * (0.12 + 0.05 * (i % 3)) + i / 16);
      final Offset start = _scatter(i);
      final Offset c = Offset(
        w * (0.62 + (start.dx - 0.5) * 0.6) +
            math.sin((p * 1.5 + start.dy) * _tau) * 10,
        h - p * h * 0.95,
      );
      final double glow = (1 - p) * math.min(p * 8, 1.0) * motion;
      final double r = 1.1 + (i % 3) * 0.5;
      canvas.drawCircle(c, r * 3, _paint(ink.withValues(alpha: 0.15 * glow)));
      canvas.drawCircle(c, r, _paint(ink.withValues(alpha: 0.55 * glow)));
    }
  }

  // ───────────────────────────── Aurora ─────────────────────────────

  void _drawAurora(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double rest = isBreak ? 1.0 : 0.0;
    final double motion = active ? 1.0 : 0.0;
    final double phase = time / _driftPeriod * _tau;
    final double strength = (0.55 + 0.45 * motion) * (1 - 0.35 * rest);
    final List<Color> tints = <Color>[
      ink.withValues(alpha: 0.30 * strength),
      shade.withValues(alpha: 0.24 + 0.08 * rest),
      ink.withValues(alpha: 0.20 * strength),
    ];
    for (var i = 0; i < tints.length; i++) {
      final Offset center = Offset(
        w * (0.5 + 0.38 * math.sin(phase + i * 2.1)),
        h * (0.5 + 0.34 * math.cos(phase + i * 1.3)),
      );
      final double radius = w * (0.34 + 0.05 * i);
      _radialWash(
        canvas,
        center,
        radius,
        tints[i],
        tints[i].withValues(alpha: 0),
      );
    }
  }

  // ───────────────────────────── Mesh ─────────────────────────────

  void _drawMesh(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double rest = isBreak ? 1.0 : 0.0;
    final double motion = active ? 1.0 : 0.0;
    final double phase = time / _driftPeriod * _tau;
    final double strength = (0.65 + 0.35 * motion) * (1 - 0.3 * rest);
    final List<Color> blobs = <Color>[
      ink.withValues(alpha: 0.30 * strength),
      shade.withValues(alpha: 0.26 * strength),
      ink.withValues(alpha: 0.20 * strength),
      ink.withValues(alpha: 0.14 * strength),
    ];
    for (var i = 0; i < blobs.length; i++) {
      final int xTurns = 1 + i % 2;
      final int yTurns = 1 + (i + 1) % 3;
      final Offset center = Offset(
        w * (0.5 + 0.42 * math.sin(phase * xTurns + i * 1.7)),
        h * (0.5 + 0.40 * math.cos(phase * yTurns + i * 2.3)),
      );
      final double radius = w * (0.38 + 0.06 * (i % 2));
      _radialWash(
        canvas,
        center,
        radius,
        blobs[i],
        blobs[i].withValues(alpha: 0),
      );
    }
    final Offset glow = Offset(w * (0.25 + 0.1 * math.sin(phase)), h * 0.2);
    _radialWash(
      canvas,
      glow,
      w * 0.3,
      ink.withValues(alpha: 0.16 * strength),
      ink.withValues(alpha: 0),
    );
  }

  @override
  bool shouldRepaint(covariant CardEffectPainter oldDelegate) =>
      oldDelegate.effect != effect ||
      oldDelegate.time != time ||
      oldDelegate.progress != progress ||
      oldDelegate.isBreak != isBreak ||
      oldDelegate.active != active ||
      oldDelegate.ink != ink ||
      oldDelegate.shade != shade;
}

// ───────────────────────────── Shared ─────────────────────────────

const double _tau = 2 * math.pi;
const double _driftPeriod = 24;
const int _steps = 40;

/// The fractional part, so a running value wraps into 0 to 1.
double _fraction(double value) => value - value.floorToDouble();

/// The [i]th point of an even but irregular-looking scatter, the same every
/// time.
Offset _scatter(int i) => Offset(
  _fraction(0.13 + i * 0.7548777),
  _fraction(0.29 + i * 0.5698403),
);

/// How visible something is at [p] through its run: fading in at the start and
/// out at the end.
double _fadeThrough(double p) =>
    math.min(p * 6, 1.0) * math.min((1 - p) * 6, 1.0);

Paint _paint(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

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

void _verticalWash(Canvas canvas, Rect rect, Color top, Color bottom) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(rect.left, rect.top),
        Offset(rect.left, rect.bottom),
        <Color>[top, bottom],
      ),
  );
}

class _DuneBand {
  const _DuneBand({
    required this.height,
    required this.swells,
    required this.alpha,
    required this.drift,
  });

  final double height;
  final double swells;
  final double alpha;
  final double drift;
}

const List<_DuneBand> _duneBands = <_DuneBand>[
  _DuneBand(height: 0.34, swells: 1.3, alpha: 0.08, drift: 2),
  _DuneBand(height: 0.25, swells: 1.9, alpha: 0.12, drift: 4),
  _DuneBand(height: 0.16, swells: 2.6, alpha: 0.18, drift: 7),
];
