import 'dart:convert';

import '../companion/pack_bundle.dart';
import '../companion/pack_json.dart';
import '../companion/pack_manifest.dart';

/// The shelf a catalogue entry is filed under.
enum PackCategory {
  geometric('Geometric'),
  animal('Animals'),
  plant('Plants'),
  object('Objects'),
  other('Other');

  const PackCategory(this.label);

  final String label;

  static PackCategory parse(String value) {
    for (final category in values) {
      if (category.name == value) return category;
    }
    throw const FormatException('The catalogue uses an unknown category.');
  }
}

/// One installable pack release listed by the catalogue.
class CatalogueEntry {
  CatalogueEntry({
    required this.manifest,
    required this.category,
    required this.featured,
    required Map<String, String> assets,
  }) : _assets = Map.unmodifiable(assets);

  final PackManifest manifest;
  final PackCategory category;
  final bool featured;
  final Map<String, String> _assets;

  String get id => manifest.id;
  String get version => manifest.version;

  /// Builds the same validated bundle the local importer uses.
  PackBundle toBundle() => PackBundle.fromJson({
    'schema': PackManifest.applicationSchema,
    'manifest': manifest.toJson(),
    'assets': _assets,
  });
}

/// The outcome of reading a catalogue document.
class CatalogueReadResult {
  const CatalogueReadResult({required this.catalogue, this.error});

  final CompanionCatalogue catalogue;
  final String? error;
}

/// The curated catalogue behind the marketplace.
///
/// The production document is `assets/companion/catalog.json`; an empty pack
/// list is a supported state. Reading never throws: a schema mismatch or a
/// damaged document is returned as a recoverable error with an empty shelf.
class CompanionCatalogue {
  CompanionCatalogue(List<CatalogueEntry> entries) : entries = List.unmodifiable(entries) {
    final newest = <String, CatalogueEntry>{};
    for (final entry in entries) {
      final current = newest[entry.id];
      if (current == null || comparePackVersions(entry.version, current.version) > 0) {
        newest[entry.id] = entry;
      }
    }
    _latest = List.unmodifiable(
      newest.values.toList()..sort((a, b) {
        final byName = a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      }),
    );
  }

  static final empty = CompanionCatalogue(const <CatalogueEntry>[]);

  static const schema = 1;

  final List<CatalogueEntry> entries;
  late final List<CatalogueEntry> _latest;

  bool get isEmpty => _latest.isEmpty;

  /// The newest release of every listed pack.
  List<CatalogueEntry> get latest => _latest;

  List<PackCategory> get categories => [
    for (final category in PackCategory.values)
      if (_latest.any((entry) => entry.category == category)) category,
  ];

  CatalogueEntry? latestFor(String id) {
    for (final entry in _latest) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  bool updateFor(String id, String installedVersion) {
    final entry = latestFor(id);
    return entry != null && comparePackVersions(entry.version, installedVersion) > 0;
  }

  List<CatalogueEntry> search(String query, {PackCategory? category}) {
    final text = query.trim().toLowerCase();
    return [
      for (final entry in _latest)
        if ((category == null || entry.category == category) &&
            (text.isEmpty ||
                entry.manifest.name.toLowerCase().contains(text) ||
                entry.manifest.author.toLowerCase().contains(text) ||
                entry.id.contains(text)))
          entry,
    ];
  }

  static CatalogueReadResult decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return CatalogueReadResult(catalogue: empty);
    }
    if (source.length > PackLimits.catalogueCharacters) {
      return CatalogueReadResult(
        catalogue: CompanionCatalogue.empty,
        error: 'The marketplace catalogue is too large to read.',
      );
    }
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return CatalogueReadResult(
        catalogue: CompanionCatalogue.empty,
        error: 'The marketplace catalogue could not be read.',
      );
    }
    try {
      return CatalogueReadResult(catalogue: _fromJson(json));
    } on FormatException catch (error) {
      return CatalogueReadResult(
        catalogue: empty,
        error: error.message,
      );
    } catch (_) {
      return CatalogueReadResult(
        catalogue: CompanionCatalogue.empty,
        error: 'The marketplace catalogue could not be read.',
      );
    }
  }

  static CompanionCatalogue _fromJson(Object? json) {
    final map = packObject(json, 'The catalogue', required: const {'schema', 'packs'});
    if (map['schema'] != schema) {
      throw const FormatException(
        'Unsupported catalogue version. This build reads catalogue version $schema.',
      );
    }
    final packsValue = map['packs'];
    if (packsValue is! List<Object?> ||
        packsValue.length > PackLimits.maxCataloguePacks) {
      throw const FormatException('The catalogue lists too many packs.');
    }
    final entries = <CatalogueEntry>[];
    final seen = <String>{};
    for (final item in packsValue) {
      final entry = packObject(
        item,
        'A catalogue entry',
        required: const {'category', 'bundle'},
        optional: const {'featured'},
      );
      final category = PackCategory.parse(
        packText(entry['category'], 'A catalogue category', max: 16),
      );
      final featured = entry.containsKey('featured')
          ? packFlag(entry['featured'], 'A catalogue featured flag')
          : false;
      final bundle = packObject(
        entry['bundle'],
        'A catalogue bundle',
        required: const {'schema', 'manifest', 'assets'},
      );
      if (bundle['schema'] != PackManifest.applicationSchema) {
        throw FormatException(
          'Unsupported pack file version. This build reads ${PackManifest.applicationSchema}.',
        );
      }
      final manifestValue = bundle['manifest'];
      if (jsonEncode(manifestValue).length > PackLimits.manifestCharacters) {
        throw const FormatException('A catalogue manifest is too large.');
      }
      final manifest = PackManifest.fromJson(manifestValue);
      final assets = readEncodedAssets(bundle['assets'], manifest);
      if (!seen.add('${manifest.id}@${manifest.version}')) {
        throw FormatException('The catalogue lists ${manifest.name} twice.');
      }
      entries.add(
        CatalogueEntry(
          manifest: manifest,
          category: category,
          featured: featured,
          assets: assets,
        ),
      );
    }
    entries.sort((a, b) {
      final byName = a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase());
      if (byName != 0) return byName;
      final byId = a.id.compareTo(b.id);
      return byId != 0 ? byId : comparePackVersions(a.version, b.version);
    });
    return CompanionCatalogue(entries);
  }
}
