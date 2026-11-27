import 'package:companion_focus/app/installed_companion_view.dart';
import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Entry titles tolerate `&`, `and` or `+`, and both colour spellings.
final RegExp _themeEntryPattern = RegExp(
  r'^\s*theme\s*(?:&|and|\+)\s*colou?rs?\s*$',
  caseSensitive: false,
);
final RegExp _homeEntryPattern = RegExp(
  r'^\s*home\s*(?:&|and|\+)\s*cards?\s*$',
  caseSensitive: false,
);

Finder _themeEntry() => find.textContaining(_themeEntryPattern);

Finder _homeEntry() => find.textContaining(_homeEntryPattern);

/// Matches controls a user can operate, without pinning a widget choice.
bool _isOperable(Widget widget) =>
    widget is InkResponse ||
    widget is Switch ||
    widget is RawChip ||
    widget is SegmentedButton<Object?> ||
    widget is ToggleButtons ||
    widget is Radio<Object?>;

Finder get _operable => find.byWidgetPredicate(_isOperable);

/// Text inside the open editor. The settings page is offstage behind the
/// route, so this excludes the entry list and the app-bar title.
Finder _inEditor(Pattern pattern) => find.descendant(
  of: find.byType(Scrollable).first,
  matching: find.textContaining(pattern),
);

/// Explicit action labels live in the list or in a fixed footer.
Finder _action(String label) => find.textContaining(
  RegExp('^\\s*${RegExp.escape(label)}\\s*\$', caseSensitive: false),
);

Finder _backControl() => find.byWidgetPredicate(
  (widget) => widget is BackButton || widget is CloseButton,
);

class _Harness {
  _Harness() : notifier = ValueNotifier(const AppSettings());

  final ValueNotifier<AppSettings> notifier;
  final List<AppSettings> saves = [];

  Widget build() => MaterialApp(
    theme: CompanionTheme.light,
    home: SettingsPage(
      settings: notifier,
      onSave: (next) async {
        saves.add(next);
        notifier.value = next;
      },
      onExport: () async => const DataBackup(
        settings: AppSettings(),
        sessions: [],
      ).encode(),
      onReplace: (backup) async {
        notifier.value = backup.settings;
      },
      onClear: () async {
        notifier.value = const AppSettings();
      },
    ),
  );

  void dispose() => notifier.dispose();
}

Future<_Harness> _pump(WidgetTester tester) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.build());
  await tester.pumpAndSettle();
  return harness;
}

/// Advances a bounded number of frames. Editor previews may run continuously,
/// so editor work never waits for the whole tree to settle.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrolls the active list until [finder] is built, then reveals it.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump();
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 150));
  }
  fail('Could not reveal $finder');
}

Future<void> _openEntry(WidgetTester tester, Finder entry) async {
  await _reveal(tester, entry);
  expect(entry, findsOneWidget);
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Layout order of the settings list, so an entry's group is not guessed from
/// a screen position that depends on scrolling.
List<String> _listLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Text && widget.data != null) labels.add(widget.data!);
    element.visitChildren(visit);
  }

  visit(tester.element(find.byType(ListView)));
  return labels;
}

int _indexOfLabel(List<String> labels, Pattern pattern) =>
    labels.indexWhere((label) => pattern.allMatches(label).isNotEmpty);

void _expectOperable(Finder label) {
  for (var index = 0; index < label.evaluate().length; index++) {
    final control = find.ancestor(of: label.at(index), matching: _operable);
    if (control.evaluate().isNotEmpty) return;
  }
  fail('Expected a selectable control labelled $label.');
}

/// The editor names a section once and places its choices after that heading,
/// so a labelled group must lead to at least one operable control.
bool _hasChoiceAfter(WidgetTester tester, Pattern heading) {
  final elements = <Element>[];
  void visit(Element element) {
    elements.add(element);
    element.visitChildren(visit);
  }

  visit(tester.element(find.byType(Scrollable).first));

  var inside = false;
  for (final element in elements) {
    final widget = element.widget;
    final label = widget is Text ? widget.data : null;
    if (!inside) {
      if (label != null && heading.allMatches(label).isNotEmpty) inside = true;
      continue;
    }
    if (_isOperable(widget)) return true;
  }
  return false;
}

Future<void> _tapOption(WidgetTester tester, Finder label) async {
  await _reveal(tester, label);
  for (var index = 0; index < label.evaluate().length; index++) {
    final option = label.at(index);
    if (find.ancestor(of: option, matching: _operable).evaluate().isEmpty) {
      continue;
    }
    await tester.ensureVisible(option);
    await _pumpFrames(tester);
    await tester.tap(option);
    await _pumpFrames(tester);
    return;
  }
  fail('Could not operate the control labelled $label.');
}

