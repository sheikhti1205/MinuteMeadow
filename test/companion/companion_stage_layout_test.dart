import 'dart:ui';

import 'package:companion_focus/app/companion_stage_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stage uses whole device pixels and an aligned origin when it fits', () {
    final layout = CompanionStageLayout.fit(
      viewport: const Size(200, 200),
      field: const Size(144, 96),
      devicePixelRatio: 3,
    );

    expect(layout.deviceScale, 4);
    expect(layout.scale, closeTo(4 / 3, 1e-9));
    expect(layout.size.width, closeTo(192, 1e-9));
    expect(layout.size.height, closeTo(128, 1e-9));
    expect(layout.offset, const Offset(4, 36));
    expect(layout.isPixelAligned, isTrue);
    expect(layout.align(10.4), 10);
    expect(layout.align(10.6), 11);
  });

  test('stage falls back to device-pixel snapping when it must shrink', () {
    final layout = CompanionStageLayout.fit(
      viewport: const Size(50, 50),
      field: const Size(144, 96),
      devicePixelRatio: 1,
    );

    expect(layout.isPixelAligned, isFalse);
    expect(layout.deviceScale, closeTo(50 / 144, 1e-9));
    expect(layout.align(10) * layout.deviceScale, closeTo(3, 1e-9));
  });

  test('stage origin lands on a device pixel at fractional ratios', () {
    final layout = CompanionStageLayout.fit(
      viewport: const Size(321, 201),
      field: const Size(144, 96),
      devicePixelRatio: 2.625,
    );

    final x = layout.offset.dx * 2.625;
    final y = layout.offset.dy * 2.625;
    expect(x, closeTo(x.roundToDouble(), 1e-9));
    expect(y, closeTo(y.roundToDouble(), 1e-9));
  });

  test('empty viewport produces no drawable stage', () {
    final layout = CompanionStageLayout.fit(
      viewport: Size.zero,
      field: const Size(144, 96),
      devicePixelRatio: 1,
    );

    expect(layout.scale, 0);
    expect(layout.deviceScale, 0);
    expect(layout.size, Size.zero);
  });
}
