// Tests of the opener: schema, versions and quarantine (E-V1 to E-V5, E-X1 of
// rtdb_storage_engine_design.md section 15; new, Android crashes or asserts in these cases).
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_open.dart';
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
      // The owner refreshes while the new open watches its lease.
      fixture.clock.onAdvance = owner.refreshLease;

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.memoryOnly);
      expect(SqliteFiles.badCopies(fixture.path), isEmpty);
      expect(File(fixture.path).existsSync(), isTrue);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
    },
  );

  test(
    'E-V2 a file of another application is moved aside whole and the store starts empty',
    () async {
      // Fails if the opener treats a foreign application_id as its own (sqlite_open.dart:347) or
      // deletes the file instead of moving it (SqliteFiles.moveAside). The move of a stray log is
      // pinned in sqlite_files_test.dart.
      Directory(fixture.directory).createSync(recursive: true);
      changeFile((sqlite.Database db) {
        db.execute('CREATE TABLE notes (body TEXT)');
        db.execute("INSERT INTO notes VALUES ('kept for diagnosis')");
      });

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(countWrites(store), 0);
      final File copy = SqliteFiles.badCopies(
        fixture.path,
      ).singleWhere((File f) => !f.path.endsWith('-wal'));
      final sqlite.Database kept = sqlite.sqlite3.open(copy.path);
      try {
        expect(
          StoreFixture.scalar(kept, 'SELECT body FROM notes'),
          'kept for diagnosis',
        );
      } finally {
        StoreFixture.closeRaw(kept);
      }
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
    'E-V1 a newer file whose owner vanished is moved aside after one observation',
    () async {
      // m25. Fails if SqliteLease.isHeldByLiveOwner counts any lease row as live
      // (sqlite_lease.dart:177, `!second.sameAs(first)`): the file stays and the store is
      // memory-only for good.
      await createStoreWithOneWrite();
      changeFile((sqlite.Database db) {
        db.userVersion = 2000;
        db.execute(
          "INSERT INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, '17:gone', 4, 0)",
        );
      });

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(countWrites(store), 0);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      final List<File> copies = SqliteFiles.badCopies(fixture.path);
      expect(copies.where((File f) => !f.path.endsWith('-wal')), hasLength(1));
      expect(fixture.log.single, contains('written by a newer version'));
    },
  );

  group('quick check after a vanished owner', () {
    // A store whose last owner, `4242:old`, vanished without releasing the lease, and whose page 1
    // counts one free page more than the file has: only `PRAGMA quick_check` sees that, every read
    // and write of the opener works.
    Future<void> leaveDamagedFileOfVanishedOwner() async {
      await createStoreWithOneWrite();
      changeFile((sqlite.Database db) {
        db.execute(
          "INSERT INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, '4242:old', 3, 0)",
        );
        db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      });
      final File file = File(fixture.path);
      final Uint8List bytes = file.readAsBytesSync();
      // Bytes 36 to 39 of the header: the number of free pages, big-endian.
      final ByteData header = ByteData.sublistView(bytes, 36, 40);
      header.setUint32(0, header.getUint32(0) + 1);
      file.writeAsBytesSync(bytes, flush: true);
    }

    test(
      'after a crash in another process the damaged file is moved aside',
      () async {
        // m22. Fails if _StoreOpener._passesQuickCheck accepts any result (sqlite_open.dart:376,
        // `rows.isNotEmpty && ... == 'ok'`): the damaged file is kept.
        await leaveDamagedFileOfVanishedOwner();

        final SqliteConnection store = await fixture.open(ownerId: '17:new');
        addTearDown(store.close);

        expect(store.state, StoreState.durable);
        expect(countWrites(store), 0);
        final List<File> copies = SqliteFiles.badCopies(fixture.path);
        expect(
          copies.where((File f) => !f.path.endsWith('-wal')),
          hasLength(1),
        );
        expect(fixture.log.last, contains('damaged'));
        expect(fixture.log.last, contains('moved aside'));
      },
    );

    test(
      'after a hot restart in the same process the file is kept without a check',
      () async {
        // The control of the test above: the same file opens with its data when the vanished owner
        // ran in this process, so only the quick check finds the damage. Fails if the opener checks
        // after a same-process takeover (the `previousOwnerSameProcess: false` pattern,
        // sqlite_open.dart:225-228).
        await leaveDamagedFileOfVanishedOwner();

        final SqliteConnection store = await fixture.open(ownerId: '4242:new');
        addTearDown(store.close);

        expect(store.state, StoreState.durable);
        expect(countWrites(store), 1);
        expect(SqliteFiles.badCopies(fixture.path), isEmpty);
        expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      },
    );
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

  group('failures that end in a memory-only store', () {
    test('a file that can not be opened', () async {
      // Fails if openSqliteStore lets an exception of `options.openDatabase` reach the caller
      // (the `on Object` catch, sqlite_open.dart:126-127).
      final SqliteConnection store = await openSqliteStore(
        directory: fixture.directory,
        fileName: StoreFixture.fileName,
        options: SqliteStoreOptions(
          nowMs: fixture.clock.now,
          delay: fixture.clock.delay,
          log: (DatabaseLogLevel level, String message) =>
              fixture.log.add(message),
          openDatabase: (String path) =>
              throw FileSystemException('denied by the test', path),
        ),
      );

      expect(store.state, StoreState.memoryOnly);
      expect(fixture.log.single, contains('could not be opened'));
    });

    test('a lease table this code can not use; the file is kept', () async {
      // Fails if the opener's `on sqlite.SqliteException` (sqlite_open.dart:252-260) moves the
      // file aside for an error that is not damage, or lets the error through.
      await createStoreWithOneWrite();
      changeFile((sqlite.Database db) {
        db.execute('DROP TABLE lease');
        db.execute('CREATE TABLE lease (id INTEGER PRIMARY KEY)');
      });

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.memoryOnly);
      expect(fixture.log.single, contains('SQLite result code'));
      expect(SqliteFiles.badCopies(fixture.path), isEmpty);
      changeFile((sqlite.Database db) {
        expect(StoreFixture.scalar(db, 'SELECT count(*) FROM user_writes'), 1);
      });
    });

    test('a damaged file that can not be moved aside', () async {
      // Fails without the `!SqliteFiles.moveAside(...)` branch of _StoreOpener._quarantine
      // (sqlite_open.dart:281-284). The fixture clock starts at 2026-01-01T00:00:00Z, so the copy
      // would be `<file>.bad-20260101T000000`; a non-empty directory of that name blocks the move.
      Directory(fixture.directory).createSync(recursive: true);
      File(fixture.path).writeAsBytesSync(List<int>.filled(8192, 0x78));
      final Directory blocker = Directory(
        '${fixture.path}${SqliteFiles.badInfix}20260101T000000',
      )..createSync();
      File(SqliteFiles.join(blocker.path, 'x')).writeAsStringSync('x');

      final SqliteConnection store = await fixture.open();

      expect(store.state, StoreState.memoryOnly);
      expect(fixture.log.single, contains('could not be moved aside'));
      expect(File(fixture.path).readAsBytesSync().first, 0x78);
    });
  });

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
