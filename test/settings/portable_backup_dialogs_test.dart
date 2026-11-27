import 'dart:async';

import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/focus/focus_engine.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:companion_focus/features/settings/portable_backup_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<SessionRecord> _sessions() {
  final finish = DateTime.utc(2026, 11, 26, 12);
  return [
    SessionRecord(
      id: 'first',
      startedAt: finish.subtract(const Duration(minutes: 25)),
      finishedAt: finish,
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
    ),
    SessionRecord(
      id: 'second',
      startedAt: finish.subtract(const Duration(minutes: 15)),
      finishedAt: finish,
      intended: const Duration(minutes: 15),
      actual: const Duration(minutes: 15),
      completed: true,
    ),
  ];
}

const AppSettings _settings = AppSettings(
  focusMinutes: 30,
  shortBreakMinutes: 10,
  longBreakMinutes: 20,
  themeMode: ThemeMode.dark,
  notifications: true,
  sound: false,
  haptics: true,
  reducedMotion: true,
  lowPower: true,
);

DataBackup _legacyBackup({int sessionCount = 2}) => DataBackup(
  settings: _settings,
  sessions: _sessions().take(sessionCount).toList(growable: false),
);

DataBackup _portableBackup({int sessionCount = 2}) => DataBackup.portable(
  settings: _settings,
  sessions: _sessions().take(sessionCount).toList(growable: false),
  focusPresets: const FocusPresetsDocument(
    presets: <FocusPresetDocument>[
      FocusPresetDocument(
        id: FocusPreset.defaultsId,
        name: 'Default',
        settings: FocusSettings(),
      ),
      FocusPresetDocument(
        id: 'deep',
        name: 'Deep work',
        settings: FocusSettings(
          focusMinutes: 50,
          shortBreakMinutes: 10,
          longBreakMinutes: 20,
          sessionsPerCycle: 3,
        ),
      ),
    ],
    defaultId: FocusPreset.defaultsId,
  ),
  clockPresets: const ClockPresetsDocument(
    presets: <ClockPresetDocument>[
      ClockPresetDocument(
        id: 'tea',
        label: 'Tea',
        duration: Duration(minutes: 5),
      ),
      ClockPresetDocument(
        id: 'focus',
        label: 'Focus',
        duration: Duration(minutes: 25),
      ),
      ClockPresetDocument(
        id: 'nap',
        label: 'Nap',
        duration: Duration(minutes: 20),
      ),
    ],
  ),
);

