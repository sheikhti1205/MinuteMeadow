import 'dart:convert';

import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus finalization rolls back both writes if a transaction fails', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.writeState('focus', 'before');
    final row = _session();
    await expectLater(
      database.transaction(() async {
        await database.record(row);
        await database.writeState('focus', 'after');
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await database.sessions(), isEmpty);
    expect(await database.readState('focus'), 'before');
    await database.record(row);
    await database.record(row);
    expect((await database.sessions()).single.id, 'focus-1');
  });

  test('backup rejects duplicate session IDs before replacing data', () {
    final row = _session().toJson();
    final source = jsonEncode({
      'schema': 1,
      'settings': const AppSettings().toJson(),
      'sessions': [row, row],
    });
    expect(() => DataBackup.decode(source), throwsFormatException);
  });
}

SessionRecord _session() => SessionRecord(
  id: 'focus-1',
  startedAt: DateTime.utc(2026, 1, 5, 12),
  finishedAt: DateTime.utc(2026, 1, 5, 12, 1),
  intended: const Duration(minutes: 1),
  actual: const Duration(minutes: 1),
  completed: true,
);
