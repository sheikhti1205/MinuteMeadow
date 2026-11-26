import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:companion_focus/companion_engine/rig/rig_codec.dart';
import 'package:companion_focus/companion_engine/rig/rig_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _minimalJson() => <String, Object?>{
  'schemaVersion': 1,
  'canvas': <String, Object?>{'width': 64, 'height': 64},
  'atlases': <Object?>[
    <String, Object?>{'id': 'main', 'width': 32, 'height': 32},
  ],
  'layers': <Object?>[
    <String, Object?>{
      'id': 'body',
      'frame': <String, Object?>{
        'atlas': 'main',
        'x': 0,
        'y': 0,
        'width': 8,
        'height': 8,
      },
    },
  ],
  'clips': <Object?>[
    <String, Object?>{'id': 'idle', 'durationMs': 100},
  ],
  'defaultClip': 'idle',
};

void main() {
  test('round-trips the geometric rig through versioned JSON', () {
    final rig = GeometricRigFixture.buildRig();
    final decoded = RigCodec.decode(RigCodec.encode(rig));
    expect(RigCodec.toJson(decoded), equals(RigCodec.toJson(rig)));
    expect(decoded.defaultClip, 'idle');
    expect(decoded.layers, hasLength(rig.layers.length));
    expect(decoded.clips.keys, containsAll(<String>['idle', 'walk', 'pet']));
  });

  test('applies optional field defaults', () {
    final decoded = RigCodec.decodeJson(_minimalJson());
    final layer = decoded.layers.single;
    expect(layer.offset, Offset.zero);
    expect(layer.pivot, Offset.zero);
    expect(layer.rotationDegrees, 0);
    expect(layer.scale, const Offset(1, 1));
    expect(layer.opacity, 1);
    expect(layer.visible, isTrue);
    expect(decoded.clips['idle']?.loop, isTrue);
    expect(decoded.clips['idle']?.layers, isEmpty);
  });

  test('rejects unknown fields with a path', () {
    final json = _minimalJson()..['extra'] = true;
    expect(
      () => RigCodec.decodeJson(json),
      throwsA(isA<RigFormatException>().having(
        (error) => error.path,
        'path',
        r'$',
      )),
    );
  });

  test('rejects an unsupported schema version', () {
    final json = _minimalJson()..['schemaVersion'] = 2;
    expect(
      () => RigCodec.decodeJson(json),
      throwsA(isA<RigFormatException>().having(
        (error) => error.message,
        'message',
        contains('Unsupported schema version'),
      )),
    );
  });

  test('rejects duplicate atlas and clip ids', () {
    final atlasJson = _minimalJson();
    atlasJson['atlases'] = <Object?>[
      <String, Object?>{'id': 'main', 'width': 32, 'height': 32},
      <String, Object?>{'id': 'main', 'width': 32, 'height': 32},
    ];
    expect(
      () => RigCodec.decodeJson(atlasJson),
      throwsA(isA<RigFormatException>()),
    );

    final clipJson = _minimalJson();
    clipJson['clips'] = <Object?>[
      <String, Object?>{'id': 'idle', 'durationMs': 100},
      <String, Object?>{'id': 'idle', 'durationMs': 100},
    ];
    expect(
      () => RigCodec.decodeJson(clipJson),
      throwsA(isA<RigFormatException>()),
    );
  });

  test('rejects malformed JSON and missing required fields', () {
    expect(() => RigCodec.decode('{'), throwsA(isA<RigFormatException>()));
    final json = _minimalJson()..remove('layers');
    expect(
      () => RigCodec.decodeJson(json),
      throwsA(isA<RigFormatException>()),
    );
  });

  test('throws semantic validation issues after decoding', () {
    final json = _minimalJson();
    json['layers'] = <Object?>[
      <String, Object?>{
        'id': 'body',
        'frame': <String, Object?>{
          'atlas': 'main',
          'x': 0,
          'y': 0,
          'width': 8,
          'height': 8,
        },
      },
      <String, Object?>{
        'id': 'body',
        'frame': <String, Object?>{
          'atlas': 'main',
          'x': 0,
          'y': 0,
          'width': 8,
          'height': 8,
        },
      },
    ];
    expect(
      () => RigCodec.decodeJson(json),
      throwsA(isA<RigValidationException>().having(
        (error) => error.issues,
        'issues',
        isNotEmpty,
      )),
    );
  });
}
