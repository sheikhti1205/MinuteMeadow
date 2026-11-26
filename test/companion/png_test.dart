import 'dart:typed_data';

import 'package:companion_focus/features/companion/png.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('accepts the generated fixture image', () {
    final info = inspectPng(buildPng(width: 6, height: 5), 'preview.png');

    expect(info.width, 6);
    expect(info.height, 5);
    expect(info.colorType, 6);
  });

  test('rejects an image without image data', () {
    expect(
      () => inspectPng(buildPng(includeData: false), 'preview.png'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('no image data'),
        ),
      ),
    );
  });

  test('rejects an image without its trailer', () {
    final png = buildPng();
    final truncated = Uint8List.fromList(png.sublist(0, png.length - 12));

    expect(
      () => inspectPng(truncated, 'preview.png'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('trailer'),
        ),
      ),
    );
  });

  test('rejects APNG chunks', () {
    final bytes = buildPng(
      extraChunks: [
        MapEntry('acTL', <int>[0, 0, 0, 1, 0, 0, 0, 1]),
      ],
    );
    expect(
      () => inspectPng(bytes, 'preview.png'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('acTL'),
        ),
      ),
    );
  });

  test('rejects compressed ancillary chunks', () {
    for (final type in <String>['zTXt', 'iTXt', 'iCCP']) {
      final bytes = buildPng(
        extraChunks: [
          MapEntry(type, <int>[0, 0, 0]),
        ],
      );
      expect(
        () => inspectPng(bytes, 'preview.png'),
        throwsA(isA<FormatException>()),
        reason: type,
      );
    }
  });

  test('rejects a malformed pixel stream', () {
    expect(
      () => inspectPng(buildPng(imageData: <int>[1, 2, 3, 4]), 'preview.png'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('pixel stream'),
        ),
      ),
    );
  });

  test('rejects an invalid row filter', () {
    expect(
      () => inspectPng(buildPng(rowFilter: 7), 'preview.png'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('row filter'),
        ),
      ),
    );
  });

  test('rejects an unsupported colour type', () {
    expect(
      () => inspectPng(buildPng(colorType: 5), 'preview.png'),
      throwsA(isA<FormatException>()),
    );
  });
}
