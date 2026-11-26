import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/marketplace/catalogue.dart';
import 'package:companion_focus/features/marketplace/catalogue_repository.dart';
import 'package:companion_focus/features/marketplace/marketplace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

class _ErrorRepository implements CompanionCatalogueRepository {
  @override
  Future<CatalogueReadResult> load() async => CatalogueReadResult(
    catalogue: CompanionCatalogue.empty,
    error: 'Unsupported catalogue version. This build reads catalogue version 1.',
  );
}

CompanionCatalogue twoPackCatalogue() => CompanionCatalogue.decode(
  catalogueText(
    [
      bundleFor(fixtureFiles(), id: 'dev.example.cat', name: 'Moss Cat'),
      bundleFor(fixtureFiles(), id: 'dev.example.stone', name: 'Stone'),
    ],
    categories: ['animal', 'geometric'],
  ),
).catalogue;

Widget host(Widget page) => MaterialApp(theme: CompanionTheme.light, home: page);

void main() {
  testWidgets('an empty catalogue keeps browsing available', (tester) async {
    await tester.pumpWidget(
      host(
        MarketplacePage(
          initialSnapshot: null,
          onSnapshot: (_) async {},
          catalogue: CompanionCatalogue.empty,
        ),
      ),
    );

    expect(find.text('The marketplace is empty'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('lists catalogue packs and installs one', (tester) async {
    final writes = <String>[];
    await tester.pumpWidget(
      host(
        MarketplacePage(
          initialSnapshot: null,
          onSnapshot: (snapshot) async => writes.add(snapshot),
          catalogue: twoPackCatalogue(),
        ),
      ),
    );

    expect(find.text('Moss Cat'), findsOneWidget);
    expect(find.text('Stone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Install').first);
    await tester.pumpAndSettle();

    expect(find.text('Installed'), findsOneWidget);
    expect(writes, hasLength(1));
  });

  testWidgets('searches and filters by category', (tester) async {
    await tester.pumpWidget(
      host(
        MarketplacePage(
          initialSnapshot: null,
          onSnapshot: (_) async {},
          catalogue: twoPackCatalogue(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'stone');
    await tester.pump();
    expect(find.text('Moss Cat'), findsNothing);
    expect(find.text('Stone'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Moss Cat'), findsOneWidget);

    await tester.tap(find.text('Animals'));
    await tester.pump();
    expect(find.text('Moss Cat'), findsOneWidget);
    expect(find.text('Stone'), findsNothing);
  });

  testWidgets('opens pack details and installs from there', (tester) async {
    final writes = <String>[];
    await tester.pumpWidget(
      host(
        MarketplacePage(
          initialSnapshot: null,
          onSnapshot: (snapshot) async => writes.add(snapshot),
          catalogue: twoPackCatalogue(),
        ),
      ),
    );

    await tester.tap(find.text('Moss Cat'));
    await tester.pumpAndSettle();

    expect(find.text('CC-BY-4.0'), findsOneWidget);
    expect(find.text('Animals'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    expect(find.text('Installed version 1.0.0'), findsOneWidget);
    expect(writes, hasLength(1));
  });

  testWidgets('surfaces a catalogue schema error as a recoverable state', (tester) async {
    await tester.pumpWidget(
      host(
        MarketplacePage(
          initialSnapshot: null,
          onSnapshot: (_) async {},
          repository: _ErrorRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Unsupported catalogue version'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('The marketplace is empty'), findsOneWidget);
  });
}
