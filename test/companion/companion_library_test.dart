import 'dart:convert';

import 'package:companion_focus/features/companion/companion_library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('an empty library round trips', () {
    final encoded = CompanionLibrary.empty.encode();
    final result = CompanionLibrary.decode(encoded);

    expect(result.error, isNull);
    expect(result.rejected, 0);
    expect(result.library.isEmpty, isTrue);
  });

  test('a missing snapshot reads as an empty library', () {
    expect(CompanionLibrary.decode(null).library.isEmpty, isTrue);
    expect(CompanionLibrary.decode('').library.isEmpty, isTrue);
  });

  test('keeps an installed pack through encode and decode', () {
    final library = CompanionLibrary.empty.install(installedFixture());
    final encoded = library.encode();
    final result = CompanionLibrary.decode(encoded);
    final pack = result.library.pack('dev.example.geometric');

    expect(result.rejected, 0);
    expect(result.error, isNull);
    expect(pack, isNotNull);
    expect(pack!.version, '1.0.0');
    expect(pack.assets['preview.png']!.width, 4);
    expect(pack.manifest.name, 'Geometric');
  });

  test('installing a newer version replaces the installed one', () {
    final first = CompanionLibrary.empty.install(installedFixture());
    final second = first.install(installedFixture(version: '1.1.0'));

    expect(second.length, 1);
    expect(second.pack('dev.example.geometric')!.version, '1.1.0');
    expect(first.pack('dev.example.geometric')!.version, '1.0.0');
  });

  test('removing a pack keeps the rest', () {
    final library = CompanionLibrary.empty
        .install(installedFixture(id: 'dev.example.a', name: 'A'))
        .install(installedFixture(id: 'dev.example.b', name: 'B'));

    final withoutA = library.remove('dev.example.a');
    expect(withoutA.pack('dev.example.a'), isNull);
    expect(withoutA.pack('dev.example.b'), isNotNull);
    expect(library.length, 2);
  });

  test('skips a tampered pack but keeps the valid one', () {
    final library = CompanionLibrary.empty
        .install(installedFixture(id: 'dev.example.a', name: 'A'))
        .install(installedFixture(id: 'dev.example.b', name: 'B'));
    final data = jsonDecode(library.encode()) as Map<String, Object?>;
    final packs = data['packs']! as Map<String, Object?>;
    final tampered = packs['dev.example.a']! as Map<String, Object?>;
    final assets = tampered['assets']! as Map<String, Object?>;
    assets['preview.png'] = base64.encode(buildPng(red: 0x01));

    final result = CompanionLibrary.decode(jsonEncode(data));

    expect(result.error, isNull);
    expect(result.rejected, 1);
    expect(result.library.pack('dev.example.a'), isNull);
    expect(result.library.pack('dev.example.b'), isNotNull);
  });

  test('rejects a stored pack whose id does not match its key', () {
    final library = CompanionLibrary.empty.install(installedFixture());
    final data = jsonDecode(library.encode()) as Map<String, Object?>;
    final packs = data['packs']! as Map<String, Object?>;
    packs['dev.example.other'] = packs.remove('dev.example.geometric');

    final result = CompanionLibrary.decode(jsonEncode(data));

    expect(result.rejected, 1);
    expect(result.library.isEmpty, isTrue);
  });

  test('reports an unreadable snapshot without throwing', () {
    final broken = CompanionLibrary.decode('{"schema": "companion.library/1", "packs": []');
    expect(broken.library.isEmpty, isTrue);
    expect(broken.error, isNotNull);

    final mismatch = CompanionLibrary.decode('{"schema": "companion.library/2", "packs": {}}');
    expect(mismatch.library.isEmpty, isTrue);
    expect(mismatch.error, contains('version'));
  });
}
