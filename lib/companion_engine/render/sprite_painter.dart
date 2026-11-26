import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'atlas_cache.dart';
import 'companion_pose.dart';
import 'debug_geometry.dart';

/// Paints cached atlas regions with nearest-neighbour sampling. All layout and
/// animation state is supplied by [pose]; this class only composites.
class SpritePainter extends CustomPainter {
  SpritePainter({
    required this.pose,
    required this.atlas,
    required this.sceneSize,
    this.pixelScale = 1,
    this.background,
    this.showGrid = false,
    this.gridSpacing = 8,
    this.showPivots = false,
    this.showHitboxes = false,
    this.hitboxes = const <SpriteHitbox>[],
    this.overlayQuads = const <CompanionQuad>[],
    this.origin = ui.Offset.zero,
  });

  final CompanionPose pose;
  final AtlasCache atlas;
  final ui.Size sceneSize;
  final int pixelScale;

  /// `null` draws the transparency checker.
  final ui.Color? background;
  final bool showGrid;
  final double gridSpacing;
  final bool showPivots;
  final bool showHitboxes;
  final List<SpriteHitbox> hitboxes;
  final List<CompanionQuad> overlayQuads;
  final ui.Offset origin;

  static const _checkerLight = ui.Color(0xFFF3ECE2);
  static const _checkerDark = ui.Color(0xFFE2D8CB);
  static const _gridColor = ui.Color(0x335E5149);
  static const _pivotColor = ui.Color(0xFFD6533C);
  static const _hitboxColor = ui.Color(0xFF1E7B8C);
  static const _missingColor = ui.Color(0xFF9C2828);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.clipRect(ui.Offset.zero & size);
    _paintBackground(canvas, size);
    if (showGrid) _paintGrid(canvas);
    for (final quad in pose.quads) {
      _paintQuad(canvas, quad);
    }
    for (final quad in overlayQuads) {
      _paintQuad(canvas, quad);
    }
    if (showPivots) _paintPivots(canvas);
    if (showHitboxes) _paintHitboxes(canvas);
  }

  void _paintBackground(ui.Canvas canvas, ui.Size size) {
    final color = background;
    if (color != null) {
      canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = color);
      return;
    }
    canvas.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = _checkerLight,
    );
    const cell = 8.0;
    final darkPaint = ui.Paint()..color = _checkerDark;
    final columns = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if ((row + column).isEven) continue;
        canvas.drawRect(
          ui.Rect.fromLTWH(column * cell, row * cell, cell, cell),
          darkPaint,
        );
      }
    }
  }

  void _paintGrid(ui.Canvas canvas) {
    final paint = ui.Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final scale = pixelScale.toDouble();
    for (var x = 0.0; x <= sceneSize.width; x += gridSpacing) {
      final dx = origin.dx + x * scale;
      canvas.drawLine(
        ui.Offset(dx, origin.dy),
        ui.Offset(dx, origin.dy + sceneSize.height * scale),
        paint,
      );
    }
    for (var y = 0.0; y <= sceneSize.height; y += gridSpacing) {
      final dy = origin.dy + y * scale;
      canvas.drawLine(
        ui.Offset(origin.dx, dy),
        ui.Offset(origin.dx + sceneSize.width * scale, dy),
        paint,
      );
    }
  }

  void _paintQuad(ui.Canvas canvas, CompanionQuad quad) {
    final image = atlas.image(quad.region.atlas);
    if (image == null) {
      canvas.drawRect(
        _toScreen(quad.bounds),
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _missingColor,
      );
      return;
    }
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false
      ..color = ui.Color.fromRGBO(255, 255, 255, quad.opacity);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(pixelScale.toDouble());
    canvas.transform(quad.transform.storage());
    canvas.drawImageRect(
      image,
      quad.region.sourceRect,
      ui.Rect.fromLTWH(0, 0, quad.region.width.toDouble(), quad.region.height.toDouble()),
      paint,
    );
    canvas.restore();
  }

  void _paintPivots(ui.Canvas canvas) {
    final paint = ui.Paint()
      ..color = _pivotColor
      ..strokeWidth = 1.5;
    final fill = ui.Paint()..color = _pivotColor;
    for (final layer in pose.layers) {
      if (!layer.visible) continue;
      final point = _toScreenPoint(layer.pivot);
      canvas.drawLine(
        ui.Offset(point.dx - 4, point.dy),
        ui.Offset(point.dx + 4, point.dy),
        paint,
      );
      canvas.drawLine(
        ui.Offset(point.dx, point.dy - 4),
        ui.Offset(point.dx, point.dy + 4),
        paint,
      );
      canvas.drawCircle(point, 2, fill);
    }
  }

  void _paintHitboxes(ui.Canvas canvas) {
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _hitboxColor;
    for (final hitbox in hitboxes) {
      final rect = _toScreen(hitbox.rect);
      canvas.drawRect(rect, paint);
      final label = TextPainter(
        text: TextSpan(
          text: hitbox.label,
          style: const TextStyle(fontSize: 10, color: _hitboxColor),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      label.paint(canvas, ui.Offset(rect.left, rect.top - 12));
    }
  }

  ui.Rect _toScreen(ui.Rect rect) => ui.Rect.fromLTRB(
    origin.dx + rect.left * pixelScale,
    origin.dy + rect.top * pixelScale,
    origin.dx + rect.right * pixelScale,
    origin.dy + rect.bottom * pixelScale,
  );

  ui.Offset _toScreenPoint(ui.Offset point) => ui.Offset(
    origin.dx + point.dx * pixelScale,
    origin.dy + point.dy * pixelScale,
  );

  @override
  bool shouldRepaint(covariant SpritePainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.atlas != atlas ||
      oldDelegate.sceneSize != sceneSize ||
      oldDelegate.pixelScale != pixelScale ||
      oldDelegate.background != background ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.gridSpacing != gridSpacing ||
      oldDelegate.showPivots != showPivots ||
      oldDelegate.showHitboxes != showHitboxes ||
      oldDelegate.hitboxes != hitboxes ||
      oldDelegate.overlayQuads != overlayQuads ||
      oldDelegate.origin != origin;
}

/// Sizes a [SpritePainter] to the scene at an integer pixel scale.
class SpriteStage extends StatelessWidget {
  const SpriteStage({
    required this.pose,
    required this.atlas,
    required this.sceneSize,
    this.pixelScale = 1,
    this.background,
    this.showGrid = false,
    this.gridSpacing = 8,
    this.showPivots = false,
    this.showHitboxes = false,
    this.hitboxes = const <SpriteHitbox>[],
    this.overlayQuads = const <CompanionQuad>[],
    this.origin = ui.Offset.zero,
    super.key,
  });

  final CompanionPose pose;
  final AtlasCache atlas;
  final ui.Size sceneSize;
  final int pixelScale;
  final ui.Color? background;
  final bool showGrid;
  final double gridSpacing;
  final bool showPivots;
  final bool showHitboxes;
  final List<SpriteHitbox> hitboxes;
  final List<CompanionQuad> overlayQuads;
  final ui.Offset origin;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: sceneSize.width * pixelScale,
    height: sceneSize.height * pixelScale,
    child: CustomPaint(
      painter: SpritePainter(
        pose: pose,
        atlas: atlas,
        sceneSize: sceneSize,
        pixelScale: pixelScale,
        background: background,
        showGrid: showGrid,
        gridSpacing: gridSpacing,
        showPivots: showPivots,
        showHitboxes: showHitboxes,
        hitboxes: hitboxes,
        overlayQuads: overlayQuads,
        origin: origin,
      ),
    ),
  );
}
