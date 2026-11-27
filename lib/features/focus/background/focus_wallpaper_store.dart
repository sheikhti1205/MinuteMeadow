import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../../core/storage/local_database.dart';

/// How a wallpaper photo fills the Focus surface.
enum WallpaperPlacement { cover, contain, tile }

/// A locally chosen Focus wallpaper photo and the adjustments applied to it.
///
/// The class stores the encoded image exactly as it was accepted. Detecting
/// the format, decoding and resizing are renderer concerns; this type only
/// guarantees the bytes are non-empty, inside [maxBytes], and an unmodifiable
/// copy held for the life of the value. Placement, alignment and strength are
/// independent fields, so one adjustment can change without rewriting the
/// photo.
class FocusWallpaperPhoto {
  factory FocusWallpaperPhoto({
    required Uint8List bytes,
    WallpaperPlacement placement = WallpaperPlacement.cover,
    double alignmentX = 0,
    double alignmentY = 0,
    int strength = 100,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'The wallpaper is empty.');
    }
    if (bytes.length > maxBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'The wallpaper exceeds $maxBytes bytes.',
      );
    }
    _checkAlignment(alignmentX, 'alignmentX');
    _checkAlignment(alignmentY, 'alignmentY');
    _checkStrength(strength);
    return FocusWallpaperPhoto._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      placement,
      alignmentX,
      alignmentY,
      strength,
    );
  }

  FocusWallpaperPhoto._(
    this._bytes,
    this.placement,
    this.alignmentX,
    this.alignmentY,
    this.strength,
  );

  /// Largest accepted photo, shared with the database constraint.
  static const maxBytes = LocalDatabase.focusWallpaperMaxBytes;

  final Uint8List _bytes;

  /// The encoded image bytes as a read-only view.
  Uint8List get bytes => _bytes;

  final WallpaperPlacement placement;

  /// Horizontal anchor from -1 (left) to 1 (right).
  final double alignmentX;

  /// Vertical anchor from -1 (top) to 1 (bottom).
  final double alignmentY;

  /// How strongly the photo is applied, from 0 to 100.
  final int strength;

  int get byteLength => _bytes.length;

  /// Returns a copy with the provided fields replaced.
  ///
  /// An adjustment-only copy reuses the immutable byte buffer, so dragging an
  /// alignment or strength control never copies the photo. Passing [bytes]
  /// validates and copies the new image instead.
  FocusWallpaperPhoto copyWith({
    Uint8List? bytes,
    WallpaperPlacement? placement,
    double? alignmentX,
    double? alignmentY,
    int? strength,
  }) {
    if (bytes != null) {
      return FocusWallpaperPhoto(
        bytes: bytes,
        placement: placement ?? this.placement,
        alignmentX: alignmentX ?? this.alignmentX,
        alignmentY: alignmentY ?? this.alignmentY,
        strength: strength ?? this.strength,
      );
    }
    final nextAlignmentX = alignmentX ?? this.alignmentX;
    final nextAlignmentY = alignmentY ?? this.alignmentY;
    final nextStrength = strength ?? this.strength;
    _checkAlignment(nextAlignmentX, 'alignmentX');
    _checkAlignment(nextAlignmentY, 'alignmentY');
    _checkStrength(nextStrength);
    return FocusWallpaperPhoto._(
      _bytes,
      placement ?? this.placement,
      nextAlignmentX,
      nextAlignmentY,
      nextStrength,
    );
  }

  @override
  String toString() =>
      'FocusWallpaperPhoto(placement: ${placement.name}, '
      'alignment: ($alignmentX, $alignmentY), strength: $strength, '
      'bytes: $byteLength)';
}

/// Reads and writes the single locally chosen Focus wallpaper photo.
///
/// The photo is device-local media: it is not part of a data backup and is
/// never mixed with companion packs. A normal restore keeps it; the full reset
/// path in [LocalDatabase.replaceData] deletes it in the same transaction.
class FocusWallpaperStore {
  FocusWallpaperStore(this._database);