Widget _host(void Function(BuildContext context) onPressed) => MaterialApp(
  theme: CompanionTheme.light,
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => Center(
        child: FilledButton(
          onPressed: () => onPressed(context),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Future<Completer<PortableBackupExportChoice?>> _openExport(
  WidgetTester tester, {
  required int sessionCount,
  int? focusPresetCount,
  int? clockPresetCount,
}) async {
  final result = Completer<PortableBackupExportChoice?>();
  await tester.pumpWidget(
    _host((BuildContext context) {
      unawaited(
        showPortableBackupExportDialog(
          context,
          sessionCount: sessionCount,
          focusPresetCount: focusPresetCount,
          clockPresetCount: clockPresetCount,
        ).then(result.complete),
      );
    }),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

Future<Completer<bool?>> _openImport(
  WidgetTester tester, {
  required DataBackup backup,
  required Future<void> Function(DataBackup) onReplace,
  String failureMessage = 'Could not restore the backup. Try again.',
}) async {
  final result = Completer<bool?>();
  await tester.pumpWidget(
    _host((BuildContext context) {
      unawaited(
        showPortableBackupImportDialog(
          context,
          backup: backup,
          onReplace: onReplace,
          failureMessage: failureMessage,
        ).then(result.complete),
      );
    }),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _pumpSummary(
  WidgetTester tester,
  DataBackup backup, {
  bool willReplace = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CompanionTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PortableBackupSummary(
              backup: backup,
              willReplace: willReplace,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('portable file save', () {
    testWidgets('lists the sections with presets off by default', (
      tester,
    ) async {
      final result = await _openExport(
        tester,
        sessionCount: 2,
        focusPresetCount: 2,
        clockPresetCount: 3,
      );

      expect(find.text('Save backup'), findsOneWidget);
      expect(find.text('The file will include:'), findsOneWidget);
      expect(
        find.textContaining('Timer defaults, feedback and appearance'),
        findsOneWidget,
      );
      expect(find.textContaining('2 focus sessions'), findsOneWidget);
      expect(find.text('Include saved presets'), findsOneWidget);
      expect(
        find.textContaining('2 Focus and 3 Clock presets saved'),
        findsOneWidget,
      );
      expect(find.textContaining('never transferred'), findsOneWidget);
      expect(
        find.textContaining('one-off plans and laps are not included'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Saving does not change local data'),
        findsOneWidget,
      );

      final toggle = tester.widget<CheckboxListTile>(
        find.byKey(PortableBackupExportDialog.includePresetsKey),
      );
      expect(toggle.value, isFalse);

      await tester.tap(find.byKey(PortableBackupExportDialog.confirmKey));
      await tester.pumpAndSettle();

      final choice = await result.future;
      expect(choice, isNotNull);
      expect(choice!.includePresets, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirms the preset opt-in only after tapping save', (
      tester,
    ) async {
      final result = await _openExport(
        tester,
        sessionCount: 1,
        focusPresetCount: 1,
        clockPresetCount: 0,
      );

      await tester.tap(
        find.byKey(PortableBackupExportDialog.includePresetsKey),
      );
      await tester.pumpAndSettle();

      final toggle = tester.widget<CheckboxListTile>(
        find.byKey(PortableBackupExportDialog.includePresetsKey),
      );
      expect(toggle.value, isTrue);
      expect(
        find.textContaining('A later restore replaces saved presets'),
        findsOneWidget,
      );
      expect(result.isCompleted, isFalse);

      await tester.tap(find.byKey(PortableBackupExportDialog.confirmKey));
      await tester.pumpAndSettle();

      final choice = await result.future;
      expect(choice, isNotNull);
      expect(choice!.includePresets, isTrue);
    });

    testWidgets('cancel writes nothing and returns no choice', (tester) async {
      final result = await _openExport(
        tester,
        sessionCount: 2,
        focusPresetCount: 2,
        clockPresetCount: 3,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('disables the opt-in when no presets are saved', (
      tester,
    ) async {
      final result = await _openExport(
        tester,
        sessionCount: 2,
        focusPresetCount: 0,
        clockPresetCount: 0,
      );

      expect(find.text('No saved presets on this device.'), findsOneWidget);
      final toggle = tester.widget<CheckboxListTile>(
        find.byKey(PortableBackupExportDialog.includePresetsKey),
      );
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);

      await tester.tap(find.byKey(PortableBackupExportDialog.confirmKey));
      await tester.pumpAndSettle();

      final choice = await result.future;
      expect(choice, isNotNull);
      expect(choice!.includePresets, isFalse);
    });
  });

  group('shared backup summary', () {
    testWidgets('names preset sections and replacement consequences', (
      tester,
    ) async {
      await _pumpSummary(tester, _portableBackup());

      expect(find.textContaining('30 min focus'), findsOneWidget);
      expect(find.textContaining('2 focus sessions'), findsOneWidget);
      expect(find.text('Saved Focus presets: 2'), findsOneWidget);
      expect(find.text('Saved Clock presets: 3'), findsOneWidget);
      expect(
        find.textContaining('photos and companion packs are never transferred'),
        findsOneWidget,
      );
      expect(
        find.text('Active timers, one-off plans and laps are cleared.'),
        findsOneWidget,
      );
      expect(
        find.text('Nothing changes until you confirm.'),
        findsOneWidget,
      );
    });

    testWidgets('legacy paste keeps omitted presets and changes nothing yet', (
      tester,
    ) async {
      await _pumpSummary(tester, _legacyBackup(sessionCount: 1));

      expect(find.text('1 focus session'), findsOneWidget);
      expect(
        find.text('Saved Focus and Clock presets stay on this device.'),
        findsOneWidget,
      );
      expect(
        find.text('Wallpaper photos and companion packs are never transferred.'),
        findsOneWidget,
      );
      expect(
        find.text('Active timers, one-off plans and laps are cleared.'),
        findsOneWidget,
      );
      expect(
        find.text('Nothing changes until you confirm.'),
        findsOneWidget,
      );
    });

    testWidgets('a review preview states the data is unchanged', (
      tester,
    ) async {
      await _pumpSummary(tester, _legacyBackup(), willReplace: false);

      expect(
        find.text('Active timers, one-off plans and laps are not included.'),
        findsOneWidget,
      );
      expect(
        find.text('Review only; local data is not changed.'),
        findsOneWidget,
      );
    });
  });

  group('replacement preview', () {
    testWidgets('waits for confirmation and cancel leaves data alone', (
      tester,
    ) async {
      final replaced = <DataBackup>[];
      final result = await _openImport(
        tester,
        backup: _portableBackup(),
        onReplace: (DataBackup backup) async => replaced.add(backup),
      );

      expect(
        find.text('This file will replace your local data:'),
        findsOneWidget,
      );
      expect(find.text('Saved Focus presets: 2'), findsOneWidget);
      expect(find.text('Saved Clock presets: 3'), findsOneWidget);
      expect(find.text('Nothing changes until you confirm.'), findsOneWidget);
      expect(replaced, isEmpty);
      expect(result.isCompleted, isFalse);

      await tester.tap(find.byKey(PortableBackupImportDialog.cancelKey));
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(replaced, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows pending, then closes after a successful replace', (
      tester,
    ) async {
      final gate = Completer<void>();
      final replaced = <DataBackup>[];
      final result = await _openImport(
        tester,
        backup: _portableBackup(),
        onReplace: (DataBackup backup) async {
          replaced.add(backup);
          await gate.future;
        },
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.confirmKey));
      await tester.pump();

      expect(replaced, hasLength(1));
      expect(find.text('Restoring…'), findsOneWidget);
      expect(find.text('Restore backup'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(PortableBackupImportDialog.cancelKey),
            )
            .onPressed,
        isNull,
      );
      expect(result.isCompleted, isFalse);

      gate.complete();
      await tester.pumpAndSettle();

      expect(await result.future, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a failed replace stays open with its error and a retry', (
      tester,
    ) async {
      var attempts = 0;
      final result = await _openImport(
        tester,
        backup: _portableBackup(),
        onReplace: (DataBackup backup) async {
          attempts += 1;
          throw const FormatException('Storage is busy.');
        },
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Storage is busy.'), findsOneWidget);
      expect(find.text('Restoring…'), findsNothing);
      expect(result.isCompleted, isFalse);

      final confirm = find.byKey(PortableBackupImportDialog.confirmKey);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(PortableBackupImportDialog.cancelKey),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.cancelKey));
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('an unexpected failure uses the supplied message', (
      tester,
    ) async {
      final result = await _openImport(
        tester,
        backup: _portableBackup(),
        onReplace: (DataBackup backup) async => throw Exception('Disk gone.'),
        failureMessage: 'Could not restore the backup. Try again.',
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not restore the backup. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Disk gone.'), findsNothing);
      expect(result.isCompleted, isFalse);

      await tester.tap(find.byKey(PortableBackupImportDialog.cancelKey));
      await tester.pumpAndSettle();
      expect(await result.future, isNull);
    });

    testWidgets('a StateError re-enables retry and Cancel', (tester) async {
      final result = await _openImport(
        tester,
        backup: _portableBackup(),
        onReplace: (DataBackup backup) async {
          throw StateError('The backend channel closed.');
        },
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Could not restore the backup. Try again.'),
        findsOneWidget,
      );
      expect(find.text('The backend channel closed.'), findsNothing);
      expect(find.text('Restoring…'), findsNothing);
      expect(result.isCompleted, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(PortableBackupImportDialog.confirmKey),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(PortableBackupImportDialog.cancelKey),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(PortableBackupImportDialog.cancelKey));
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
