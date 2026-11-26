import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:companion_focus/core/storage/pack_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a ZIP pack without writing its contents to disk', () {
    final files = PackArchive.read(_archive(['manifest.json', 'sprites/atlas.png']));
    expect(files.keys, ['manifest.json', 'sprites/atlas.png']);
    expect(files['manifest.json'], [7, 9]);
  });

  test('rejects paths outside a pack', () {
    expect(
      () => PackArchive.read(_archive(['manifest.json', '../settings.json'])),
      throwsFormatException,
    );
  });

  test('rejects case-insensitive duplicate paths', () {
    expect(
      () => PackArchive.read(_archive(['manifest.json', 'sprites/a.png', 'sprites/A.png'])),
      throwsFormatException,
    );
  });
}

Uint8List _archive(List<String> names) {
  final archive = Archive();
  for (final name in names) {
    archive.addFile(ArchiveFile(name, 2, [7, 9]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
