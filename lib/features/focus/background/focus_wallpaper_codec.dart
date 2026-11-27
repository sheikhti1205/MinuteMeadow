import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

/// Image formats accepted for a photo wallpaper.
///
/// The format is sniffed from the file's magic bytes, never from its name or
/// extension, so a renamed file cannot smuggle a different decoder in. Video,
/// animated GIF, animated PNG/WebP, SVG and HEIC are rejected; a wallpaper
/// photo is always one still frame.
enum FocusWallpaperImageFormat {
  jpeg('image/jpeg', 'JPEG'),
  png('image/png', 'PNG'),
  webp('image/webp', 'WebP');

  const FocusWallpaperImageFormat(this.mimeType, this.label);

  final String mimeType;
  final String label;
}

/// Hard limits applied before any photo bytes are decoded.
///
/// They bound the encoded read, the image header and the decoded raster. Eight
/// MiB matches the device-local wallpaper slot, so an accepted photo can
/// always be persisted, while a failed pick cannot exhaust memory on a
/// low-end device.
abstract final class FocusWallpaperLimits {
  static const int maxEncodedBytes = 8 * 1024 * 1024;
  static const int maxDimension = 8192;
  static const int minDimension = 64;
  static const int maxPixels = 16 * 1024 * 1024;

  /// The largest long edge the renderer decodes for a full-screen backdrop.
  static const int maxDecodeExtent = 4096;

  /// The reduced-size probe decoded while validating a newly picked file.
  static const int probeExtent = 320;

  static String get encodedSizeLabel =>
      '${maxEncodedBytes ~/ (1024 * 1024)} MB';

  static String get dimensionLabel => 'up to $maxDimension px on a side';
}

/// A user-facing failure while reading, validating or decoding a photo.
class FocusWallpaperCodecException implements Exception {
  const FocusWallpaperCodecException(this.message);

  final String message;

  @override
  String toString() => 'FocusWallpaperCodecException: $message';
}

/// A photo that passed the magic, size, dimension, still-frame and decode probe.
///
/// [bytes] is a read-only view of a private copy taken once during validation.
/// Nothing outside this object can mutate it, so the validated header,
/// dimensions and probe cannot be replaced by a later write. That copy is the
/// only encoded buffer the candidate retains; the caller's input is never
/// referenced again. The candidate does not own a decoded image; call [decode]
/// and dispose the returned image when the widget is disposed.
@immutable
class FocusWallpaperCandidate {
  const FocusWallpaperCandidate._({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.name,
  });

  final Uint8List bytes;
  final FocusWallpaperImageFormat format;
  final int width;
  final int height;
  final String? name;

  int get byteCount => bytes.length;

  int get pixelCount => width * height;

  String get sizeLabel => '$width × $height';

