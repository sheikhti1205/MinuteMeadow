import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalogue.dart';

/// Where the marketplace reads its catalogue from.
abstract interface class CompanionCatalogueRepository {
  Future<CatalogueReadResult> load();
}

/// The catalogue bundled with the current build.
///
/// Production ships `assets/companion/catalog.json` with an empty pack list.
/// A development build can replace it without touching the library.
class BundledCatalogueRepository implements CompanionCatalogueRepository {
  const BundledCatalogueRepository();

  static const assetPath = 'assets/companion/catalog.json';

  @override
  Future<CatalogueReadResult> load() async {
    String source;
    try {
      source = await rootBundle.loadString(assetPath);
    } catch (_) {
      return CatalogueReadResult(
        catalogue: CompanionCatalogue.empty,
        error: 'The marketplace catalogue is missing from this build.',
      );
    }
    return CompanionCatalogue.decode(source);
  }
}

/// Holds the catalogue shelf for a page.
///
/// A catalogue passed in directly seeds the shelf and skips loading. Otherwise
/// the repository is read once; a schema mismatch or damaged document becomes a
/// recoverable [error] with an empty shelf.
class CatalogueController extends ChangeNotifier {
  CatalogueController({
    CompanionCatalogue? seed,
    CompanionCatalogueRepository repository = const BundledCatalogueRepository(),
  }) : _catalogue = seed ?? CompanionCatalogue.empty,
       _repository = repository,
       _seeded = seed != null;

  final CompanionCatalogueRepository _repository;
  final bool _seeded;

  CompanionCatalogue _catalogue;
  String? _error;
  bool _loading = false;
  bool _loaded = false;
  bool _disposed = false;

  CompanionCatalogue get catalogue => _catalogue;
  String? get error => _error;
  bool get loading => _loading;

  Future<void> load() async {
    if (_seeded || _loaded || _loading) return;
    _loading = true;
    _announce();
    final result = await _repository.load();
    if (_disposed) return;
    _catalogue = result.catalogue;
    _error = result.error;
    _loading = false;
    _loaded = true;
    _announce();
  }

  Future<void> retry() {
    if (_seeded) return Future<void>.value();
    _loaded = false;
    return load();
  }

  void dismissError() {
    if (_error == null) return;
    _error = null;
    _announce();
  }

  void _announce() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
