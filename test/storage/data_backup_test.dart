import 'dart:convert';

import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _legacySessionJson() => {
  'id': 'legacy',
  'startedAt': 1767614400000,
  'finishedAt': 1767614580000,
  'intendedMs': 180000,
  'actualMs': 180000,
  'completed': true,
};

Map<String, Object?> _defaultFocusPresetJson() => <String, Object?>{
  'id': 'defaults',
  'name': 'Default',
  'settings': <String, Object?>{
    'focusMinutes': 25,
    'shortBreakMinutes': 5,
    'longBreakMinutes': 15,
    'sessionsPerCycle': 4,
  },
};

Map<String, Object?> _schema2BackupJson() => <String, Object?>{
  'schema': 2,
  'app': 'minutemeadow',
  'scope': <String>['settings', 'sessions', 'focusPresets', 'clockPresets'],
  'settings': const AppSettings().toJson(),
  'sessions': <Object?>[
    {
      ..._legacySessionJson(),
      'label': 'Deep work',
      'note': 'Phone stayed in the drawer.',
    },
  ],
  'focusPresets': <String, Object?>{
    'defaultId': 'defaults',
    'autoAdvance': false,
    'presets': <Object?>[_defaultFocusPresetJson()],
  },
  'clockPresets': <String, Object?>{
    'presets': <Object?>[],
  },
};

void main() {
  test('decodes a schema 1 backup saved before labels and notes', () {
    final source = jsonEncode({
      'schema': 1,
      'settings': const AppSettings().toJson(),
      'sessions': [_legacySessionJson()],
    });

    final backup = DataBackup.decode(source);

    final session = backup.sessions.single;
    expect(session.id, 'legacy');
    expect(session.label, isNull);
    expect(session.note, isNull);
    expect(session.intended, const Duration(minutes: 3));
    expect(session.actual, const Duration(minutes: 3));
    expect(session.completed, isTrue);
  });

  test('round trips optional text and keeps the backup schema at 1', () {
    final session = SessionRecord(
      id: 'described',
      startedAt: DateTime.utc(2026, 1, 6, 12),
      finishedAt: DateTime.utc(2026, 1, 6, 12, 25),
      intended: const Duration(minutes: 25),
      actual: const Duration(minutes: 25),
      completed: true,
      label: 'Deep work',
      note: 'Phone stayed in the drawer.',
    );
    final encoded = DataBackup(
      settings: const AppSettings(),
      sessions: [session],
    ).encode();

    final json = jsonDecode(encoded) as Map<String, Object?>;
    expect(json['schema'], 1);
    final records = json['sessions'] as List<Object?>;
    final record = records.single as Map<String, Object?>;
    expect(record['label'], 'Deep work');
    expect(record['note'], 'Phone stayed in the drawer.');
    expect(record['intendedMs'], const Duration(minutes: 25).inMilliseconds);
    expect(record['actualMs'], const Duration(minutes: 25).inMilliseconds);

    final restored = DataBackup.decode(encoded).sessions.single;
    expect(restored.label, 'Deep work');
    expect(restored.note, 'Phone stayed in the drawer.');
    expect(restored.startedAt, session.startedAt);
    expect(restored.finishedAt, session.finishedAt);
    expect(restored.intended, session.intended);
    expect(restored.actual, session.actual);
    expect(restored.completed, session.completed);
  });

  test('normalizes blank optional text instead of storing it', () {
    final source = jsonEncode({
      'schema': 1,
      'settings': const AppSettings().toJson(),
      'sessions': [
        {..._legacySessionJson(), 'label': '   ', 'note': ''},
      ],
    });

    final session = DataBackup.decode(source).sessions.single;

    expect(session.label, isNull);
    expect(session.note, isNull);
  });

  test('rejects an overlong label before replacing data', () {
    final source = jsonEncode({
      'schema': 1,
      'settings': const AppSettings().toJson(),
      'sessions': [
        {..._legacySessionJson(), 'label': 'x' * (SessionDetails.maxLabelLength + 1)},
      ],
    });

    expect(() => DataBackup.decode(source), throwsFormatException);
  });

  test('rejects non-text optional fields', () {
    final source = jsonEncode({
      'schema': 1,
      'settings': const AppSettings().toJson(),
      'sessions': [
        {..._legacySessionJson(), 'note': 42},
      ],
    });

    expect(() => DataBackup.decode(source), throwsFormatException);
  });

  test('decodes an opt-in schema 2 backup with scoped presets', () {
    final backup = DataBackup.decode(jsonEncode(_schema2BackupJson()));

    expect(backup.settings.focusMinutes, 25);
    expect(backup.settings.themeMode.name, 'system');
    final session = backup.sessions.single;
    expect(session.id, 'legacy');
    expect(session.label, 'Deep work');
    expect(session.note, 'Phone stayed in the drawer.');
  });

  test('rejects duplicate focus preset ids in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    final focusPresets = json['focusPresets']! as Map<String, Object?>;
    (focusPresets['presets']! as List<Object?>).add(_defaultFocusPresetJson());

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects a schema 2 backup whose default preset is missing', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    final focusPresets = json['focusPresets']! as Map<String, Object?>;
    focusPresets['defaultId'] = 'missing';

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects one-off focus state in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    final focusPresets = json['focusPresets']! as Map<String, Object?>;
    focusPresets['oneOff'] = <String, Object?>{
      'focusMinutes': 30,
      'shortBreakMinutes': 5,
      'longBreakMinutes': 15,
      'sessionsPerCycle': 4,
    };

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects running state in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    json['running'] = true;

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects companion packs in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    json['packs'] = <Object?>[];

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects companion media in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    json['media'] = <Object?>[];

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects invalid focus preset durations in a schema 2 backup', () {
    expect(
      () => DataBackup.decode(jsonEncode(_schema2BackupJson())),
      returnsNormally,
    );

    final json = _schema2BackupJson();
    final focusPresets = json['focusPresets']! as Map<String, Object?>;
    final preset = (focusPresets['presets']! as List<Object?>).single
        as Map<String, Object?>;
    final settings = preset['settings']! as Map<String, Object?>;
    settings['focusMinutes'] = 0;

    expect(() => DataBackup.decode(jsonEncode(json)), throwsFormatException);
  });
}
