import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'session_record.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);

  factory LocalDatabase.open() => LocalDatabase(
    driftDatabase(
      name: 'companion_focus',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.base.resolve('sqlite3.wasm'),
        driftWorker: Uri.base.resolve('drift_worker.js'),
      ),
    ),
  );

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''
        CREATE TABLE app_state (
          name TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE focus_sessions (
          id TEXT PRIMARY KEY NOT NULL,
          started_at INTEGER NOT NULL,
          finished_at INTEGER NOT NULL,
          intended_ms INTEGER NOT NULL CHECK (intended_ms > 0),
          actual_ms INTEGER NOT NULL CHECK (actual_ms BETWEEN 0 AND intended_ms),
          completed INTEGER NOT NULL CHECK (completed IN (0, 1))
        )
      ''');
      await customStatement('''
        CREATE INDEX focus_sessions_finished ON focus_sessions(finished_at)
      ''');
    },
  );

  Future<String?> readState(String name) async {
    final row = await customSelect(
      'SELECT value FROM app_state WHERE name = ?',
      variables: [Variable<String>(name)],
    ).getSingleOrNull();
    return row?.read<String>('value');
  }

  Future<void> writeState(String name, String value) => customStatement(
    '''INSERT INTO app_state (name, value) VALUES (?, ?)
       ON CONFLICT(name) DO UPDATE SET value = excluded.value''',
    [name, value],
  );

  Future<List<SessionRecord>> sessions() async {
    final rows = await customSelect(
      'SELECT * FROM focus_sessions ORDER BY finished_at DESC, id DESC',
    ).get();
    return [
      for (final row in rows)
        SessionRecord(
          id: row.read<String>('id'),
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('started_at'),
            isUtc: true,
          ),
          finishedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('finished_at'),
            isUtc: true,
          ),
          intended: Duration(milliseconds: row.read<int>('intended_ms')),
          actual: Duration(milliseconds: row.read<int>('actual_ms')),
          completed: row.read<int>('completed') == 1,
        ),
    ];
  }

  Future<void> record(SessionRecord session) => customStatement(
    '''INSERT INTO focus_sessions
       (id, started_at, finished_at, intended_ms, actual_ms, completed)
       VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING''',
    [
      session.id,
      session.startedAt.millisecondsSinceEpoch,
      session.finishedAt.millisecondsSinceEpoch,
      session.intended.inMilliseconds,
      session.actual.inMilliseconds,
      session.completed ? 1 : 0,
    ],
  );

  Future<void> replaceData(
    String settings,
    List<SessionRecord> importedSessions,
  ) => transaction(() async {
    await customStatement(
      "DELETE FROM app_state WHERE name IN ('focus', 'clock', 'settings')",
    );
    await customStatement('DELETE FROM focus_sessions');
    await writeState('settings', settings);
    for (final session in importedSessions) {
      await record(session);
    }
  });
}