  final LocalDatabase _database;

  static const _slot = LocalDatabase.focusWallpaperSlot;

  /// Reads the saved photo, or null when no wallpaper is set.
  Future<FocusWallpaperPhoto?> read() async {
    final row = await _database.customSelect(
      'SELECT placement, alignment_x, alignment_y, strength, bytes '
      'FROM focus_wallpaper WHERE id = ?',
      variables: [Variable<String>(_slot)],
    ).getSingleOrNull();
    if (row == null) return null;
    return FocusWallpaperPhoto(
      bytes: row.read<Uint8List>('bytes'),
      placement: _decodePlacement(row.read<String>('placement')),
      alignmentX: row.read<double>('alignment_x'),
      alignmentY: row.read<double>('alignment_y'),
      strength: row.read<int>('strength'),
    );
  }

  /// Replaces the saved photo and its adjustments in one statement.
  ///
  /// The slot holds at most one photo, so a successful write leaves exactly
  /// one row and a failed write leaves the previous photo in place.
  Future<void> write(FocusWallpaperPhoto photo) => _database.customStatement(
    '''INSERT INTO focus_wallpaper
         (id, placement, alignment_x, alignment_y, strength, bytes)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         placement = excluded.placement,
         alignment_x = excluded.alignment_x,
         alignment_y = excluded.alignment_y,
         strength = excluded.strength,
         bytes = excluded.bytes''',
    [
      _slot,
      photo.placement.name,
      photo.alignmentX,
      photo.alignmentY,
      photo.strength,
      photo.bytes,
    ],
  );

  /// Updates the provided adjustments and leaves the rest untouched.
  ///
  /// Null values keep the saved choice. Returns false when no photo is saved,
  /// so adjusting can never invent a wallpaper without bytes.
  Future<bool> adjust({
    WallpaperPlacement? placement,
    double? alignmentX,
    double? alignmentY,
    int? strength,
  }) async {
    final assignments = <String>[];
    final variables = <Variable<Object>>[];
    if (placement != null) {
      assignments.add('placement = ?');
      variables.add(Variable<String>(placement.name));
    }
    if (alignmentX != null) {
      _checkAlignment(alignmentX, 'alignmentX');
      assignments.add('alignment_x = ?');
      variables.add(Variable<double>(alignmentX));
    }
    if (alignmentY != null) {
      _checkAlignment(alignmentY, 'alignmentY');
      assignments.add('alignment_y = ?');
      variables.add(Variable<double>(alignmentY));
    }
    if (strength != null) {
      _checkStrength(strength);
      assignments.add('strength = ?');
      variables.add(Variable<int>(strength));
    }
    if (assignments.isEmpty) {
      final row = await _database.customSelect(
        'SELECT 1 AS present FROM focus_wallpaper WHERE id = ?',
        variables: [Variable<String>(_slot)],
      ).getSingleOrNull();
      return row != null;
    }
    final updated = await _database.customUpdate(
      'UPDATE focus_wallpaper SET ${assignments.join(', ')} WHERE id = ?',
      variables: [...variables, Variable<String>(_slot)],
    );
    return updated > 0;
  }

  /// Removes the saved photo. Clearing an empty slot succeeds.
  Future<void> clear() => _database.customStatement(
    'DELETE FROM focus_wallpaper WHERE id = ?',
    [_slot],
  );
}

WallpaperPlacement _decodePlacement(String stored) {
  for (final placement in WallpaperPlacement.values) {
    if (placement.name == stored) return placement;
  }
  throw const FormatException('Unknown wallpaper placement.');
}

void _checkAlignment(double value, String name) {
  if (!value.isFinite || value < -1 || value > 1) {
    throw ArgumentError.value(
      value,
      name,
      'Wallpaper alignment must be between -1 and 1.',
    );
  }
}

void _checkStrength(int value) {
  if (value < 0 || value > 100) {
    throw ArgumentError.value(
      value,
      'strength',
      'Wallpaper strength must be between 0 and 100.',
    );
  }
}