  /// Reads only the file's magic bytes.
  static FocusWallpaperImageFormat? sniff(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return FocusWallpaperImageFormat.jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return FocusWallpaperImageFormat.png;
    }
    if (bytes.length >= 12 &&
        _asciiAt(bytes, 0, 'RIFF') &&
        _asciiAt(bytes, 8, 'WEBP')) {
      return FocusWallpaperImageFormat.webp;
    }
    return null;
  }

  /// Validates [bytes] and returns a candidate, or throws
  /// [FocusWallpaperCodecException] with a message suitable for the editor.
  ///
  /// The validation order bounds work: the encoded size first, then the magic
  /// bytes, then the image header dimensions, then a small decode probe so a
  /// file that reports plausible dimensions but cannot actually be decoded is
  /// rejected before the editor keeps it. A multi-frame PNG or WebP is
  /// rejected after instantiation and before its first frame is read, because
  /// a wallpaper is always one still photo. The accepted bytes are copied once
  /// and exposed read-only, so the caller may release its own buffer.
  static Future<FocusWallpaperCandidate> validate(
    Uint8List bytes, {
    String? name,
  }) async {
    if (bytes.isEmpty) {
      throw const FocusWallpaperCodecException(
        'That file is empty. Choose a JPEG, PNG or WebP photo.',
      );
    }
    if (bytes.length > FocusWallpaperLimits.maxEncodedBytes) {
      throw FocusWallpaperCodecException(
        'That photo is larger than '
        '${FocusWallpaperLimits.encodedSizeLabel}. Choose a smaller image.',
      );
    }
    final format = sniff(bytes);
    if (format == null) {
      throw const FocusWallpaperCodecException(
        'Use a JPEG, PNG or WebP photo. Video and other formats are not '
        'supported.',
      );
    }

    // Copy once, then expose only the unmodifiable view. From here on every
    // check and the returned candidate read this buffer, so a caller that keeps
    // the input cannot change the image behind a passed validation. The input
    // itself is not retained.
    final Uint8List photo = Uint8List.fromList(bytes).asUnmodifiableView();

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? probe;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(photo);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < FocusWallpaperLimits.minDimension ||
          height < FocusWallpaperLimits.minDimension) {
        throw const FocusWallpaperCodecException(
          'That image is too small. Choose a larger photo.',
        );
      }
      if (width > FocusWallpaperLimits.maxDimension ||
          height > FocusWallpaperLimits.maxDimension) {
        throw FocusWallpaperCodecException(
          'That image is too large. Use one '
          '${FocusWallpaperLimits.dimensionLabel}.',
        );
      }
      if (width * height > FocusWallpaperLimits.maxPixels) {
        throw const FocusWallpaperCodecException(
          'That image has too many pixels. Choose a smaller photo.',
        );
      }

      final target = _scaledTarget(
        width,
        height,
        FocusWallpaperLimits.probeExtent,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: target.$1,
        targetHeight: target.$2,
      );
      if (codec.frameCount != 1) {
        throw const FocusWallpaperCodecException(
          'That image is animated. Choose a still JPEG, PNG or WebP photo.',
        );
      }
      final frame = await codec.getNextFrame();
      probe = frame.image;
      return FocusWallpaperCandidate._(
        bytes: photo,
        format: format,
        width: width,
        height: height,
        name: _cleanName(name),
      );
    } on FocusWallpaperCodecException {
      rethrow;
    } catch (_) {
      throw const FocusWallpaperCodecException(
        'That image could not be read. Try another photo.',
      );
    } finally {
      probe?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Decodes the photo with its long edge capped at [maxExtent].
  ///
  /// The returned image belongs to the caller, which must dispose it. Passing
  /// a small extent keeps a full-screen wallpaper inside a bounded raster even
  /// when the source is 16 megapixels.
  Future<ui.Image> decode({int maxExtent = 2048}) async {
    if (bytes.isEmpty) {
      throw const FocusWallpaperCodecException(
        'This photo is no longer available. Choose it again.',
      );
    }
    final int extent = math
        .min(
          math.max(maxExtent, FocusWallpaperLimits.minDimension),
          FocusWallpaperLimits.maxDecodeExtent,
        )
        .toInt();
    final target = _scaledTarget(width, height, extent);

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(
        targetWidth: target.$1,
        targetHeight: target.$2,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } on FocusWallpaperCodecException {
      rethrow;
    } catch (_) {
      throw const FocusWallpaperCodecException(
        'This photo could not be shown. Try choosing it again.',
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// The editor's file picker hook.
///
/// A host may supply its own picker that reads bytes once and returns a
/// validated candidate. Returning null means the user cancelled. When the hook
/// is null the built-in bounded picker is used.
typedef FocusWallpaperPhotoPicker = Future<FocusWallpaperCandidate?> Function();

/// Opens the platform picker for one still JPEG, PNG or WebP file.
///
/// On the web this is the browser file input. On Android it uses the system
/// document picker provided by `file_selector`; no activity registration is
/// required. The file length is checked before the bytes are read, so an
/// oversized file is rejected without loading it into memory. The selected
/// bytes are read once and handed to [FocusWallpaperCandidate.validate].
Future<FocusWallpaperCandidate?> pickFocusWallpaperFile() async {
  const XTypeGroup group = XTypeGroup(
    label: 'Photos',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
  );
  final XFile? file = await openFile(
    acceptedTypeGroups: const <XTypeGroup>[group],
  );
  if (file == null) return null;
  final int length = await file.length();
  if (length > FocusWallpaperLimits.maxEncodedBytes) {
    throw FocusWallpaperCodecException(
      'That photo is larger than '
      '${FocusWallpaperLimits.encodedSizeLabel}. Choose a smaller image.',
    );
  }
  final bytes = await _readBounded(file);
  if (bytes.isEmpty) {
    throw const FocusWallpaperCodecException(
      'That file is empty. Choose a JPEG, PNG or WebP photo.',
    );
  }
  return FocusWallpaperCandidate.validate(bytes, name: file.name);
}

/// Streams a picked file with a hard cap, so a platform that reports an
/// unknown length still cannot load an oversized file into memory.
Future<Uint8List> _readBounded(XFile file) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final Uint8List chunk in file.openRead()) {
    builder.add(chunk);
    if (builder.length > FocusWallpaperLimits.maxEncodedBytes) {
      throw FocusWallpaperCodecException(
        'That photo is larger than '
        '${FocusWallpaperLimits.encodedSizeLabel}. Choose a smaller image.',
      );
    }
  }
  return builder.takeBytes();
}

(int?, int?) _scaledTarget(int width, int height, int extent) {
  final long = math.max(width, height);
  if (long <= extent) return (null, null);
  final double scale = extent / long;
  return (
    math.max(1, (width * scale).round()).toInt(),
    math.max(1, (height * scale).round()).toInt(),
  );
}

bool _asciiAt(Uint8List bytes, int offset, String text) {
  if (offset + text.length > bytes.length) return false;
  for (var index = 0; index < text.length; index++) {
    if (bytes[offset + index] != text.codeUnitAt(index)) return false;
  }
  return true;
}

String? _cleanName(String? name) {
  if (name == null) return null;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
}
