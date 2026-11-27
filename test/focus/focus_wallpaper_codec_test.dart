import 'dart:typed_data';

import 'package:companion_focus/features/focus/background/focus_wallpaper_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const List<int> _webpHeader = <int>[
  0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50,
];

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('sniff accepts still JPEG, PNG and WebP magic only', () {
    expect(
      FocusWallpaperCandidate.sniff(_bytes(<int>[0xFF, 0xD8, 0xFF, 0xE0])),
      FocusWallpaperImageFormat.jpeg,
    );
    expect(
      FocusWallpaperCandidate.sniff(
        _bytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]),
      ),
      FocusWallpaperImageFormat.png,
    );
    expect(
      FocusWallpaperCandidate.sniff(_bytes(_webpHeader)),
      FocusWallpaperImageFormat.webp,
    );
    expect(
      FocusWallpaperCandidate.sniff(
        _bytes(<int>[0x47, 0x49, 0x46, 0x38, 0x39]),
      ),
      isNull,
      reason: 'An animated GIF is not a wallpaper photo.',
    );
    expect(
      FocusWallpaperCandidate.sniff(
        _bytes(<int>[0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]),
      ),
      isNull,
      reason: 'An MP4 container is not a wallpaper photo.',
    );
  });

  test('rejects empty and oversized input before decoding', () async {
    await expectLater(
      FocusWallpaperCandidate.validate(Uint8List(0)),
      throwsA(
        isA<FocusWallpaperCodecException>().having(
          (error) => error.message,
          'message',
          'That file is empty. Choose a JPEG, PNG or WebP photo.',
        ),
      ),
    );
    await expectLater(
      FocusWallpaperCandidate.validate(
        Uint8List(FocusWallpaperLimits.maxEncodedBytes + 1),
      ),
      throwsA(
        isA<FocusWallpaperCodecException>().having(
          (error) => error.message,
          'message',
          contains('larger than ${FocusWallpaperLimits.encodedSizeLabel}'),
        ),
      ),
    );
  });

  test('rejects an unknown payload with format guidance', () async {
    await expectLater(
      FocusWallpaperCandidate.validate(_bytes(<int>[1, 2, 3, 4])),
      throwsA(
        isA<FocusWallpaperCodecException>().having(
          (error) => error.message,
          'message',
          contains('Use a JPEG, PNG or WebP photo'),
        ),
      ),
    );
  });
}
