import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../features/companion/pack_manifest.dart';
import '../features/marketplace/catalogue.dart';
import '../features/marketplace/catalogue_repository.dart';

class DevelopmentCatalogueRepository implements CompanionCatalogueRepository {
  const DevelopmentCatalogueRepository();

  @override
  Future<CatalogueReadResult> load() async {
    try {
      final entries = <CatalogueEntry>[];
      for (final (id, name, ink, accent) in _fixtures) {
        entries.add(await _entry(id, name, ink, accent));
      }
      return CatalogueReadResult(catalogue: CompanionCatalogue(entries));
    } on Exception {
      return CatalogueReadResult(
        catalogue: CompanionCatalogue.empty,
        error: 'Could not create the development packs.',
      );
    }
  }

  static Future<CatalogueEntry> _entry(String id, String name, int ink, int accent) async {
    final layered = id == 'layer-composition';
    final frames = id == 'geometric-motion' ? 2 : 1;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..isAntiAlias = false;
    for (var index = 0; index < frames; index++) {
      final x = index * 16.0;
      canvas.drawRect(ui.Rect.fromLTWH(x + 3, 5, 10, 9), paint..color = ui.Color(ink));
      canvas.drawRect(
        ui.Rect.fromLTWH(x + 6, index == 0 ? 3 : 2, 5, 4),
        paint..color = ui.Color(accent),
      );
    }
    if (layered) {
      canvas.drawRect(ui.Rect.fromLTWH(16, 0, 8, 3), paint..color = ui.Color(accent));
    }
    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage((layered ? 2 : frames) * 16, 16);
    } finally {
      picture.dispose();
    }
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (bytes == null) throw const FormatException('Could not draw the development atlas.');
    final png = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    final manifest = PackManifest.fromJson({
      'schema': PackManifest.schema,
      'id': 'dev.companion.$id',
      'version': '1.0.0',
      'name': '$name (test)',
      'author': 'MinuteMeadow',
      'description': 'Geometric development fixture for pack and animation checks.',
      'license': 'Development use only',
      'preview': 'preview.png',
      'canvas': {'width': 16, 'height': 16},
      'palette': [_hex(ink), _hex(accent)],
      'layers': [
        {'id': 'shape', 'z': 0},
        if (layered)
          {
            'id': 'arm',
            'parent': 'shape',
            'z': 1,
            'offset': {'x': 9, 'y': 9},
            'pivot': {'x': 1, 'y': 1},
          },
      ],
      'clips': [
        {
          'id': 'idle',
          'fps': 3,
          'loop': true,
          'frames': [
            for (var frame = 0; frame < frames; frame++)
              {
                'layer': 'shape',
                'asset': 'preview.png',
                'rect': {'x': frame * 16, 'y': 0, 'w': 16, 'h': 16},
              },
            if (layered)
              {'layer': 'arm', 'asset': 'preview.png', 'rect': {'x': 16, 'y': 0, 'w': 8, 'h': 3}},
          ],
          if (layered) 'durationMs': 800,
          if (layered)
            'tracks': [
              {
                'layer': 'arm',
                'property': 'rotationDegrees',
                'keyframes': [
                  {'timeMs': 0, 'value': 0},
                  {'timeMs': 400, 'value': 45},
                  {'timeMs': 800, 'value': 0},
                ],
              },
            ],
        },
      ],
      'assets': [
        {'path': 'preview.png', 'sha256': sha256.convert(png).toString(), 'bytes': png.length},
      ],
    });
    return CatalogueEntry(
      manifest: manifest,
      category: PackCategory.geometric,
      featured: id == 'geometric-motion',
      assets: {'preview.png': base64Encode(png)},
    );
  }

  static String _hex(int color) => '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}';

  static const _fixtures = [
    ('pixel-blocks', 'Pixel Blocks', 0xff873829, 0xffd5a980),
    ('geometric-motion', 'Geometric Motion', 0xff4e5940, 0xffb9c9a5),
    ('layer-composition', 'Layer Composition', 0xff362820, 0xffe0ae67),
  ];
}
