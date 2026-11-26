import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A 2D affine transform:
/// `x' = a*x + c*y + tx`, `y' = b*x + d*y + ty`.
///
/// Kept independent of Flutter's matrix types so pose composition can be
/// tested without a graphics context.
final class Affine2 {
  const Affine2(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const Affine2 identity = Affine2(1, 0, 0, 1, 0, 0);

  factory Affine2.translation(double dx, double dy) =>
      Affine2(1, 0, 0, 1, dx, dy);

  factory Affine2.scale(double sx, double sy) => Affine2(sx, 0, 0, sy, 0, 0);

  factory Affine2.rotation(double radians) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return Affine2(cosine, sine, -sine, cosine, 0, 0);
  }

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  /// Returns `this * other`: [other] is applied first.
  Affine2 operator *(Affine2 other) => Affine2(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.tx + c * other.ty + tx,
    b * other.tx + d * other.ty + ty,
  );

  Offset transform(Offset point) => Offset(
    a * point.dx + c * point.dy + tx,
    b * point.dx + d * point.dy + ty,
  );

  Rect transformRect(Rect rect) {
    final p1 = transform(rect.topLeft);
    final p2 = transform(rect.topRight);
    final p3 = transform(rect.bottomRight);
    final p4 = transform(rect.bottomLeft);
    final minX = math.min(math.min(p1.dx, p2.dx), math.min(p3.dx, p4.dx));
    final maxX = math.max(math.max(p1.dx, p2.dx), math.max(p3.dx, p4.dx));
    final minY = math.min(math.min(p1.dy, p2.dy), math.min(p3.dy, p4.dy));
    final maxY = math.max(math.max(p1.dy, p2.dy), math.max(p3.dy, p4.dy));
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Column-major storage for `Canvas.transform`.
  Float64List storage() => Float64List.fromList(<double>[
    a,
    b,
    0,
    0,
    c,
    d,
    0,
    0,
    0,
    0,
    1,
    0,
    tx,
    ty,
    0,
    1,
  ]);

  @override
  bool operator ==(Object other) =>
      other is Affine2 &&
      a == other.a &&
      b == other.b &&
      c == other.c &&
      d == other.d &&
      tx == other.tx &&
      ty == other.ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Affine2($a, $b, $c, $d, $tx, $ty)';
}
