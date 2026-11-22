// Tests of the opener: schema, versions and quarantine (E-V1 to E-V5, E-X1 of
// rtdb_storage_engine_design.md section 15; new, Android crashes or asserts in these cases).
import 'dart:io';

import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;

  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  /// Runs [change] on a raw connection to the store file, as another program would.
  void changeFile(void Function(sqlite.Database db) change) {
    final sqlite.Database db = fixture.raw();
    try {
      change(db);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  /// Creates the store, writes one pending write and closes it.
  Future<void> createStoreWithOneWrite() async {
    final SqliteConnection store = await fixture.open();
    expect(store.begin(), isTrue);
    store.execute(
      "INSERT INTO user_writes (id, path, type, value) VALUES (7, '/a/', 'o', x'01')",
    );
    store.commit();
    store.close();
  }

  int countWrites(SqliteConnection store) {
    return store.select('SELECT count(*) AS n FROM user_writes').first['n']
        as int;
  }

  test(
    'a new store has the schema, the version and the pragmas of this code',
    () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      final sqlite.Database db = store.debugDatabase!;

      expect(store.state, StoreState.durable);
      expect(
        StoreFixture.scalar(db, 'PRAGMA application_id'),
        SqliteSchema.applicationId,
      );
      expect(db.userVersion, 1000);
      expect(
        '${StoreFixture.scalar(db, 'PRAGMA journal_mode')}'.toLowerCase(),
        'wal',
      );
      expect(StoreFixture.scalar(db, 'PRAGMA auto_vacuum'), 2); // incremental
      expect(StoreFixture.scalar(db, 'PRAGMA synchronous'), 2); // full
      final List<String> tables = <String>[
        for (final sqlite.Row row in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        ))
          row['name'] as String,
      ];
      expect(tables, <String>[
        'lease',
        'server_cache',
        'tracked_keys',
        'tracked_queries',
        'user_writes',
      ]);
      expect(fixture.log, isEmpty);
    },
  );

  test('a store keeps its rows across a close and an open', () async {
    await createStoreWithOneWrite();

    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(store.state, StoreState.durable);
    expect(countWrites(store), 1);
  });

  test(
    'E-V1 a file of a newer major version is moved aside and the store starts empty',
    () async {
      await createStoreWithOneWrite();
      changeFile((sqlite.Database db) => db.userVersion = 2000);

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(countWrites(store), 0);
      expect(store.debugDatabase!.userVersion, 1000);
      final List<File> copies = SqliteFiles.badCopies(fixture.path);
      expect(copies.where((File f) => !f.path.endsWith('-wal')), hasLength(1));
      expect(fixture.log.single, contains('written by a newer version'));
      expect(fixture.log.single, contains('moved aside'));
    },
  );

  test(
    'E-V1 a newer file in use by a live owner is left alone; the store is memory-only',
    () async {
      final SqliteConnection owner = await fixture.open();
      addTearDown(owner.close);
      changeFile((sqlite.Database db) => db.userVersion = 2000);

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.memoryOnly);
      expect(SqliteFiles.badCopies(fixture.path), isEmpty);
      expect(File(fixture.path).existsSync(), isTrue);
      expect(fixture.clock.delays, isEmpty);
    },
  );

  test(
    'E-V2 a file of another application is moved aside; no log stays with the new file',
    () async {
      Directory(fixture.directory).createSync(recursive: true);
      changeFile((sqlite.Database db) {
        db.execute('CREATE TABLE notes (body TEXT)');
        db.execute("INSERT INTO notes VALUES ('kept for diagnosis')");
      });
      // A stray log next to the file must not end up next to the new file of the same name.
      File('${fixture.path}-wal').writeAsStringSync('old log');

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      final List<File> copies = SqliteFiles.badCopies(fixture.path);
      expect(copies.where((File f) => !f.path.endsWith('-wal')), hasLength(1));
      final File log = File('${fixture.path}-wal');
      // The new store's own log is binary, so compare bytes, not text.
      expect(
        log.existsSync() ? log.readAsBytesSync() : <int>[],
        isNot('old log'.codeUnits),
      );
      expect(fixture.log.single, contains('not a Realtime Database cache'));
    },
  );

  test(
    'E-V3 a damaged file is moved aside and the store starts empty',
    () async {
      Directory(fixture.directory).createSync(recursive: true);
      File(fixture.path).writeAsBytesSync(List<int>.filled(8192, 0x78));

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(countWrites(store), 0);
      expect(SqliteFiles.badCopies(fixture.path), hasLength(1));
      expect(fixture.log.single, contains('damaged'));
    },
  );

  test('E-V3 only the newest moved-aside copy is kept', () async {
    Directory(fixture.directory).createSync(recursive: true);
    File(fixture.path).writeAsBytesSync(List<int>.filled(8192, 0x78));
    (await fixture.open()).close();
    for (final String suffix in SqliteFiles.sideSuffixes) {
      final File side = File('${fixture.path}$suffix');
      if (side.existsSync()) {
        side.deleteSync();
      }
    }
    File(fixture.path).writeAsBytesSync(List<int>.filled(8192, 0x79));
    fixture.clock.advance(const Duration(seconds: 2));

    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    final List<File> copies = SqliteFiles.badCopies(fixture.path);
    expect(copies, hasLength(1));
    expect(copies.single.readAsBytesSync().first, 0x79);
  });

  test(
    'E-V5 a file of the same major and a newer minor opens and keeps its data',
    () async {
      await createStoreWithOneWrite();
      changeFile((sqlite.Database db) {
        db.userVersion = 1001;
        db.execute('CREATE TABLE added_in_1_1 (x INTEGER)');
      });

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(countWrites(store), 1);
      expect(store.debugDatabase!.userVersion, 1001);
      expect(SqliteFiles.badCopies(fixture.path), isEmpty);
    },
  );

  test(
    'E-X1 a SQLite older than 3.24 gives a memory-only store and touches no file',
    () async {
      final SqliteConnection store = await fixture.open(
        sqliteVersionNumber: 3023000,
      );

      expect(store.state, StoreState.memoryOnly);
      expect(Directory(fixture.directory).existsSync(), isFalse);
      expect(fixture.log.single, contains('older than 3.24.0'));
    },
  );
}
