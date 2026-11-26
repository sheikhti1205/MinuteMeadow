import 'package:companion_focus/app/installed_companion_view.dart';
import 'package:companion_focus/companion_engine/debug/geometric_rig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _scaledHost(Widget child, double textScale) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  ),
);

/// Mirrors the Focus shell's fixed square and clip around the stage.
Widget _focusSquare(Widget child) => Center(
  child: SizedBox.square(
    dimension: 224,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Center(child: child),
    ),
  ),
);

Future<GeometricRigBundle> _fixture(WidgetTester tester) async {
  final created = await tester.runAsync(GeometricRigFixture.create);
  expect(created, isNotNull, reason: 'the geometric fixture needs an atlas');
  final bundle = created!;
  addTearDown(bundle.atlasImage.dispose);
  return bundle;
}

InstalledCompanionView _stage({
  required GeometricRigBundle fixture,
  required ValueNotifier<String?> ambient,
  required bool showInteractionControls,
  double stageHeight = 200,
}) => InstalledCompanionView(
  pack: null,
  debugStage: fixture,
  lowPower: false,
  sound: false,
  ambientClip: ambient,
  stageHeight: stageHeight,
  showInteractionControls: showInteractionControls,
);

void main() {
  test('defaults keep the nullable stage API compatible', () {
    final ambient = ValueNotifier<String?>(null);
    final view = InstalledCompanionView(
      pack: null,
      lowPower: false,
      sound: false,
      ambientClip: ambient,
    );

    expect(view.pack, isNull);
    expect(view.useDevelopmentFixture, isFalse);
    expect(view.stageHeight, 200);
    expect(view.showInteractionControls, isTrue);
    expect(view.debugStage, isNull);
  });

  testWidgets('renders an intentional empty stage without a pack', (
    tester,
  ) async {
    final ambient = ValueNotifier<String?>(null);
    addTearDown(ambient.dispose);
    await tester.pumpWidget(
      _host(
        InstalledCompanionView(
          pack: null,
          lowPower: false,
          sound: false,
          ambientClip: ambient,
          stageHeight: 160,
        ),
      ),
    );
    await tester.pump();

    final stage = find.byKey(const ValueKey('companion-empty-stage'));
    expect(stage, findsOneWidget);
    expect(tester.getSize(stage).height, 160);
    expect(find.byKey(const ValueKey('companion-loading-stage')), findsNothing);
    expect(find.text('Companion stage'), findsOneWidget);
    expect(find.text('Install a companion to see it here.'), findsOneWidget);
    expect(find.text('Pet'), findsNothing);
    expect(find.text('Throw ball'), findsNothing);
  });

  testWidgets('Focus mode keeps a large-text notice inside the stage', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final ambient = ValueNotifier<String?>(null);
    addTearDown(ambient.dispose);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      _scaledHost(
        _focusSquare(
          _stage(
            fixture: fixture,
            ambient: ambient,
            showInteractionControls: false,
          ),
        ),
        2,
      ),
    );
    expect(tester.takeException(), isNull);

    final canvas = find.byKey(const ValueKey('companion-stage-canvas'));
    await tester.tapAt(tester.getCenter(canvas));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Petted companion'), findsNothing);
    final stageSemantics = find.byKey(
      const ValueKey('companion-stage-semantics'),
    );
    expect(stageSemantics, findsOneWidget);
    final data = tester.getSemantics(stageSemantics).getSemanticsData();
    expect(data.label, 'Companion stage. Petted companion');
    expect(data.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    expect(
      tester.getSize(find.byType(InstalledCompanionView)).height,
      moreOrLessEquals(200),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Companion keeps a wrapping notice visible at large text', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final ambient = ValueNotifier<String?>(null);
    addTearDown(ambient.dispose);

    await tester.pumpWidget(
      _scaledHost(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: _stage(
              fixture: fixture,
              ambient: ambient,
              showInteractionControls: true,
              stageHeight: 160,
            ),
          ),
        ),
        2,
      ),
    );
    expect(tester.takeException(), isNull);

    final canvas = find.byKey(const ValueKey('companion-stage-canvas'));
    await tester.tapAt(tester.getCenter(canvas));
    await tester.pump();

    final notice = find.byKey(const ValueKey('companion-stage-notice'));
    expect(notice, findsOneWidget);
    expect(find.text('Petted companion'), findsOneWidget);
    final text = tester.widget<Text>(notice);
    expect(text.softWrap, isTrue);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('interaction controls keep a 48dp touch target', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final ambient = ValueNotifier<String?>(null);
    addTearDown(ambient.dispose);

    await tester.pumpWidget(
      _host(
        _stage(
          fixture: fixture,
          ambient: ambient,
          showInteractionControls: true,
          stageHeight: 160,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    for (final label in ['Pet', 'Throw ball']) {
      final button = find.widgetWithText(TextButton, label);
      expect(button, findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }

    final pet = find.widgetWithText(TextButton, 'Pet');
    await tester.tapAt(tester.getRect(pet).bottomCenter - const Offset(0, 2));
    await tester.pump();
    expect(find.text('Petted companion'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
