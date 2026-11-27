import 'dart:io';
import 'dart:typed_data';

import 'package:companion_focus/core/storage/local_database.dart';
import 'package:companion_focus/features/focus/background/focus_wallpaper_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips the photo bytes and every adjustment', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);

    expect(await store.read(), isNull);
    expect(FocusWallpaperPhoto.maxBytes, LocalDatabase.focusWallpaperMaxBytes);

    final source = Uint8List.fromList([0, 1, 2, 3, 127, 255]);
    final photo = FocusWallpaperPhoto(
      bytes: source,
      placement: WallpaperPlacement.contain,
      alignmentX: -0.5,
      alignmentY: 0.75,
      strength: 40,
    );
    source[0] = 99;
    expect(photo.bytes, [0, 1, 2, 3, 127, 255]);
    expect(photo.byteLength, 6);
    expect(
      () => photo.bytes[0] = 99,
      throwsA(isA<UnsupportedError>()),
      reason: 'The stored bytes must be a read-only view.',
    );

    await store.write(photo);

    final saved = await store.read();
    expect(saved, isNotNull);
    expect(saved!.placement, WallpaperPlacement.contain);
    expect(saved.alignmentX, -0.5);
    expect(saved.alignmentY, 0.75);
    expect(saved.strength, 40);
    expect(saved.bytes, [0, 1, 2, 3, 127, 255]);
  });

  test('an adjustment-only copy reuses the immutable photo buffer', () {
    final photo = FocusWallpaperPhoto(
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    final adjusted = photo.copyWith(
      placement: WallpaperPlacement.tile,
      alignmentX: 1,
      alignmentY: -1,
      strength: 0,
    );

    expect(identical(adjusted.bytes, photo.bytes), isTrue);
    expect(adjusted.bytes, [1, 2, 3]);
    expect(adjusted.placement, WallpaperPlacement.tile);
    expect(adjusted.alignmentX, 1);
    expect(adjusted.alignmentY, -1);
    expect(adjusted.strength, 0);
    expect(photo.placement, WallpaperPlacement.cover);
    expect(photo.alignmentX, 0);
    expect(photo.strength, 100);
    expect(() => adjusted.bytes[0] = 9, throwsA(isA<UnsupportedError>()));
    expect(() => photo.copyWith(strength: 101), throwsArgumentError);
    expect(() => photo.copyWith(alignmentX: -2), throwsArgumentError);

    final replacement = Uint8List.fromList([4, 5]);
    final replaced = photo.copyWith(bytes: replacement);
    replacement[0] = 9;
    expect(replaced.bytes, [4, 5]);
    expect(identical(replaced.bytes, photo.bytes), isFalse);
  });

  test('replacing a photo keeps one slot and swaps bytes and metadata', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);

    await store.write(_photo(bytes: [1, 2, 3]));
    await store.write(
      _photo(
        bytes: [9, 8],
        placement: WallpaperPlacement.tile,
        alignmentX: 1,
        alignmentY: -1,
        strength: 0,
      ),
    );

    final rows = await database
        .customSelect('SELECT COUNT(*) AS count FROM focus_wallpaper')
        .getSingle();
    expect(rows.read<int>('count'), 1);

    final saved = (await store.read())!;
    expect(saved.bytes, [9, 8]);
    expect(saved.placement, WallpaperPlacement.tile);
    expect(saved.alignmentX, 1);
    expect(saved.alignmentY, -1);
    expect(saved.strength, 0);
  });

  test('adjusts placement, alignment and strength independently', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);

    expect(await store.adjust(alignmentX: 1), isFalse);
    expect(await store.read(), isNull);

    await store.write(
      _photo(alignmentX: -0.25, alignmentY: -0.5, strength: 60),
    );

    expect(await store.adjust(alignmentX: 1), isTrue);
    var saved = (await store.read())!;
    expect(saved.alignmentX, 1);
    expect(saved.alignmentY, -0.5);
    expect(saved.strength, 60);
    expect(saved.placement, WallpaperPlacement.cover);

    expect(await store.adjust(strength: 0), isTrue);
    saved = (await store.read())!;
    expect(saved.strength, 0);
    expect(saved.alignmentX, 1);
    expect(saved.alignmentY, -0.5);

    expect(await store.adjust(placement: WallpaperPlacement.tile), isTrue);
    saved = (await store.read())!;
    expect(saved.placement, WallpaperPlacement.tile);
    expect(saved.strength, 0);
    expect(saved.alignmentX, 1);
    expect(saved.alignmentY, -0.5);

    expect(await store.adjust(), isTrue);
    await expectLater(store.adjust(alignmentX: 1.5), throwsArgumentError);
    await expectLater(store.adjust(strength: 101), throwsArgumentError);
    saved = (await store.read())!;
    expect(saved.alignmentX, 1);
    expect(saved.strength, 0);
  });

  test('a rolled back write keeps the previous photo', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);
    await store.write(_photo(bytes: [1]));

    await expectLater(
      database.transaction(() async {
        await store.write(_photo(bytes: [2]));
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    expect((await store.read())!.bytes, [1]);
  });

  test('rejects empty and oversized photos before writing', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);
    await store.write(_photo(bytes: [7]));

    expect(() => _photo(bytes: const []), throwsArgumentError);
    expect(
      () => _photo(
        bytes: List<int>.filled(FocusWallpaperPhoto.maxBytes + 1, 0),
      ),
      throwsArgumentError,
    );

    expect((await store.read())!.bytes, [7]);
  });

  test('accepts a photo of exactly the shared size cap', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);
    expect(FocusWallpaperPhoto.maxBytes, LocalDatabase.focusWallpaperMaxBytes);

    await store.write(
      FocusWallpaperPhoto(bytes: Uint8List(FocusWallpaperPhoto.maxBytes)),
    );

    final saved = await store.read();
    expect(saved, isNotNull);
    expect(saved!.byteLength, FocusWallpaperPhoto.maxBytes);
  });

  test('the table rejects an oversized blob that bypasses the store', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);

    await expectLater(
      database.customStatement(
        'INSERT INTO focus_wallpaper '
        '(id, placement, alignment_x, alignment_y, strength, bytes) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          LocalDatabase.focusWallpaperSlot,
          'cover',
          0.0,
          0.0,
          100,
          Uint8List(LocalDatabase.focusWallpaperMaxBytes + 1),
        ],
      ),
      throwsA(anything),
    );

    expect(await store.read(), isNull);
  });

  test('an ordinary restore keeps the photo and a full reset clears it', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);
    await database.writeState('companion', '{"schema":"companion.library/1"}');
    await store.write(
      _photo(
        bytes: [3, 4],
        placement: WallpaperPlacement.contain,
        alignmentX: 0.5,
        strength: 30,
      ),
    );

    await database.replaceData('{"schema":2}', []);

    var saved = await store.read();
    expect(saved, isNotNull);
    expect(saved!.bytes, [3, 4]);
    expect(saved.placement, WallpaperPlacement.contain);
    expect(saved.alignmentX, 0.5);
    expect(saved.strength, 30);

    await database.replaceData('{"schema":2}', [], clearPacks: true);

    expect(await store.read(), isNull);
    expect(await database.readState('companion'), isNull);
  });

  test('a rolled back full reset keeps the photo', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);
    await store.write(_photo(bytes: [5]));

    await expectLater(
      database.transaction(() async {
        await database.replaceData('{"schema":2}', [], clearPacks: true);
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    expect((await store.read())!.bytes, [5]);
  });

  test('upgrades a schema 2 database without touching saved data', () async {
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
              completed INTEGER NOT NULL CHECK (completed IN (0, 1)),
              label TEXT,
              note TEXT
            )
          ''');
          raw.execute(
            'CREATE INDEX focus_sessions_finished ON focus_sessions(finished_at)',
          );
          raw.execute(
            "INSERT INTO app_state (name, value) VALUES ('settings', 'v2')",
          );
          raw.execute('''
            INSERT INTO focus_sessions
              (id, started_at, finished_at, intended_ms, actual_ms, completed, label, note)
            VALUES ('kept', 1000, 2000, 60000, 60000, 1, 'Deep work', 'Kept.')
          ''');
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(database.close);
    final store = FocusWallpaperStore(database);

    final sessions = await database.sessions();
    expect(sessions.single.id, 'kept');
    expect(sessions.single.label, 'Deep work');
    expect(sessions.single.note, 'Kept.');
    expect(await database.readState('settings'), 'v2');
    expect(await store.read(), isNull);

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

    await store.write(_photo(bytes: [5]));
    expect((await store.read())!.bytes, [5]);
  });

  test('upgrades a schema 1 database straight to schema 3', () async {
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
            "INSERT INTO app_state (name, value) VALUES ('settings', 'v1')",
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
    final store = FocusWallpaperStore(database);

    final sessions = await database.sessions();
    expect(sessions.single.id, 'legacy');
    expect(sessions.single.label, isNull);
    expect(sessions.single.note, isNull);
    expect(await database.readState('settings'), 'v1');

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 3);

    await store.write(_photo(bytes: [6]));
    expect((await store.read())!.bytes, [6]);
  });

  test(
    'a failed schema 3 step rolls back schema 2 and a retry upgrades once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'focus_wallpaper_migration_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/focus.sqlite');

      final broken = LocalDatabase(
        NativeDatabase(
          file,
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
              "INSERT INTO app_state (name, value) VALUES ('settings', 'v1')",
            );
            raw.execute('''
              INSERT INTO focus_sessions
                (id, started_at, finished_at, intended_ms, actual_ms, completed)
              VALUES ('legacy', 1000, 2000, 60000, 60000, 1)
            ''');
            // Occupying the schema 3 table name makes the last upgrade step
            // fail after the schema 2 step has already run.
            raw.execute('CREATE TABLE focus_wallpaper (id INTEGER)');
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      await expectLater(
        broken.customSelect('SELECT COUNT(*) AS count FROM focus_sessions').get(),
        throwsA(anything),
      );
      await broken.close();

      final repaired = LocalDatabase(
        NativeDatabase(
          file,
          setup: (raw) => raw.execute('DROP TABLE focus_wallpaper'),
        ),
      );
      addTearDown(repaired.close);
      final store = FocusWallpaperStore(repaired);

      final sessions = await repaired.sessions();
      expect(sessions.single.id, 'legacy');
      expect(sessions.single.label, isNull);
      expect(sessions.single.note, isNull);
      expect(await repaired.readState('settings'), 'v1');

      // A committed schema 2 step would make this retry fail with a duplicate
      // column instead of exposing each column once.
      final columns = await repaired
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

      final version = await repaired
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 3);

      await store.write(_photo(bytes: [8]));
      expect((await store.read())!.bytes, [8]);
    },
  );

  test('a new database starts at schema 3 with an empty slot', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    expect(await FocusWallpaperStore(database).read(), isNull);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 3);

    final tables = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    expect(
      tables.map((table) => table.read<String>('name')),
      contains('focus_wallpaper'),
    );
  });

  test('a saved photo survives closing and reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('focus_wallpaper_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/focus.sqlite');

    final first = LocalDatabase(NativeDatabase(file));
    try {
      await FocusWallpaperStore(first).write(
        _photo(
          bytes: [1, 2, 3],
          placement: WallpaperPlacement.tile,
          alignmentY: 1,
          strength: 25,
        ),
      );
    } finally {
      await first.close();
    }

    final second = LocalDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final saved = await FocusWallpaperStore(second).read();
    expect(saved, isNotNull);
    expect(saved!.bytes, [1, 2, 3]);
    expect(saved.placement, WallpaperPlacement.tile);
    expect(saved.alignmentY, 1);
    expect(saved.strength, 25);
  });
}

FocusWallpaperPhoto _photo({
  List<int>? bytes,
  WallpaperPlacement placement = WallpaperPlacement.cover,
  double alignmentX = 0,
  double alignmentY = 0,
  int strength = 100,
}) => FocusWallpaperPhoto(
  bytes: Uint8List.fromList(bytes ?? const [0, 1, 2, 3, 255]),
  placement: placement,
  alignmentX: alignmentX,
  alignmentY: alignmentY,
  strength: strength,
);
