import 'package:companion_focus/features/companion/pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('accepts a minimal pack manifest', () {
    final files = fixtureFiles();
    final manifest = PackManifest.fromJson(manifestFor(files));

    expect(manifest.id, 'dev.example.geometric');
    expect(manifest.version, '1.0.0');
    expect(manifest.preview, 'preview.png');
    expect(manifest.assets, hasLength(1));
    expect(manifest.clips.single.frames.single.asset, 'preview.png');
    expect(manifest.byteSize, files['preview.png']!.length);
  });

  test('round trips through its canonical form', () {
    final manifest = PackManifest.fromJson(manifestFor(fixtureFiles()));
    final again = PackManifest.fromJson(manifest.toJson());

    expect(again.id, manifest.id);
    expect(again.toJson()['assets'], manifest.toJson()['assets']);
    expect(again.clips.single.id, 'idle');
  });

  test('rejects unknown top-level fields', () {
    final manifest = manifestFor(fixtureFiles())..['script'] = 'alert(1)';
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown nested fields', () {
    final manifest = manifestFor(fixtureFiles());
    final canvas = manifest['canvas']! as Map<String, Object?>;
    canvas['scale'] = 2;
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported manifest versions', () {
    final manifest = manifestFor(fixtureFiles())..['schema'] = 'companion.pack/2';
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('companion.pack/1'),
        ),
      ),
    );
  });

  test('rejects unsafe asset paths', () {
    for (final path in <String>[
      '../escape.png',
      'folder/../escape.png',
      '/absolute.png',
      'C:/drive.png',
      'folder\\escape.png',
      'preview.txt',
      'manifest.json',
      './preview.png',
    ]) {
      expect(
        () => validateAssetPath(path),
        throwsA(isA<FormatException>()),
        reason: path,
      );
    }
  });

  test('rejects duplicate asset paths', () {
    final manifest = manifestFor(fixtureFiles());
    final assets = manifest['assets']! as List<Map<String, Object?>>;
    assets.add(Map<String, Object?>.of(assets.first));
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a malformed checksum', () {
    final manifest = manifestFor(fixtureFiles());
    final assets = manifest['assets']! as List<Map<String, Object?>>;
    assets.first['sha256'] = 'ABC';
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an oversized asset declaration', () {
    final manifest = manifestFor(fixtureFiles());
    final assets = manifest['assets']! as List<Map<String, Object?>>;
    assets.first['bytes'] = PackLimits.assetBytes + 1;
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a frame that leaves its image', () {
    final files = fixtureFiles();
    final manifest = manifestFor(files);
    final clips = manifest['clips']! as List<Map<String, Object?>>;
    final frames = clips.first['frames']! as List<Map<String, Object?>>;
    (frames.first['rect']! as Map<String, Object?>)['w'] = 8;
    final parsed = PackManifest.fromJson(manifest);

    expect(
      () => parsed.verifyAssets(files),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('frame outside'),
        ),
      ),
    );
  });

  test('rejects frames that name an unknown layer or asset', () {
    final files = fixtureFiles();
    final unknownLayer = manifestFor(files);
    final clips = unknownLayer['clips']! as List<Map<String, Object?>>;
    final frames = clips.first['frames']! as List<Map<String, Object?>>;
    frames.first['layer'] = 'ghost';
    expect(
      () => PackManifest.fromJson(unknownLayer),
      throwsA(isA<FormatException>()),
    );

    final unknownAsset = manifestFor(files);
    final otherClips = unknownAsset['clips']! as List<Map<String, Object?>>;
    final otherFrames = otherClips.first['frames']! as List<Map<String, Object?>>;
    otherFrames.first['asset'] = 'missing.png';
    expect(
      () => PackManifest.fromJson(unknownAsset),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate clip ids', () {
    final files = fixtureFiles();
    final manifest = manifestFor(files);
    final clips = manifest['clips']! as List<Map<String, Object?>>;
    clips.add(Map<String, Object?>.of(clips.first));
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a preview outside the declared assets', () {
    final manifest = manifestFor(fixtureFiles(), preview: 'other.png');
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a non-https homepage', () {
    final manifest = manifestFor(fixtureFiles(), homepage: 'http://example.com');
    expect(
      () => PackManifest.fromJson(manifest),
      throwsA(isA<FormatException>()),
    );
  });

  test('compares application versions', () {
    final manifest = PackManifest.fromJson(
      manifestFor(fixtureFiles(), minimumAppVersion: '0.7.0'),
    );

    expect(manifest.isCompatibleWith('0.7.0'), isTrue);
    expect(manifest.isCompatibleWith('0.8.1'), isTrue);
    expect(manifest.isCompatibleWith('0.1.0'), isFalse);
    expect(comparePackVersions('1.2.10', '1.2.9'), greaterThan(0));
  });
}
