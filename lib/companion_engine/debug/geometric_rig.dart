import 'dart:ui' as ui;

import '../rig/rig_model.dart';

final class GeometricRigBundle {
  const GeometricRigBundle({
    required this.rig,
    required this.atlasId,
    required this.atlasImage,
  });

  final CompanionRig rig;
  final String atlasId;
  final ui.Image atlasImage;
}

/// A development-only geometric rig. It exercises the compositor, parenting,
/// pivots, independent frame tracks and keyframes without shipping pet art.
abstract final class GeometricRigFixture {
  static const String atlasId = 'geometric';

  static const AtlasDefinition atlas = AtlasDefinition(
    id: atlasId,
    width: 160,
    height: 96,
    imageKey: 'geometric',
  );

  static const SpriteRegion bodyRegion = SpriteRegion(
    atlas: atlasId,
    x: 0,
    y: 0,
    width: 24,
    height: 20,
  );
  static const SpriteRegion headRegion = SpriteRegion(
    atlas: atlasId,
    x: 24,
    y: 0,
    width: 22,
    height: 18,
  );
  static const SpriteRegion earRegion = SpriteRegion(
    atlas: atlasId,
    x: 46,
    y: 0,
    width: 10,
    height: 10,
  );
  static const SpriteRegion tailRegion = SpriteRegion(
    atlas: atlasId,
    x: 56,
    y: 0,
    width: 18,
    height: 10,
  );
  static const SpriteRegion legRegion = SpriteRegion(
    atlas: atlasId,
    x: 74,
    y: 0,
    width: 8,
    height: 12,
  );
  static const SpriteRegion eyeOpenRegion = SpriteRegion(
    atlas: atlasId,
    x: 82,
    y: 0,
    width: 8,
    height: 4,
  );
  static const SpriteRegion eyeClosedRegion = SpriteRegion(
    atlas: atlasId,
    x: 90,
    y: 0,
    width: 8,
    height: 4,
  );
  static const SpriteRegion ballRegion = SpriteRegion(
    atlas: atlasId,
    x: 98,
    y: 0,
    width: 12,
    height: 12,
  );