/// The preview is announced as a named region, so it is distinguishable from
/// the option list and from the content behind the editor. The largest matching
/// region is the preview surface rather than a caption inside it.
Future<void> _expectVisiblePreview(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final preview = find.bySemanticsLabel(
      RegExp('preview', caseSensitive: false),
    );
    expect(
      preview,
      findsWidgets,
      reason: 'The Home & Cards editor must announce its preview region.',
    );

    await tester.ensureVisible(preview.first);
    await tester.pump();

    final viewport = tester.getRect(find.byType(Scrollable).first);
    Rect? visible;
    for (var index = 0; index < preview.evaluate().length; index++) {
      final rect = tester.getRect(preview.at(index));
      if (rect.width <= 0 || rect.height <= 0) continue;
      if (!viewport.contains(rect.center)) continue;
      final best = visible;
      final area = rect.width * rect.height;
      if (best == null || area > best.width * best.height) visible = rect;
    }

    expect(
      visible,
      isNotNull,
      reason: 'The preview must be on screen when the editor opens.',
    );
  } finally {
    handle.dispose();
  }
}

void main() {
  testWidgets('Appearance lists Theme & Colors and Home & Cards entries', (
    tester,
  ) async {
    await _pump(tester);
    await _reveal(tester, find.text('Appearance'));

    expect(find.text('Appearance'), findsOneWidget);
    expect(_themeEntry(), findsOneWidget);
    expect(_homeEntry(), findsOneWidget);

    final labels = _listLabels(tester);
    final appearance = labels.indexOf('Appearance');
    final theme = _indexOfLabel(labels, _themeEntryPattern);
    final home = _indexOfLabel(labels, _homeEntryPattern);
    final local = labels.indexOf('Local data');

    expect(appearance, greaterThanOrEqualTo(0));
    expect(
      theme,
      greaterThan(appearance),
      reason: 'Theme & Colors belongs below the Appearance header.',
    );
    expect(
      home,
      greaterThan(theme),
      reason: 'Home & Cards follows Theme & Colors in the group.',
    );
    expect(
      local == -1 || local > home,
      isTrue,
      reason: 'Both entries stay inside Appearance and before Local data.',
    );

    final viewport = tester.getRect(find.byType(Scrollable).first);
    for (final entry in <Finder>[_themeEntry(), _homeEntry()]) {
      await tester.ensureVisible(entry.first);
      await tester.pump();
      expect(
        tester.getRect(entry).overlaps(viewport),
        isTrue,
        reason: 'The entry must be reachable from the Appearance group.',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Theme & Colors drafts mode and AMOLED until Apply', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _openEntry(tester, _themeEntry());

    expect(find.byType(SettingsPage), findsNothing);
    expect(_backControl(), findsWidgets);

    for (final mode in ['System', 'Light', 'Dark']) {
      final option = _inEditor(
        RegExp('^\\s*$mode\\b', caseSensitive: false),
      );
      expect(
        option,
        findsWidgets,
        reason: 'Theme & Colors must offer the $mode mode.',
      );
      _expectOperable(option);
    }

    Finder amoled() => _inEditor(RegExp('amoled', caseSensitive: false));
    expect(
      amoled(),
      findsWidgets,
      reason: 'Theme & Colors must offer an AMOLED control.',
    );
    _expectOperable(amoled());

    expect(
      _inEditor(RegExp('colou?r|palette', caseSensitive: false)),
      findsWidgets,
      reason: 'Theme & Colors must offer colour choices.',
    );

    await _tapOption(
      tester,
      _inEditor(RegExp(r'^\s*dark\b', caseSensitive: false)),
    );
    expect(harness.saves, isEmpty, reason: 'A draft mode change is not saved.');
    expect(harness.notifier.value.themeMode, ThemeMode.system);

    await _tapOption(tester, amoled());
    expect(harness.saves, isEmpty, reason: 'The AMOLED draft is not saved.');
    expect(harness.notifier.value.themeMode, ThemeMode.system);

    final apply = _action('Apply');
    expect(apply, findsWidgets, reason: 'The draft editor must offer Apply.');
    await _tapOption(tester, apply);
    await _pumpFrames(tester);

    expect(harness.saves, hasLength(1));
    expect(harness.saves.single.themeMode, ThemeMode.dark);
    expect(harness.notifier.value.themeMode, ThemeMode.dark);

    // Appearance is edited here, not with a demo companion or stage.
    expect(find.byType(InstalledCompanionView), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Home & Cards opens its own layout, card style and animation', (
    tester,
  ) async {
    await _pump(tester);
    await _openEntry(tester, _homeEntry());

    expect(find.byType(SettingsPage), findsNothing);
    expect(_backControl(), findsWidgets);

    for (final (name, pattern) in [
      ('layout', RegExp('layout', caseSensitive: false)),
      ('card style', RegExp('card', caseSensitive: false)),
      ('animation', RegExp('animation|motion|effect', caseSensitive: false)),
    ]) {
      expect(
        _inEditor(pattern),
        findsWidgets,
        reason: 'Home & Cards must expose $name choices.',
      );
      expect(
        _hasChoiceAfter(tester, pattern),
        isTrue,
        reason: 'Home & Cards must offer a $name control.',
      );
    }

    // The editor previews cards; it does not ship a demo companion.
    expect(find.byType(InstalledCompanionView), findsNothing);

    await tester.tap(_backControl().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Home & Cards shows a visible preview of the selected cards', (
    tester,
  ) async {
    await _pump(tester);
    await _openEntry(tester, _homeEntry());

    await _expectVisiblePreview(tester);
    expect(find.byType(InstalledCompanionView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
