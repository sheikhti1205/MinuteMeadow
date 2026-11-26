import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'session_record.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);

  /// Identifiers bound per statement when deleting a selection.
  ///
  /// SQLite's legacy parameter limit is 999 (32766 since 3.32), so 500 keeps
  /// large history selections well inside every supported build while still
  /// covering a whole delete in a handful of statements.
  static const _deleteBatchSize = 500;

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
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(_createSchema),
    onUpgrade: (_, from, _) async {
      // Schema 2 adds optional descriptive text. Existing rows keep their
      // identifiers, timestamps and recorded durations; the new columns are
      // null until a person edits them.
      //
      // Drift runs `onUpgrade` outside a transaction (verified against
      // drift 2.35.4 `GeneratedDatabase.beforeOpen`), so both statements are
      // grouped here: either the database gains both columns or neither.
      if (from < 2) {
        await transaction(() async {
          await customStatement(
            'ALTER TABLE focus_sessions ADD COLUMN label TEXT',
          );
          await customStatement(
            'ALTER TABLE focus_sessions ADD COLUMN note TEXT',
          );
        });
      }
    },
  );

  Future<void> _createSchema() async {
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
        completed INTEGER NOT NULL CHECK (completed IN (0, 1)),
        label TEXT,
        note TEXT
      )
    ''');
    await customStatement('''
      CREATE INDEX focus_sessions_finished ON focus_sessions(finished_at)
    ''');
  }

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
          label: row.readNullable<String>('label'),
          note: row.readNullable<String>('note'),
        ),
    ];
  }

  Future<void> record(SessionRecord session) async {
    final details = SessionDetails.fromInput(
      label: session.label,
      note: session.note,
    );
    await customStatement(
      '''INSERT INTO focus_sessions
         (id, started_at, finished_at, intended_ms, actual_ms, completed, label, note)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING''',
      [
        session.id,
        session.startedAt.millisecondsSinceEpoch,
        session.finishedAt.millisecondsSinceEpoch,
        session.intended.inMilliseconds,
        session.actual.inMilliseconds,
        session.completed ? 1 : 0,
        details.label,
        details.note,
      ],
    );
  }

  /// Replaces only the optional label and note for one saved session.
  ///
  /// Durations, timestamps and the completion outcome are not part of the
  /// update, so this cannot rewrite recorded history.
  Future<void> updateSessionDetails(
    String id,
    SessionDetails details,
  ) {
    final normalized = SessionDetails.fromInput(
      label: details.label,
      note: details.note,
    );
    return transaction(() async {
      await customStatement(
        'UPDATE focus_sessions SET label = ?, note = ? WHERE id = ?',
        [normalized.label, normalized.note, id],
      );
    });
  }

  /// Deletes the selected sessions in one transaction.
  ///
  /// Identifiers are bound in bounded batches so a large selection never
  /// exceeds SQLite's parameter limit, while the surrounding transaction still
  /// makes the whole delete atomic. Returns how many rows were actually
  /// removed so the caller can reconcile its list even if some identifiers
  /// were already gone.
  Future<int> deleteSessions(Set<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    final ordered = ids.toList(growable: false);
    return transaction(() async {
      var removed = 0;
      for (var start = 0; start < ordered.length; start += _deleteBatchSize) {
        final end = math.min(start + _deleteBatchSize, ordered.length);
        final batch = ordered.sublist(start, end);
        final placeholders = List.filled(batch.length, '?').join(', ');
        final existing = await customSelect(
          'SELECT COUNT(*) AS count FROM focus_sessions '
          'WHERE id IN ($placeholders)',
          variables: [for (final id in batch) Variable<String>(id)],
        ).getSingle();
        final count = existing.read<int>('count');
        if (count == 0) continue;
        await customStatement(
          'DELETE FROM focus_sessions WHERE id IN ($placeholders)',
          batch,
        );
        removed += count;
      }
      return removed;
    });
  }

  Future<void> replaceData(
    String settings,
    List<SessionRecord> importedSessions, {
    bool clearPacks = false,
  }) => transaction(() async {
    if (clearPacks) {
      await customStatement('DELETE FROM app_state');
    } else {
      await customStatement(
        "DELETE FROM app_state WHERE name IN ('focus', 'clock', 'settings')",
      );
    }
    await customStatement('DELETE FROM focus_sessions');
    await writeState('settings', settings);
    for (final session in importedSessions) {
      await record(session);
    }
  });
}
