import 'dart:typed_data';

import 'package:companion_focus/companion_engine/debug/rig_file_loader.dart';
import 'package:companion_focus/companion_engine/rig/manifest_inspection.dart';
import 'package:companion_focus/companion_engine/rig/rig_codec.dart';
import 'package:companion_focus/companion_engine/rig/rig_model.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = SpriteRegion(
  atlas: 'main',
  x: 0,
  y: 0,
  width: 8,
  height: 8,
);

CompanionRig _rig({
  List<LayerDefinition>? layers,
  Map<String, AtlasDefinition>? atlases,
}) => CompanionRig(
  canvasWidth: 64,
  canvasHeight: 64,
  atlases: atlases ??
      const <String, AtlasDefinition>{
        'main': AtlasDefinition(id: 'main', width: 32, height: 32),
      },
  layers: layers ??
      const <LayerDefinition>[
        LayerDefinition(id: 'body', defaultFrame: _frame),
      ],
  clips: const <String, ClipDefinition>{},
);

void main() {
  group('RigManifestInspection', () {
    test('accepts a valid manifest and keeps its raw text', () {
      final raw = RigCodec.encode(_rig());
      final inspection = RigManifestInspection.inspect(raw);

      expect(inspection.isValid, isTrue);
      expect(inspection.rig, isNotNull);
      expect(inspection.schemaVersion, CompanionRig.currentSchemaVersion);
      expect(inspection.issues, isEmpty);
      expect(inspection.raw, raw);
    });

    test('reports a JSON path for malformed text', () {
      final inspection = RigManifestInspection.inspect('{');

      expect(inspection.isValid, isFalse);
      expect(inspection.rig, isNull);
      expect(inspection.schemaVersion, isNull);
      expect(inspection.issues, hasLength(1));
      expect(inspection.issues.single.location, r'$');
      expect(inspection.issues.single.message, contains('Invalid JSON'));
    });

    test('keeps every semantic issue for an invalid rig', () {
      final raw = RigCodec.encode(
        _rig(
          layers: const <LayerDefinition>[
            LayerDefinition(id: 'body', defaultFrame: _frame),
            LayerDefinition(id: 'body', defaultFrame: _frame),
          ],
        ),
      );
      final inspection = RigManifestInspection.inspect(raw);

      expect(inspection.isValid, isFalse);
      expect(
        inspection.issues.map((issue) => issue.message),
        contains(contains('Duplicate layer id')),
      );
    });
  });

  group('RigFileLoader.resolveAtlasId', () {
    const atlases = <String, AtlasDefinition>{
      'cat': AtlasDefinition(
        id: 'cat',
        width: 32,
        height: 32,
        imageKey: 'cat-sheet.png',
      ),
      'dog': AtlasDefinition(
        id: 'dog',
        width: 32,
        height: 32,
        imageKey: 'dog-sheet.png',
      ),
    };

    final rig = _rig(
      atlases: atlases,
      layers: const <LayerDefinition>[
        LayerDefinition(
          id: 'body',
          defaultFrame: SpriteRegion(
            atlas: 'cat',
            x: 0,
            y: 0,
            width: 8,
            height: 8,
          ),
        ),
      ],
    );

    test('matches an image key, atlas id or file stem', () {
      expect(
        RigFileLoader.resolveAtlasId(
          rig,
          'cat-sheet.png',
          loadedAtlasIds: const <String>{},
        ),
        'cat',
      );
      expect(
        RigFileLoader.resolveAtlasId(
          rig,
          'dog',
          loadedAtlasIds: const <String>{},
        ),
        'dog',
      );
      expect(
        RigFileLoader.resolveAtlasId(
          rig,
          'dog.png',
          loadedAtlasIds: const <String>{},
        ),
        'dog',
      );
    });

    test('falls back to the only atlas that is still missing', () {
      expect(
        RigFileLoader.resolveAtlasId(
          rig,
          'unrelated.png',
          loadedAtlasIds: const <String>{'cat'},
        ),
        'dog',
      );
      expect(
        RigFileLoader.resolveAtlasId(
          _rig(),
          'anything.webp',
          loadedAtlasIds: const <String>{'main'},
        ),
        'main',
      );
    });

    test('rejects an unmatchable or ambiguous image', () {
      expect(
        () => RigFileLoader.resolveAtlasId(
          rig,
          'unrelated.png',
          loadedAtlasIds: const <String>{},
        ),
        throwsA(isA<RigFileException>()),
      );

      final ambiguous = _rig(
        atlases: const <String, AtlasDefinition>{
          'a': AtlasDefinition(
            id: 'a',
            width: 32,
            height: 32,
            imageKey: 'shared.png',
          ),
          'b': AtlasDefinition(
            id: 'b',
            width: 32,
            height: 32,
            imageKey: 'shared.png',
          ),
        },
        layers: const <LayerDefinition>[
          LayerDefinition(
            id: 'body',
            defaultFrame: SpriteRegion(
              atlas: 'a',
              x: 0,
              y: 0,
              width: 8,
              height: 8,
            ),
          ),
        ],
      );
      expect(
        () => RigFileLoader.resolveAtlasId(
          ambiguous,
          'shared.png',
          loadedAtlasIds: const <String>{},
        ),
        throwsA(isA<RigFileException>()),
      );
    });
  });

  group('RigFileLoader bounded reads', () {
    test('decodes UTF-8 text and enforces the size limit', () async {
      final text = '{"schemaVersion":1}';
      final file = XFile.fromData(Uint8List.fromList(text.codeUnits));
      expect(await RigFileLoader.readManifestText(file), text);
      await expectLater(
        RigFileLoader.readManifestText(file, maxBytes: 4),
        throwsA(isA<RigFileException>()),
      );
    });

    test('rejects invalid UTF-8 and non-positive limits', () async {
      final invalid = XFile.fromData(Uint8List.fromList(<int>[0xFF]));
      await expectLater(
        RigFileLoader.readManifestText(invalid),
        throwsA(isA<RigFileException>()),
      );
      await expectLater(
        RigFileLoader.readBytes(
          XFile.fromData(Uint8List(0)),
          maxBytes: 0,
          label: 'Atlas',
        ),
        throwsArgumentError,
      );
    });

    test('returns atlas bytes unchanged', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final file = XFile.fromData(bytes);
      expect(await RigFileLoader.readAtlasBytes(file), bytes);
    });
  });
}
