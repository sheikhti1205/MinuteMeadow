import 'package:companion_focus/features/marketplace/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

Map<String, Object?> entryBundle({
  required String id,
  required String name,
  String version = '1.0.0',
  String author = 'Example Studio',
}) => bundleFor(
  fixtureFiles(),
  id: id,
  name: name,
  version: version,
  author: author,
);

void main() {
  test('the production document with no packs is a supported state', () {
    final result = CompanionCatalogue.decode('{"schema": 1, "packs": []}');

    expect(result.error, isNull);
    expect(result.catalogue.isEmpty, isTrue);
    expect(result.catalogue.latest, isEmpty);
  });

  test('an absent document reads as an empty shelf', () {
    expect(CompanionCatalogue.decode(null).catalogue.isEmpty, isTrue);
    expect(CompanionCatalogue.decode('').error, isNull);
  });

  test('a schema mismatch is a recoverable error', () {
    final result = CompanionCatalogue.decode('{"schema": 2, "packs": []}');

    expect(result.catalogue.isEmpty, isTrue);
    expect(result.error, contains('version'));
  });

  test('damaged catalogue text is a recoverable error', () {
    final result = CompanionCatalogue.decode('{"schema": 1');
    expect(result.catalogue.isEmpty, isTrue);
    expect(result.error, isNotNull);
  });

  test('lists releases and exposes the newest one per pack', () {
    final result = CompanionCatalogue.decode(
      catalogueText(
        [
          entryBundle(id: 'dev.example.cat', name: 'Moss Cat'),
          entryBundle(id: 'dev.example.cat', name: 'Moss Cat', version: '1.2.0'),
          entryBundle(id: 'dev.example.stone', name: 'Stone'),
        ],
        categories: ['animal', 'animal', 'geometric'],
      ),
    );

    expect(result.error, isNull);
    expect(result.catalogue.entries, hasLength(3));
    expect(result.catalogue.latest, hasLength(2));
    expect(result.catalogue.latestFor('dev.example.cat')!.version, '1.2.0');
    expect(result.catalogue.updateFor('dev.example.cat', '1.0.0'), isTrue);
    expect(result.catalogue.updateFor('dev.example.cat', '1.2.0'), isFalse);
    expect(result.catalogue.categories, [PackCategory.geometric, PackCategory.animal]);
  });

  test('searches by name, author and category', () {
    final result = CompanionCatalogue.decode(
      catalogueText(
        [
          entryBundle(id: 'dev.example.cat', name: 'Moss Cat'),
          entryBundle(id: 'dev.example.stone', name: 'Stone', author: 'Other Studio'),
        ],
        categories: ['animal', 'geometric'],
      ),
    );
    final catalogue = result.catalogue;

    expect(catalogue.search('moss').single.id, 'dev.example.cat');
    expect(catalogue.search('other').single.id, 'dev.example.stone');
    expect(
      catalogue.search('', category: PackCategory.animal).single.id,
      'dev.example.cat',
    );
    expect(catalogue.search('missing'), isEmpty);
  });

  test('rejects a duplicated release', () {
    final result = CompanionCatalogue.decode(
      catalogueText([
        entryBundle(id: 'dev.example.cat', name: 'Moss Cat'),
        entryBundle(id: 'dev.example.cat', name: 'Moss Cat'),
      ]),
    );

    expect(result.catalogue.isEmpty, isTrue);
    expect(result.error, contains('twice'));
  });

  test('rejects an unknown category and unknown fields', () {
    final unknownCategory = CompanionCatalogue.decode(
      catalogueText([entryBundle(id: 'dev.example.cat', name: 'Moss Cat')], categories: ['robot']),
    );
    expect(unknownCategory.error, isNotNull);

    final unknownField = CompanionCatalogue.decode(
      '{"schema": 1, "packs": [], "source": "remote"}',
    );
    expect(unknownField.error, isNotNull);
  });

  test('a listed pack still validates as a bundle on install', () {
    final result = CompanionCatalogue.decode(
      catalogueText([
        entryBundle(id: 'dev.example.cat', name: 'Moss Cat'),
      ]),
    );
    final entry = result.catalogue.latest.single;
    final bundle = entry.toBundle();

    expect(bundle.manifest.id, 'dev.example.cat');
    expect(bundle.assets['preview.png']!.width, 4);
  });
}
