import 'package:companion_focus/app/development_catalogue.dart';
import 'package:companion_focus/features/companion/companion_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('development packs install through the same validator as imported packs', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final result = await const DevelopmentCatalogueRepository().load();
      expect(result.error, isNull);
      expect(result.catalogue.entries.map((entry) => entry.id), [
        'dev.companion.pixel-blocks',
        'dev.companion.geometric-motion',
        'dev.companion.layer-composition',
      ]);

      String? snapshot;
      final session = CompanionSession(
        initialSnapshot: null,
        onSnapshot: (value) async {
          snapshot = value;
        },
      );
      addTearDown(session.dispose);
      for (final entry in result.catalogue.entries) {
        expect(await session.installPack(entry.toBundle), isTrue, reason: session.error);
      }

      final restored = CompanionSession(
        initialSnapshot: snapshot,
        onSnapshot: (_) async {},
      );
      addTearDown(restored.dispose);
      expect(restored.rejected, 0);
      expect(restored.library.pack('dev.companion.layer-composition'), isNotNull);
    });
  });
}
