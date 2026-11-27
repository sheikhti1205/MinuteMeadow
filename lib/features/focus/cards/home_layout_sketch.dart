import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/appearance_preferences.dart';

/// A small schematic of one Focus home layout.
///
/// The three sketches show where the timer, the card and the actions sit, so a
/// layout can be compared before it is applied. They are drawn from the app's
/// own neutral roles and contain no text or controls.
class HomeLayoutSketch extends StatelessWidget {
  const HomeLayoutSketch({required this.layout, super.key});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 0.62,
      child: CustomPaint(
        painter: _HomeLayoutSketchPainter(layout: layout, scheme: scheme),
      ),
    );
  }
}

class _HomeLayoutSketchPainter extends CustomPainter {
  const _HomeLayoutSketchPainter({required this.layout, required this.scheme});

  final HomeLayout layout;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final RRect frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(size.width * 0.14),
    );
    canvas.drawRRect(frame, Paint()..color = scheme.surfaceContainerLow);
    canvas.drawRRect(
      frame,
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke,
    );

    switch (layout) {
      case HomeLayout.classic:
        _classic(canvas, size);
        return;
      case HomeLayout.refined:
        _refined(canvas, size);
        return;
      case HomeLayout.studio:
        _studio(canvas, size);
        return;
    }
  }

  void _bar(
    Canvas canvas,
    Size size,
    double x,
    double y,
    double width,
    double height,
    Color color,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * x,
          size.height * y,
          size.width * width,
          size.height * height,
        ),
        Radius.circular(size.height * height / 2),
      ),
      Paint()..color = color,
    );
  }

  void _block(
    Canvas canvas,
    Size size,
    double x,
    double y,
    double width,
    double height,
    Color color, {
    double radius = 0.04,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * x,
          size.height * y,
          size.width * width,
          size.height * height,
        ),
        Radius.circular(size.width * radius),
      ),
      Paint()..color = color,
    );
  }

  void _ring(
    Canvas canvas,
    Size size,
    double centreY,
    double radius,
    Color track,
    Color fill,
  ) {
    final Offset centre = Offset(size.width / 2, size.height * centreY);
    final double r = size.width * radius;
    final double stroke = size.width * 0.045;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      -math.pi / 2,
      math.pi * 1.22,
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _classic(Canvas canvas, Size size) {
    _bar(canvas, size, 0.10, 0.055, 0.36, 0.022,
        scheme.onSurfaceVariant.withValues(alpha: 0.55));
    _block(canvas, size, 0.78, 0.045, 0.13, 0.032, scheme.surfaceContainerHigh,
        radius: 0.02);
    _ring(canvas, size, 0.30, 0.19, scheme.outlineVariant, scheme.primary);
    _bar(canvas, size, 0.38, 0.285, 0.24, 0.018,
        scheme.onSurface.withValues(alpha: 0.75));
    _bar(canvas, size, 0.42, 0.312, 0.16, 0.012,
        scheme.onSurfaceVariant.withValues(alpha: 0.5));
    _block(canvas, size, 0.09, 0.47, 0.38, 0.10, scheme.surfaceContainerHighest,
        radius: 0.03);
    _block(canvas, size, 0.53, 0.47, 0.38, 0.10, scheme.surfaceContainerHighest,
        radius: 0.03);
    _block(canvas, size, 0.10, 0.64, 0.16, 0.06, scheme.surfaceContainerHigh,
        radius: 0.03);
    _block(canvas, size, 0.32, 0.63, 0.36, 0.075, scheme.primary,
        radius: 0.038);
    _block(canvas, size, 0.74, 0.64, 0.16, 0.06, scheme.surfaceContainerHigh,
        radius: 0.03);
    for (var i = 0; i < 6; i++) {
      _block(canvas, size, 0.36 + i * 0.05, 0.765, 0.028, 0.012,
          scheme.outlineVariant, radius: 0.006);
    }
    _block(canvas, size, 0.14, 0.855, 0.72, 0.07, scheme.surfaceContainerHigh,
        radius: 0.035);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.32 + i * 0.18), size.height * 0.89),
        size.width * 0.018,
        Paint()
          ..color = i == 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }
  }

  void _refined(Canvas canvas, Size size) {
    _bar(canvas, size, 0.10, 0.06, 0.20, 0.018,
        scheme.onSurfaceVariant.withValues(alpha: 0.45));
    _bar(canvas, size, 0.10, 0.095, 0.46, 0.032,
        scheme.onSurface.withValues(alpha: 0.8));
    _block(canvas, size, 0.70, 0.072, 0.20, 0.045, scheme.surfaceContainerHigh,
        radius: 0.02);
    final Offset glow = Offset(size.width / 2, size.height * 0.34);
    canvas.drawCircle(
      glow,
      size.width * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: glow, radius: size.width * 0.34),
        ),
    );
    _ring(canvas, size, 0.34, 0.22, scheme.outlineVariant, scheme.primary);
    _bar(canvas, size, 0.40, 0.325, 0.20, 0.016,
        scheme.onSurface.withValues(alpha: 0.75));
    _block(canvas, size, 0.09, 0.56, 0.82, 0.15, scheme.surfaceContainerHigh,
        radius: 0.03);
    _bar(canvas, size, 0.16, 0.60, 0.55, 0.018,
        scheme.onSurface.withValues(alpha: 0.65));
    _bar(canvas, size, 0.16, 0.635, 0.38, 0.012,
        scheme.onSurfaceVariant.withValues(alpha: 0.45));
    _bar(canvas, size, 0.16, 0.672, 0.55, 0.008,
        scheme.primary.withValues(alpha: 0.4));
    _block(canvas, size, 0.32, 0.76, 0.36, 0.07, scheme.primary,
        radius: 0.038);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.32 + i * 0.18), size.height * 0.90),
        size.width * 0.018,
        Paint()
          ..color = i == 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }
  }

  void _studio(Canvas canvas, Size size) {
    _bar(canvas, size, 0.09, 0.05, 0.22, 0.016,
        scheme.onSurfaceVariant.withValues(alpha: 0.45));
    _bar(canvas, size, 0.09, 0.085, 0.50, 0.038,
        scheme.onSurface.withValues(alpha: 0.85));
    final Offset centre = Offset(size.width / 2, size.height * 0.38);
    final double face = size.width * 0.30;
    canvas.drawCircle(centre, face, Paint()..color = scheme.surfaceContainerHigh);
    canvas.drawCircle(
      centre,
      face * 0.78,
      Paint()..color = scheme.surfaceContainerLow,
    );
    canvas.drawCircle(
      centre,
      face,
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.012,
    );
    final Offset hand = centre + Offset(math.cos(-1.1), math.sin(-1.1)) * face * 0.6;
    canvas.drawLine(
      centre,
      hand,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = size.width * 0.017
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(hand, size.width * 0.03, Paint()..color = scheme.primary);
    _block(canvas, size, 0.14, 0.66, 0.72, 0.10, scheme.surfaceContainerHigh,
        radius: 0.035);
    canvas.drawCircle(
      Offset(size.width * 0.26, size.height * 0.71),
      size.width * 0.022,
      Paint()..color = scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.71),
      size.width * 0.036,
      Paint()..color = scheme.primary,
    );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.71),
      size.width * 0.022,
      Paint()..color = scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.85),
      size.width * 0.055,
      Paint()..color = scheme.primary,
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.85),
      size.width * 0.02,
      Paint()..color = scheme.surface,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeLayoutSketchPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.scheme != scheme;
}
