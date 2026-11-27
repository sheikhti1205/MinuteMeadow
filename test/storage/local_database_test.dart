import 'dart:convert';

import 'package:companion_focus/app/bootstrap.dart';
import 'package:companion_focus/core/storage/data_backup.dart';
import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/core/storage/session_record.dart';
import 'package:companion_focus/features/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unreadable settings do not hide saved session history', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    const futureSettings = '{"schema":2}';
    await database.writeState('settings', futureSettings);
    await database.record(_session());

    final startup = await container.read(startupProvider.future);

    expect(startup.settings.focusMinutes, 25);
    expect(startup.sessions.single.id, 'focus-1');
    expect(await database.readState('settings'), futureSettings);
  });

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

  test('restore replaces timers and history while only clear removes packs', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const settings = AppSettings(focusMinutes: 37);
    const library = '{"schema":"companion.library/1","packs":{}}';
    await database.writeState('focus', 'active focus');
    await database.writeState('clock', 'active clock');
    await database.writeState('companion', library);
    await database.record(_session());
    final restored = SessionRecord(
      id: 'restored',
      startedAt: DateTime.utc(2026, 1, 6, 12),
      finishedAt: DateTime.utc(2026, 1, 6, 12, 3),
      intended: const Duration(minutes: 3),
      actual: const Duration(minutes: 3),
      completed: true,
      label: 'Deep work',
      note: 'Restored with the backup.',
    );

    await database.replaceData(settings.encode(), [restored]);

    expect(await database.readState('settings'), settings.encode());
    expect(await database.readState('focus'), isNull);
    expect(await database.readState('clock'), isNull);
    expect(await database.readState('companion'), library);
    final saved = (await database.sessions()).single;
    expect(saved.id, 'restored');
    expect(saved.label, 'Deep work');
    expect(saved.note, 'Restored with the backup.');

    await database.replaceData(const AppSettings().encode(), [], clearPacks: true);

    expect(await database.readState('companion'), isNull);
    expect(await database.sessions(), isEmpty);
  });

  test('upgrades a schema 1 database without losing saved history', () async {
    final database = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE app_state (
              name TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            )
          ''');
          raw.execute('''
            CREATE TABLE focus_sessions (
              id TEXT PRIMARY KEY NOT NULL,
              started_at INTEGER NOT NULL,
              finished_at INTEGER NOT NULL,
              intended_ms INTEGER NOT NULL CHECK (intended_ms > 0),
              actual_ms INTEGER NOT NULL CHECK (actual_ms BETWEEN 0 AND intended_ms),
              completed INTEGER NOT NULL CHECK (completed IN (0, 1))
            )
          ''');
          raw.execute(
            'CREATE INDEX focus_sessions_finished ON focus_sessions(finished_at)',
          );
          raw.execute(
            "INSERT INTO app_state (name, value) VALUES ('settings', 'legacy')",
          );
          raw.execute('''
            INSERT INTO focus_sessions
              (id, started_at, finished_at, intended_ms, actual_ms, completed)
            VALUES ('legacy', 1000, 2000, 60000, 60000, 1)
          ''');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(database.close);

    final legacy = (await database.sessions()).single;
    expect(legacy.id, 'legacy');
    expect(legacy.startedAt.millisecondsSinceEpoch, 1000);
    expect(legacy.finishedAt.millisecondsSinceEpoch, 2000);
    expect(legacy.intended, const Duration(minutes: 1));
    expect(legacy.actual, const Duration(minutes: 1));
    expect(legacy.completed, isTrue);
    expect(legacy.label, isNull);
    expect(legacy.note, isNull);
    expect(await database.readState('settings'), 'legacy');

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 3);

    final columns = await database
        .customSelect('PRAGMA table_info(focus_sessions)')
        .get();
    expect(
      columns.map((column) => column.read<String>('name')),
      [
        'id',
        'started_at',
        'finished_at',
        'intended_ms',
        'actual_ms',
        'completed',
        'label',
        'note',
      ],
    );

    await database.updateSessionDetails(
      'legacy',
      const SessionDetails(label: 'Deep work', note: 'After migration.'),
    );
    final migrated = (await database.sessions()).single;
    expect(migrated.label, 'Deep work');
    expect(migrated.note, 'After migration.');
    expect(migrated.startedAt.millisecondsSinceEpoch, 1000);
    expect(migrated.finishedAt.millisecondsSinceEpoch, 2000);
    expect(migrated.intended, const Duration(minutes: 1));
    expect(migrated.actual, const Duration(minutes: 1));
    expect(migrated.completed, isTrue);
  });

  test('records description and updates only the details', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final original = _session().withDetails(
      const SessionDetails(label: 'Deep work', note: 'No phone.'),
    );
    await database.record(original);

    final saved = (await database.sessions()).single;
    expect(saved.label, 'Deep work');
    expect(saved.note, 'No phone.');

    await database.updateSessionDetails(
      'focus-1',
      const SessionDetails(label: 'Planning', note: 'Drafted the plan.'),
    );

    final updated = (await database.sessions()).single;
    expect(updated.label, 'Planning');
    expect(updated.note, 'Drafted the plan.');
    expect(updated.startedAt, original.startedAt);
    expect(updated.finishedAt, original.finishedAt);
    expect(updated.intended, original.intended);
    expect(updated.actual, original.actual);
    expect(updated.completed, original.completed);
  });

  test('deletes only selected sessions and reports the removed count', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.record(_session(id: 'first'));
    await database.record(_session(id: 'second'));
    await database.record(_session(id: 'third'));

    final removed = await database.deleteSessions({'first', 'missing'});

    expect(removed, 1);
    expect(
      (await database.sessions()).map((session) => session.id),
      ['third', 'second'],
    );
    expect(await database.deleteSessions(const {}), 0);
  });

  test('deletes a large selection across bounded batches', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const total = 1205;
    for (var index = 0; index < total; index++) {
      await database.record(_session(id: 'bulk-$index'));
    }

    final removed = await database.deleteSessions({
      for (var index = 0; index < total - 5; index++) 'bulk-$index',
      'missing',
    });

    expect(removed, total - 5);
    expect(
      (await database.sessions()).map((session) => session.id).toSet(),
      {'bulk-1200', 'bulk-1201', 'bulk-1202', 'bulk-1203', 'bulk-1204'},
    );
  });
}

SessionRecord _session({String id = 'focus-1'}) => SessionRecord(
  id: id,
  startedAt: DateTime.utc(2026, 1, 5, 12),
  finishedAt: DateTime.utc(2026, 1, 5, 12, 1),
  intended: const Duration(minutes: 1),
  actual: const Duration(minutes: 1),
  completed: true,
);
