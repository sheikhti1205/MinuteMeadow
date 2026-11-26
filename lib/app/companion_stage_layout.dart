import 'dart:math' as math;
import 'dart:ui';

/// Size and physical-pixel snapping policy for a companion stage.
///
/// When the stage fits, one source pixel is drawn to a whole number of device
/// pixels. [align] then snaps scene-space coordinates to a crisp boundary so
/// nearest-neighbour sampling does not land between pixels.
final class CompanionStageLayout {
  const CompanionStageLayout({
    required this.scale,
    required this.deviceScale,
    required this.size,
    required this.offset,
  });

  /// Used when the viewport or scene has no drawable area.
  static const empty = CompanionStageLayout(
    scale: 0,
    deviceScale: 0,
    size: Size.zero,
    offset: Offset.zero,
  );

  factory CompanionStageLayout.fit({
    required Size viewport,
    required Size field,
    required double devicePixelRatio,
  }) {
    if (viewport.isEmpty ||
        field.isEmpty ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return empty;
    }
    final fit = math.min(
      viewport.width * devicePixelRatio / field.width,
      viewport.height * devicePixelRatio / field.height,
    );
    if (!fit.isFinite || fit <= 0) return empty;
    final deviceScale = fit >= 1 ? fit.floorToDouble() : fit;
    final scale = deviceScale / devicePixelRatio;
    final size = Size(field.width * scale, field.height * scale);
    final offset = Offset(
      ((viewport.width - size.width) * devicePixelRatio / 2).round() /
          devicePixelRatio,
      ((viewport.height - size.height) * devicePixelRatio / 2).round() /
          devicePixelRatio,
    );
    return CompanionStageLayout(
      scale: scale,
      deviceScale: deviceScale,
      size: size,
      offset: offset,
    );
  }

  /// Logical pixels per scene unit.
  final double scale;

  /// Device pixels per scene unit.
  final double deviceScale;

  /// Logical size of the drawn scene.
  final Size size;

  /// Physical-pixel aligned offset inside the viewport.
  final Offset offset;

  bool get isPixelAligned =>
      deviceScale > 0 && deviceScale == deviceScale.roundToDouble();

  /// Snaps [value] to the nearest crisp boundary in scene units.
  ///
  /// With a whole [deviceScale] this rounds to a source-pixel edge so every
  /// sprite pixel keeps the same physical width. Otherwise it snaps to the
  /// nearest device pixel.
  double align(double value) {
    if (deviceScale <= 0) return value;
    if (isPixelAligned) return value.roundToDouble();
    return (value * deviceScale).roundToDouble() / deviceScale;
  }

  @override
  bool operator ==(Object other) =>
      other is CompanionStageLayout &&
      scale == other.scale &&
      deviceScale == other.deviceScale &&
      size == other.size &&
      offset == other.offset;

  @override
  int get hashCode => Object.hash(scale, deviceScale, size, offset);
}