  static CompanionRig buildRig() => CompanionRig(
    canvasWidth: 64,
    canvasHeight: 64,
    atlases: const <String, AtlasDefinition>{atlasId: atlas},
    layers: const <LayerDefinition>[
      LayerDefinition(
        id: 'tail',
        parent: 'body',
        defaultFrame: tailRegion,
        offset: ui.Offset(-16, 4),
        pivot: ui.Offset(18, 5),
      ),
      LayerDefinition(
        id: 'legBack',
        parent: 'body',
        defaultFrame: legRegion,
        offset: ui.Offset(13, 16),
        pivot: ui.Offset(4, 0),
        opacity: 0.9,
      ),
      LayerDefinition(
        id: 'body',
        defaultFrame: bodyRegion,
        offset: ui.Offset(20, 32),
        pivot: ui.Offset(12, 20),
      ),
      LayerDefinition(
        id: 'legFront',
        parent: 'body',
        defaultFrame: legRegion,
        offset: ui.Offset(3, 16),
        pivot: ui.Offset(4, 0),
      ),
      LayerDefinition(
        id: 'head',
        parent: 'body',
        defaultFrame: headRegion,
        offset: ui.Offset(1, -16),
        pivot: ui.Offset(11, 18),
      ),
      LayerDefinition(
        id: 'earLeft',
        parent: 'head',
        defaultFrame: earRegion,
        offset: ui.Offset(2, -6),
        pivot: ui.Offset(5, 10),
        rotationDegrees: -12,
      ),
      LayerDefinition(
        id: 'earRight',
        parent: 'head',
        defaultFrame: earRegion,
        offset: ui.Offset(10, -6),
        pivot: ui.Offset(5, 10),
        rotationDegrees: 12,
      ),
      LayerDefinition(
        id: 'eye',
        parent: 'head',
        defaultFrame: eyeOpenRegion,
        offset: ui.Offset(7, 8),
        pivot: ui.Offset(4, 2),
      ),
    ],
    clips: <String, ClipDefinition>{
      'idle': ClipDefinition(
        id: 'idle',
        durationMs: 1600,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.scaleY,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 1),
                  Keyframe(timeMs: 800, value: 1.03),
                  Keyframe(timeMs: 1600, value: 1),
                ],
              ),
              PropertyTrack(
                property: LayerProperty.offsetY,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 32),
                  Keyframe(timeMs: 800, value: 33),
                  Keyframe(timeMs: 1600, value: 32),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'tail',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: -18),
                  Keyframe(timeMs: 400, value: 14),
                  Keyframe(timeMs: 800, value: -18),
                  Keyframe(timeMs: 1200, value: 14),
                  Keyframe(timeMs: 1600, value: -18),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'earLeft',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: -12),
                  Keyframe(timeMs: 300, value: -20),
                  Keyframe(timeMs: 600, value: -12),
                  Keyframe(timeMs: 900, value: -20),
                  Keyframe(timeMs: 1200, value: -12),
                  Keyframe(timeMs: 1600, value: -12),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'eye',
            frames: FrameTrack(
              frames: const <SpriteRegion>[
                eyeOpenRegion,
                eyeOpenRegion,
                eyeOpenRegion,
                eyeClosedRegion,
              ],
              frameDurationMs: 200,
            ),
          ),
        ],
      ),
      'walk': ClipDefinition(
        id: 'walk',
        durationMs: 700,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetY,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 32),
                  Keyframe(timeMs: 175, value: 30.5),
                  Keyframe(timeMs: 350, value: 32),
                  Keyframe(timeMs: 525, value: 30.5),
                  Keyframe(timeMs: 700, value: 32),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'legFront',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 18),
                  Keyframe(timeMs: 175, value: -18),
                  Keyframe(timeMs: 350, value: 18),
                  Keyframe(timeMs: 525, value: -18),
                  Keyframe(timeMs: 700, value: 18),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'legBack',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: -18),
                  Keyframe(timeMs: 175, value: 18),
                  Keyframe(timeMs: 350, value: -18),
                  Keyframe(timeMs: 525, value: 18),
                  Keyframe(timeMs: 700, value: -18),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'tail',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: -10),
                  Keyframe(timeMs: 175, value: 10),
                  Keyframe(timeMs: 350, value: -10),
                  Keyframe(timeMs: 525, value: 10),
                  Keyframe(timeMs: 700, value: -10),
                ],
              ),
            ],
          ),
        ],
      ),
      'pet': ClipDefinition(
        id: 'pet',
        durationMs: 900,
        loop: false,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'head',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 0),
                  Keyframe(timeMs: 150, value: -6),
                  Keyframe(timeMs: 300, value: 6),
                  Keyframe(timeMs: 450, value: -6),
                  Keyframe(timeMs: 600, value: 6),
                  Keyframe(timeMs: 750, value: -3),
                  Keyframe(timeMs: 900, value: 0),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.scaleY,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 1),
                  Keyframe(timeMs: 300, value: 0.96),
                  Keyframe(timeMs: 600, value: 1.02),
                  Keyframe(timeMs: 900, value: 1),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'tail',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 0),
                  Keyframe(timeMs: 300, value: 25),
                  Keyframe(timeMs: 600, value: -10),
                  Keyframe(timeMs: 900, value: 0),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'earLeft',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: -12),
                  Keyframe(timeMs: 300, value: -25),
                  Keyframe(timeMs: 600, value: -12),
                  Keyframe(timeMs: 900, value: -12),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'eye',
            frames: FrameTrack(
              frames: const <SpriteRegion>[eyeClosedRegion],
              frameDurationMs: 900,
              loop: false,
            ),
          ),
        ],
      ),
      'hop': ClipDefinition(
        id: 'hop',
        durationMs: 520,
        loop: false,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetY,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 32),
                  Keyframe(timeMs: 120, value: 23),
                  Keyframe(timeMs: 260, value: 32),
                  Keyframe(timeMs: 380, value: 29),
                  Keyframe(timeMs: 520, value: 32),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'legFront',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 0),
                  Keyframe(timeMs: 120, value: 25),
                  Keyframe(timeMs: 260, value: 0),
                  Keyframe(timeMs: 520, value: 0),
                ],
              ),
            ],
          ),
          LayerClip(
            layerId: 'legBack',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.rotationDegrees,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 0),
                  Keyframe(timeMs: 120, value: -25),
                  Keyframe(timeMs: 260, value: 0),
                  Keyframe(timeMs: 520, value: 0),
                ],
              ),
            ],
          ),
        ],
      ),
    },
    defaultClip: 'idle',
  );

  static Future<GeometricRigBundle> create() async {
    final image = await _paintAtlas();
    return GeometricRigBundle(
      rig: buildRig(),
      atlasId: atlasId,
      atlasImage: image,
    );
  }

  static Future<ui.Image> _paintAtlas() async {
    const size = ui.Size(160, 96);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
    );
    const ink = ui.Color(0xFF3A2A1F);
    const fur = ui.Color(0xFFB97A4E);
    const furLight = ui.Color(0xFFD59A6C);
    const cream = ui.Color(0xFFF0D2AF);
    const innerEar = ui.Color(0xFFE59C93);
    const legColor = ui.Color(0xFF9E623D);
    const eyeColor = ui.Color(0xFF241A14);
    const ball = ui.Color(0xFFD6533C);
    const highlight = ui.Color(0xFFFFE8C9);

    _framedRect(canvas, bodyRegion, fur, ink);
    _fillRect(canvas, 5, 12, 14, 5, cream);
    _framedRect(canvas, headRegion, furLight, ink);
    _fillRect(canvas, 32, 11, 4, 2, cream);
    _framedTriangle(canvas, earRegion, fur, ink);
    _fillRect(canvas, 48, 6, 6, 2, innerEar);
    _framedRect(canvas, tailRegion, fur, ink);
    _fillRect(canvas, 66, 2, 5, 5, cream);
    _framedRect(canvas, legRegion, legColor, ink);
    _fillRect(canvas, 75, 8, 6, 3, cream);
    _fillRect(canvas, 83, 1, 2, 2, eyeColor);
    _fillRect(canvas, 87, 1, 2, 2, eyeColor);
    _fillRect(canvas, 91, 2, 2, 1, eyeColor);
    _fillRect(canvas, 95, 2, 2, 1, eyeColor);
    canvas.drawCircle(
      const ui.Offset(104, 6),
      5,
      ui.Paint()..color = ball,
    );
    canvas.drawCircle(
      const ui.Offset(104, 6),
      5,
      ui.Paint()
        ..color = ink
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
    _fillRect(canvas, 101, 3, 2, 2, highlight);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(160, 96);
    } finally {
      picture.dispose();
    }
  }

  static void _framedRect(
    ui.Canvas canvas,
    SpriteRegion region,
    ui.Color fill,
    ui.Color outline,
  ) {
    final rect = ui.Rect.fromLTWH(
      region.x.toDouble() + 0.5,
      region.y.toDouble() + 0.5,
      region.width.toDouble() - 1,
      region.height.toDouble() - 1,
    );
    canvas.drawRect(
      rect,
      ui.Paint()
        ..color = fill
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      rect,
      ui.Paint()
        ..color = outline
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  static void _framedTriangle(
    ui.Canvas canvas,
    SpriteRegion region,
    ui.Color fill,
    ui.Color outline,
  ) {
    final path = ui.Path()
      ..moveTo(region.x + 1.0, region.y + region.height - 1.0)
      ..lineTo(region.x + region.width / 2, region.y + 1.0)
      ..lineTo(region.x + region.width - 1.0, region.y + region.height - 1.0)
      ..close();
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = fill
        ..isAntiAlias = false,
    );
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = outline
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  static void _fillRect(
    ui.Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    ui.Color color,
  ) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x, y, width, height),
      ui.Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }
}
