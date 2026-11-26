import 'dart:ui';

import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:companion_focus/companion_engine/rig/rig_model.dart';
import 'package:companion_focus/companion_engine/rig/rig_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const _atlas = AtlasDefinition(id: 'main', width: 64, height: 32);
const _bodyFrame = SpriteRegion(
  atlas: 'main',
  x: 0,
  y: 0,
  width: 16,
  height: 16,
);
const _headFrame = SpriteRegion(
  atlas: 'main',
  x: 16,
  y: 0,
  width: 12,
  height: 12,
);

CompanionRig _rig({
  Map<String, AtlasDefinition>? atlases,
  List<LayerDefinition>? layers,
  Map<String, ClipDefinition>? clips,
  String? defaultClip = 'idle',
  int canvasWidth = 64,
  int canvasHeight = 64,
  int schemaVersion = CompanionRig.currentSchemaVersion,
}) => CompanionRig(
  schemaVersion: schemaVersion,
  canvasWidth: canvasWidth,
  canvasHeight: canvasHeight,
  atlases: atlases ?? const <String, AtlasDefinition>{'main': _atlas},
  layers: layers ??
      const <LayerDefinition>[
        LayerDefinition(
          id: 'body',
          defaultFrame: _bodyFrame,
          offset: Offset(8, 8),
          pivot: Offset(8, 16),
        ),
        LayerDefinition(
          id: 'head',
          parent: 'body',
          defaultFrame: _headFrame,
          offset: Offset(2, -10),
          pivot: Offset(6, 12),
        ),
      ],
  clips: clips ?? <String, ClipDefinition>{'idle': _idleClip()},
  defaultClip: defaultClip,
);

ClipDefinition _idleClip() => ClipDefinition(
  id: 'idle',
  durationMs: 1000,
  layers: <LayerClip>[
    LayerClip(
      layerId: 'body',
      frames: FrameTrack(
        frames: const <SpriteRegion>[_bodyFrame, _headFrame],
        frameDurationMs: 200,
      ),
      tracks: <PropertyTrack>[
        PropertyTrack(
          property: LayerProperty.rotationDegrees,
          keyframes: const <Keyframe>[
            Keyframe(timeMs: 0, value: 0),
            Keyframe(timeMs: 500, value: 10),
            Keyframe(timeMs: 1000, value: 0),
          ],
        ),
      ],
    ),
  ],
);

List<String> _messages(CompanionRig rig) =>
    RigValidator.validate(rig).map((issue) => issue.message).toList();

void main() {
  test('accepts the geometric development rig', () {
    expect(RigValidator.validate(GeometricRigFixture.buildRig()), isEmpty);
  });

  test('accepts a declared rig', () {
    expect(RigValidator.validate(_rig()), isEmpty);
  });

  test('rejects an unsupported schema version', () {
    expect(
      _messages(_rig(schemaVersion: 2)),
      contains(contains('Unsupported schema version')),
    );
  });

  test('rejects duplicate layer ids', () {
    final rig = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(id: 'body', defaultFrame: _bodyFrame),
        LayerDefinition(id: 'body', defaultFrame: _headFrame),
      ],
    );
    expect(_messages(rig), contains(contains('Duplicate layer id')));
  });

  test('rejects unknown parents and parent cycles', () {
    final unknown = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'body',
          parent: 'missing',
          defaultFrame: _bodyFrame,
        ),
      ],
    );
    expect(_messages(unknown), contains(contains('Unknown parent')));

    final cycle = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'body',
          parent: 'head',
          defaultFrame: _bodyFrame,
        ),
        LayerDefinition(
          id: 'head',
          parent: 'body',
          defaultFrame: _headFrame,
        ),
      ],
    );
    expect(_messages(cycle), contains(contains('Parent cycle')));
  });

  test('rejects frames outside their atlas', () {
    final rig = _rig(
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'body',
          defaultFrame: SpriteRegion(
            atlas: 'main',
            x: 60,
            y: 0,
            width: 16,
            height: 16,
          ),
        ),
        LayerDefinition(
          id: 'head',
          defaultFrame: SpriteRegion(
            atlas: 'missing',
            x: 0,
            y: 0,
            width: 4,
            height: 4,
          ),
        ),
      ],
    );
    final messages = _messages(rig);
    expect(messages, contains(contains('does not fit atlas')));
    expect(messages, contains(contains('unknown atlas')));
  });

  test('rejects clips that reference unknown layers', () {
    final rig = _rig(
      clips: <String, ClipDefinition>{
        'idle': ClipDefinition(
          id: 'idle',
          durationMs: 100,
          layers: <LayerClip>[LayerClip(layerId: 'missing')],
        ),
      },
    );
    expect(_messages(rig), contains(contains('Unknown layer')));
  });

  test('rejects malformed keyframes', () {
    final rig = _rig(
      clips: <String, ClipDefinition>{
        'idle': ClipDefinition(
          id: 'idle',
          durationMs: 100,
          layers: <LayerClip>[
            LayerClip(
              layerId: 'body',
              tracks: <PropertyTrack>[
                PropertyTrack(
                  property: LayerProperty.opacity,
                  keyframes: const <Keyframe>[
                    Keyframe(timeMs: 50, value: 2),
                    Keyframe(timeMs: 20, value: 1),
                    Keyframe(timeMs: 200, value: 1),
                  ],
                ),
                PropertyTrack(
                  property: LayerProperty.scaleX,
                  keyframes: const <Keyframe>[
                    Keyframe(timeMs: 0, value: 0),
                  ],
                ),
              ],
            ),
          ],
        ),
      },
    );
    final messages = _messages(rig);
    expect(messages, contains(contains('between 0 and 1')));
    expect(messages, contains(contains('must increase')));
    expect(messages, contains(contains('outside the clip')));
    expect(messages, contains(contains('Scale must be positive')));
  });

  test('rejects unknown and empty structure', () {
    expect(
      _messages(_rig(defaultClip: 'missing')),
      contains(contains('Unknown clip')),
    );
    expect(
      _messages(_rig(layers: const <LayerDefinition>[])),
      contains(contains('At least one layer')),
    );
    expect(
      _messages(
        _rig(
          atlases: const <String, AtlasDefinition>{
            'main': AtlasDefinition(id: 'main', width: 0, height: 0),
          },
        ),
      ),
      contains(contains('Width and height must be positive')),
    );
    expect(
      _messages(_rig(canvasWidth: 0)),
      contains(contains('Width and height must be positive')),
    );
  });
}
