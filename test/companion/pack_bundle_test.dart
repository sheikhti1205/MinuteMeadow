import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_focus/features/companion/pack_bundle.dart';
import 'package:companion_focus/features/companion/pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('decodes a bundle and verifies its assets', () {
    final files = fixtureFiles();
    final bundle = PackBundle.decode(bundleText(files));

    expect(bundle.manifest.id, 'dev.example.geometric');
    expect(bundle.assets.keys, ['preview.png']);
    expect(bundle.assets['preview.png']!.width, 4);
    expect(bundle.assets['preview.png']!.height, 4);
  });

  test('rejects an unexpected asset', () {
    final files = fixtureFiles();
    final bundle = bundleFor(files);
    final assets = bundle['assets']! as Map<String, Object?>;
    assets['extra.png'] = base64.encode(buildPng());
    expect(
      () => PackBundle.fromJson(bundle),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a missing asset', () {
    final bundle = bundleFor(fixtureFiles());
    (bundle['assets']! as Map<String, Object?>).remove('preview.png');
    expect(
      () => PackBundle.fromJson(bundle),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a checksum mismatch', () {
    final bundle = bundleFor(fixtureFiles());
    final manifest = bundle['manifest']! as Map<String, Object?>;
    final assets = manifest['assets']! as List<Map<String, Object?>>;
    assets.first['sha256'] = '0' * 64;
    expect(
      () => PackBundle.fromJson(bundle),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
  });

  test('rejects a declared size mismatch', () {
    final bundle = bundleFor(fixtureFiles());
    final manifest = bundle['manifest']! as Map<String, Object?>;
    final assets = manifest['assets']! as List<Map<String, Object?>>;
    assets.first['bytes'] = 32;
    expect(
      () => PackBundle.fromJson(bundle),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed base64', () {
    final bundle = bundleFor(fixtureFiles());
    final assets = bundle['assets']! as Map<String, Object?>;
    assets['preview.png'] = 'not$base64';
    expect(
      () => PackBundle.fromJson(bundle),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a damaged PNG block', () {
    final damaged = Uint8List.fromList(buildPng());
    damaged[20] ^= 0xFF;
    expect(
      () => PackBundle.fromJson(bundleFor({'preview.png': damaged})),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('damaged'),
        ),
      ),
    );
  });

  test('rejects trailing bytes after the PNG trailer', () {
    final bytes = Uint8List.fromList(<int>[...buildPng(), 0]);
    expect(
      () => PackBundle.fromJson(bundleFor({'preview.png': bytes})),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('trailing'),
        ),
      ),
    );
  });

  test('rejects an oversized pack document', () {
    expect(
      () => PackBundle.decode('x' * (PackLimits.bundleCharacters + 1)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('too large'),
        ),
      ),
    );
  });

  test('bridges a validated archive through the same manifest checks', () {
    final files = fixtureFiles();
    final contents = <String, Uint8List>{
      'manifest.json': Uint8List.fromList(
        utf8.encode(jsonEncode(manifestFor(files))),
      ),
      'preview.png': files['preview.png']!,
      'LICENSE': Uint8List.fromList(utf8.encode('CC-BY-4.0')),
    };

    final bundle = PackBundle.fromArchive(contents);
    expect(bundle.manifest.id, 'dev.example.geometric');
    expect(bundle.assets.keys, ['preview.png']);
  });

  test('rejects undeclared archive files', () {
    final files = fixtureFiles();
    final contents = <String, Uint8List>{
      'manifest.json': Uint8List.fromList(
        utf8.encode(jsonEncode(manifestFor(files))),
      ),
      'preview.png': files['preview.png']!,
      'notes.txt': Uint8List.fromList(utf8.encode('hello')),
    };

    expect(
      () => PackBundle.fromArchive(contents),
      throwsA(isA<FormatException>()),
    );
  });

  test('reads either upload form', () {
    final text = bundleText(fixtureFiles());
    final json = PackBundle.fromUpload(Uint8List.fromList(utf8.encode(text)));
    expect(json.manifest.name, 'Geometric');

    expect(
      () => PackBundle.fromUpload(Uint8List.fromList(<int>[0xFF, 0xFE, 0x00])),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PackBundle.fromUpload(
        Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
