import 'dart:typed_data';
import 'dart:ui' as ui;

/// Holds decoded atlas images by atlas id. Decoding is deliberately outside the
/// painter: the painter only reads cached images and never blocks a frame.
final class AtlasCache {
  final Map<String, ui.Image> _images = <String, ui.Image>{};

  bool has(String atlasId) => _images.containsKey(atlasId);

  ui.Image? image(String atlasId) => _images[atlasId];

  Set<String> get atlasIds => Set<String>.unmodifiable(_images.keys);

  void put(String atlasId, ui.Image image) {
    final previous = _images[atlasId];
    _images[atlasId] = image;
    if (previous != null && !identical(previous, image)) {
      previous.dispose();
    }
  }

  /// Disposes images that the active rig no longer references.
  void retain(Set<String> atlasIds) {
    final stale = _images.keys
        .where((atlasId) => !atlasIds.contains(atlasId))
        .toList();
    for (final atlasId in stale) {
      _images.remove(atlasId)?.dispose();
    }
  }

  /// Decodes PNG or WebP bytes into an image the compositor can draw.
  static Future<ui.Image> decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          return frame.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}
