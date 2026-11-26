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
}
