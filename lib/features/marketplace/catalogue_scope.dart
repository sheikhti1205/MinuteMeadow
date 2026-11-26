import 'package:flutter/widgets.dart';

import 'catalogue.dart';

/// Provides the catalogue to the library and marketplace routes.
///
/// Without a scope the marketplace reads the bundled catalogue, and the library
/// simply has no update suggestions.
class CompanionCatalogueScope extends InheritedWidget {
  const CompanionCatalogueScope({
    required this.catalogue,
    required super.child,
    super.key,
  });

  final CompanionCatalogue catalogue;

  static CompanionCatalogue? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompanionCatalogueScope>()?.catalogue;

  @override
  bool updateShouldNotify(CompanionCatalogueScope oldWidget) =>
      !identical(oldWidget.catalogue, catalogue);
}
