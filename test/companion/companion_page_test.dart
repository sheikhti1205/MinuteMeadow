import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/companion/companion_library.dart';
import 'package:companion_focus/features/companion/companion_page.dart';
import 'package:companion_focus/features/marketplace/catalogue.dart';
import 'package:companion_focus/features/marketplace/catalogue_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pack_fixture.dart';

Widget host(
  Widget child, {
  CompanionCatalogue? catalogue,
  double? textScale,
}) {
  final content = catalogue == null
      ? child
      : CompanionCatalogueScope(catalogue: catalogue, child: child);
  final body = textScale == null
      ? content
      : Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: content,
          ),
        );
  return MaterialApp(theme: CompanionTheme.light, home: Scaffold(body: body));
}

String snapshotWith(String name) =>
    CompanionLibrary.empty.install(installedFixture(name: name)).encode();

void main() {
  testWidgets('shows the empty library with its affordances', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(initialSnapshot: null, onSnapshot: (_) async {}),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    expect(find.text('No companions installed'), findsOneWidget);
    expect(
      find.textContaining('No marketplace packs are listed yet'),
      findsOneWidget,
    );
    expect(find.text('Browse marketplace'), findsOneWidget);
    expect(find.byTooltip('Import pack'), findsOneWidget);
    expect(find.byTooltip('Marketplace'), findsNothing);

    await tester.tap(find.byTooltip('Import pack'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a pack file'), findsOneWidget);
    expect(find.text('Paste pack JSON'), findsOneWidget);
  });

  testWidgets('lists an installed companion', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (_) async {},
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    expect(find.text('Moss Cat'), findsOneWidget);
    expect(find.textContaining('v1.0.0'), findsOneWidget);
    expect(find.byTooltip('Marketplace'), findsOneWidget);
  });

  testWidgets('imports a pasted pack and persists it', (tester) async {
    final writes = <String>[];
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: null,
          onSnapshot: (snapshot) async => writes.add(snapshot),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    await tester.tap(find.byTooltip('Import pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste pack JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      bundleText(fixtureFiles(), name: 'Moss Cat'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    expect(find.text('Moss Cat'), findsOneWidget);
    expect(writes, hasLength(1));
    expect(
      CompanionLibrary.decode(writes.single).library.pack('dev.example.geometric'),
      isNotNull,
    );
  });

  testWidgets('keeps the previous library when an import is rejected', (tester) async {
    final writes = <String>[];
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (snapshot) async => writes.add(snapshot),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    await tester.tap(find.byTooltip('Import pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste pack JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '{"schema": 2, "manifest": {}, "assets": {}}',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    expect(find.text('Moss Cat'), findsOneWidget);
    expect(writes, isEmpty);
    expect(find.textContaining('Unsupported'), findsOneWidget);
  });

  testWidgets('returns to the library after removing a companion', (tester) async {
    final writes = <String>[];
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (snapshot) async => writes.add(snapshot),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    await tester.tap(find.text('Moss Cat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('No companions installed'), findsOneWidget);
    expect(find.text('This companion is not installed.'), findsNothing);
    expect(writes, hasLength(1));
    expect(CompanionLibrary.decode(writes.single).library.isEmpty, isTrue);
  });

  testWidgets('offers an update when the catalogue is newer', (tester) async {
    final catalogue = CompanionCatalogue.decode(
      catalogueText([
        bundleFor(fixtureFiles(), version: '1.1.0', name: 'Moss Cat'),
      ]),
    ).catalogue;
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (_) async {},
        ),
        catalogue: catalogue,
      ),
    );

    expect(find.textContaining('Update available'), findsOneWidget);

    await tester.tap(find.text('Moss Cat'));
    await tester.pumpAndSettle();
    expect(find.text('Update to 1.1.0'), findsOneWidget);
  });

  testWidgets('uses the supplied preview builder in the detail route', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (_) async {},
          previewBuilder: (context, pack) => const Text('layered view'),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    await tester.tap(find.text('Moss Cat'));
    await tester.pumpAndSettle();

    expect(find.text('layered view'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows a stored notice for an unreadable snapshot', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: '{"schema": "companion.library/9"}',
          onSnapshot: (_) async {},
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    expect(find.textContaining('Unsupported companion library version'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.textContaining('Unsupported companion library version'), findsNothing);
  });

  testWidgets('renders the supplied stage above the installed library', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (_) async {},
          stageBuilder: (context) => const SizedBox(
            height: 160,
            child: Center(child: Text('companion stage')),
          ),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    expect(find.text('companion stage'), findsOneWidget);
    expect(find.text('Moss Cat'), findsOneWidget);
    expect(find.byTooltip('Marketplace'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('companion stage')).dy,
      lessThan(tester.getTopLeft(find.text('Moss Cat')).dy),
    );
  });

  testWidgets('keeps the intentional empty library below the stage', (tester) async {
    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: null,
          onSnapshot: (_) async {},
          stageBuilder: (context) => const Text('companion stage'),
        ),
        catalogue: CompanionCatalogue.empty,
      ),
    );

    expect(find.text('companion stage'), findsOneWidget);
    expect(find.text('No companions installed'), findsOneWidget);
    expect(
      find.textContaining('No marketplace packs are listed yet'),
      findsOneWidget,
    );
    expect(find.text('Browse marketplace'), findsOneWidget);
    expect(find.byTooltip('Marketplace'), findsNothing);
  });

  testWidgets('keeps the empty library usable at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: null,
          onSnapshot: (_) async {},
          stageBuilder: (context) => const SizedBox(
            height: 220,
            child: Center(child: Text('companion stage')),
          ),
        ),
        catalogue: CompanionCatalogue.empty,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Browse marketplace'), 80);
    expect(find.text('Browse marketplace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls with the stage at portrait width and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        CompanionPage(
          initialSnapshot: snapshotWith('Moss Cat'),
          onSnapshot: (_) async {},
          stageBuilder: (context) => const SizedBox(
            height: 220,
            child: Center(child: Text('companion stage')),
          ),
        ),
        catalogue: CompanionCatalogue.empty,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('companion stage'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Moss Cat'), 80);
    expect(find.text('Moss Cat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
