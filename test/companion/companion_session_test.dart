import 'dart:convert';
import 'dart:typed_data';

import 'package:companion_focus/features/companion/companion_library.dart';
import 'package:companion_focus/features/companion/companion_session.dart';
import 'package:companion_focus/features/marketplace/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

void main() {
  test('starts from the stored snapshot', () {
    final snapshot = CompanionLibrary.empty.install(installedFixture()).encode();
    final session = CompanionSession(
      initialSnapshot: snapshot,
      onSnapshot: (_) async {},
    );
    addTearDown(session.dispose);

    expect(session.library.pack('dev.example.geometric'), isNotNull);
    expect(session.loadError, isNull);
  });

  test('importing text persists the new library', () async {
    final writes = <String>[];
    final session = CompanionSession(
      initialSnapshot: null,
      onSnapshot: (snapshot) async => writes.add(snapshot),
      now: () => DateTime.utc(2026, 3, 4),
    );
    addTearDown(session.dispose);

    final ok = await session.importText(bundleText(fixtureFiles()));

    expect(ok, isTrue);
    expect(writes, hasLength(1));
    expect(session.library.pack('dev.example.geometric'), isNotNull);
    expect(session.success, contains('installed'));
    expect(session.error, isNull);
    final stored = CompanionLibrary.decode(writes.single);
    expect(stored.library.pack('dev.example.geometric')!.version, '1.0.0');
  });

  test('importing uploaded bytes uses the same path', () async {
    final session = CompanionSession(
      initialSnapshot: null,
      onSnapshot: (_) async {},
    );
    addTearDown(session.dispose);

    final ok = await session.importBytes(
      Uint8List.fromList(utf8.encode(bundleText(fixtureFiles()))),
    );

    expect(ok, isTrue);
    expect(session.library.length, 1);
  });

  test('a rejected pack leaves the library untouched', () async {
    final writes = <String>[];
    final session = CompanionSession(
      initialSnapshot: CompanionLibrary.empty.install(installedFixture()).encode(),
      onSnapshot: (snapshot) async => writes.add(snapshot),
    );
    addTearDown(session.dispose);

    final ok = await session.importText('{"schema": 2, "manifest": {}, "assets": {}}');

    expect(ok, isFalse);
    expect(writes, isEmpty);
    expect(session.error, contains('version'));
    expect(session.library.pack('dev.example.geometric'), isNotNull);
  });

  test('an incompatible application version is refused', () async {
    final writes = <String>[];
    final session = CompanionSession(
      initialSnapshot: null,
      onSnapshot: (snapshot) async => writes.add(snapshot),
    );
    addTearDown(session.dispose);

    final ok = await session.importText(
      bundleText(fixtureFiles(), minimumAppVersion: '9.9.9'),
    );

    expect(ok, isFalse);
    expect(writes, isEmpty);
    expect(session.error, contains('needs MinuteMeadow 9.9.9'));
  });

  test('a failed write keeps the previous version', () async {
    final session = CompanionSession(
      initialSnapshot: CompanionLibrary.empty.install(installedFixture()).encode(),
      onSnapshot: (_) async => throw Exception('storage full'),
    );
    addTearDown(session.dispose);

    final ok = await session.importText(
      bundleText(fixtureFiles(), version: '1.1.0'),
    );

    expect(ok, isFalse);
    expect(session.error, isNotNull);
    expect(session.library.pack('dev.example.geometric')!.version, '1.0.0');
  });

  test('removing a pack persists the empty library', () async {
    final writes = <String>[];
    final session = CompanionSession(
      initialSnapshot: CompanionLibrary.empty.install(installedFixture()).encode(),
      onSnapshot: (snapshot) async => writes.add(snapshot),
    );
    addTearDown(session.dispose);

    final ok = await session.remove('dev.example.geometric');

    expect(ok, isTrue);
    expect(session.library.isEmpty, isTrue);
    expect(writes, hasLength(1));
    expect(CompanionLibrary.decode(writes.single).library.isEmpty, isTrue);
  });

  test('installing a catalogue release updates the pack', () async {
    final writes = <String>[];
    final session = CompanionSession(
      initialSnapshot: CompanionLibrary.empty.install(installedFixture()).encode(),
      onSnapshot: (snapshot) async => writes.add(snapshot),
    );
    addTearDown(session.dispose);
    final catalogue = CompanionCatalogue.decode(
      catalogueText([
        bundleFor(fixtureFiles(), version: '1.1.0', name: 'Geometric'),
      ]),
    ).catalogue;

    final ok = await session.installPack(catalogue.latest.single.toBundle);

    expect(ok, isTrue);
    expect(writes, hasLength(1));
    expect(session.library.pack('dev.example.geometric')!.version, '1.1.0');
  });

  test('a damaged snapshot becomes a dismissible error state', () async {
    final session = CompanionSession(
      initialSnapshot: 'not a snapshot',
      onSnapshot: (_) async {},
    );
    addTearDown(session.dispose);

    expect(session.library.isEmpty, isTrue);
    expect(session.loadError, isNotNull);

    session.dismissLoadNotice();
    expect(session.loadError, isNull);
  });
}
