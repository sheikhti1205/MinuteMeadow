import 'dart:typed_data';
import 'dart:ui' as ui;

/// Holds decoded atlas images by atlas id. Decoding is deliberately outside the
/// painter: the painter only reads cached images and never blocks a frame.
final class AtlasCache {
  final Map<String, ui.Image> _images = <String, ui.Image>{};

  bool has(String atlasId) => _images.containsKey(atlasId);

  ui.Image? image(String atlasId) => _images[atlasId];

  void put(String atlasId, ui.Image image) {
    final previous = _images[atlasId];
    _images[atlasId] = image;
    if (previous != null && !identical(previous, image)) {
      previous.dispose();
    }
  }

  /// Decodes PNG or WebP bytes into an image the compositor can draw.
  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}
