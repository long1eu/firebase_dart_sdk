// The factory and file naming (E-F1 and E-P3 of rtdb_storage_engine_design.md section 15).
// E-F1 replaces Android's SqlPersistenceStorageEngineTest testAllowedSessionIdCharacters: the
// name is a hash here, so any app name and URL are safe.
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;
  late SqlitePersistence persistence;
  final Uri url = Uri.parse('https://demo-test-default-rtdb.firebaseio.com');
  final PersistenceKey key = PersistenceKey(
    appName: '[DEFAULT]',
    databaseUrl: url,
  );

  setUp(() {
    fixture = StoreFixture();
    persistence = SqlitePersistence(
      fixture.directory,
      options: fixture.options(),
    );
  });
  tearDown(() => fixture.dispose());

  /// Writes the lease row of a vanished owner into the closed store file at [path].
  void writeLease(String path, String ownerId) {
    final sqlite.Database db = sqlite.sqlite3.open(path);
    try {
      db.execute(
        'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, 3, 0)',
        <Object?>[ownerId],
      );
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  LeaseRow? readLease(String path) {
    final sqlite.Database db = sqlite.sqlite3.open(path);
    try {
      return SqliteLease.read(db);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  group('E-F1 file names', () {
    test('are rtdb-, 32 hex digits and .sqlite for any app name and URL', () {
      const String odd = r'.?!@$%^&*()\/-~{}π∞٩(-̮̮̃-̃)۶ ٩(●̮̮̃•̃)۶';
      for (final String app in <String>['[DEFAULT]', odd, '', '../..']) {
        expect(
          SqliteFiles.fileName(
            app,
            Uri.parse('https://x.firebaseio.com/?ns=$app'),
          ),
          matches(RegExp(r'^rtdb-[0-9a-f]{32}\.sqlite$')),
        );
      }
    });

    test('are stable and differ by app and by URL', () {
      final String base = SqliteFiles.fileName('[DEFAULT]', url);
      expect(SqliteFiles.fileName('[DEFAULT]', url), base);
      expect(SqliteFiles.fileName('other', url), isNot(base));
      expect(
        SqliteFiles.fileName(
          '[DEFAULT]',
          Uri.parse('https://other.firebaseio.com'),
        ),
        isNot(base),
      );
    });
  });

  group('sqlitePersistence', () {
    // The size range is the client's (databasePersistence): 1 MiB to 100 MiB, 10 MiB when null.
    test('checks its arguments', () {
      expect(() => sqlitePersistence(''), throwsArgumentError);
      expect(
        () => sqlitePersistence('/tmp/x', cacheSizeBytes: 1024 * 1024 - 1),
        throwsArgumentError,
      );
      expect(
        () =>
            sqlitePersistence('/tmp/x', cacheSizeBytes: 100 * 1024 * 1024 + 1),
        throwsArgumentError,
      );
      for (final int size in <int>[1024 * 1024, 100 * 1024 * 1024]) {
        expect(
          () => sqlitePersistence('/tmp/x', cacheSizeBytes: size),
          returnsNormally,
          reason: '$size',
        );
      }
    });

    test('logs to the logger the client passes, with a level', () async {
      final PersistenceStorageEngine first = await persistence.open(key);
      addTearDown(first.close);
      final List<(DatabaseLogLevel, String)> clientLog =
          <(DatabaseLogLevel, String)>[];

      final PersistenceStorageEngine second = await persistence.open(
        key,
        logger: (DatabaseLogLevel level, String message) =>
            clientLog.add((level, message)),
      );

      expect(second.isDurable, isFalse);
      expect(fixture.log, isEmpty);
      expect(clientLog.single.$1, DatabaseLogLevel.warning);
      expect(clientLog.single.$2, contains('another instance'));
    });

    test('opens a durable store in the directory', () async {
      final PersistenceStorageEngine engine = await persistence.open(key);
      addTearDown(engine.close);

      expect(engine.isDurable, isTrue);
      expect(File(persistence.pathOf(key)).existsSync(), isTrue);
    });

    test('a second open of the same database is memory-only at once', () async {
      final PersistenceStorageEngine first = await persistence.open(key);
      addTearDown(first.close);

      final PersistenceStorageEngine second = await persistence.open(key);

      expect(second.isDurable, isFalse);
      expect(fixture.clock.delays, isEmpty);
      expect(fixture.log.single, contains('another instance'));
    });

    test(
      'a store that could not own its file is not left registered as open',
      () async {
        // m23. Fails without `if (!connection.isDurable) _openPaths.remove(path)` in
        // SqlitePersistence.open (sqlite_persistence.dart:135-137): the reopen below is refused as
        // "another instance" although nothing holds the file any more.
        final SqliteConnection owner = await openSqliteStore(
          directory: fixture.directory,
          fileName: SqliteFiles.fileName(key.appName, key.databaseUrl),
          options: fixture.options(),
        );
        // Another isolate owns the file and refreshes its lease while this one watches it.
        fixture.clock.onAdvance = owner.refreshLease;
        final PersistenceStorageEngine memoryOnly = await persistence.open(key);
        expect(memoryOnly.isDurable, isFalse);
        memoryOnly.close();
        owner.close();
        fixture.clock.onAdvance = null;

        final PersistenceStorageEngine again = await persistence.open(key);
        addTearDown(again.close);

        expect(again.isDurable, isTrue);
      },
    );

    test('after a close the database opens durably again', () async {
      (await persistence.open(key)).close();

      final PersistenceStorageEngine again = await persistence.open(key);
      addTearDown(again.close);

      expect(again.isDurable, isTrue);
      expect(fixture.clock.delays, isEmpty);
    });
  });

  group('E-P3 clear', () {
    test(
      'deletes the file, its side files and its moved-aside copies',
      () async {
        final String path = persistence.pathOf(key);
        (await persistence.open(key)).close();
        File('$path.bad-20260101T000000').writeAsStringSync('old');
        File('$path.bad-20260101T000000-wal').writeAsStringSync('old log');
        File('$path-journal').writeAsStringSync('journal');

        await persistence.clear(key);

        final List<String> left = <String>[
          for (final FileSystemEntity e in Directory(
            fixture.directory,
          ).listSync())
            e.path,
        ];
        expect(left, isEmpty);
      },
    );

    test('clearSqlitePersistence deletes the files of one database', () async {
      final String path = persistence.pathOf(key);
      (await persistence.open(key)).close();
      expect(File(path).existsSync(), isTrue);

      await clearSqlitePersistence(
        fixture.directory,
        appName: key.appName,
        databaseUrl: key.databaseUrl,
      );

      expect(File(path).existsSync(), isFalse);
    });

    test('is refused while this persistence has the store open', () async {
      final PersistenceStorageEngine engine = await persistence.open(key);
      addTearDown(engine.close);

      await expectLater(persistence.clear(key), throwsStateError);
    });

    test('is refused while another process holds a live lease', () async {
      final SqlitePersistence other = SqlitePersistence(
        fixture.directory,
        options: fixture.options(),
      );
      final PersistenceStorageEngine engine = await other.open(key);
      addTearDown(engine.close);
      // The owner works (and so refreshes its lease) while clear watches it.
      fixture.clock.onAdvance = () {
        engine.beginTransaction();
        engine.setTransactionSuccessful();
        engine.endTransaction();
      };

      await expectLater(persistence.clear(key), throwsStateError);
      expect(File(persistence.pathOf(key)).existsSync(), isTrue);
    });

    test(
      'M3 is refused while the owner refreshes, also when its lease expired by the clock',
      () async {
        // Fails if clear decides by `expires_at_ms` against the clock again instead of watching
        // the row (SqlitePersistence._tombstone and SqliteLease.writeTombstone).
        final SqlitePersistence other = SqlitePersistence(
          fixture.directory,
          options: fixture.options(),
        );
        final PersistenceStorageEngine engine = await other.open(key);
        addTearDown(engine.close);
        fixture.clock.advance(const Duration(seconds: 20));
        fixture.clock.onAdvance = () {
          engine.beginTransaction();
          engine.setTransactionSuccessful();
          engine.endTransaction();
        };

        await expectLater(persistence.clear(key), throwsStateError);

        expect(File(persistence.pathOf(key)).existsSync(), isTrue);
        expect(engine.isDurable, isTrue);
      },
    );

    test(
      'M3 of an owner that vanished waits one observation, then deletes',
      () async {
        // A crashed owner: its lease row stays and nothing holds the file.
        (await persistence.open(key)).close();
        writeLease(persistence.pathOf(key), '17:crashed');

        await persistence.clear(key);

        expect(File(persistence.pathOf(key)).existsSync(), isFalse);
        expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      },
    );

    test(
      'is refused while another connection writes to the file, and keeps it',
      () async {
        // m24. Fails if SqlitePersistence._tombstone counts SQLITE_BUSY as "not a store"
        // (sqlite_persistence.dart:196-197): the files of a store in use are deleted.
        final String path = persistence.pathOf(key);
        (await persistence.open(key)).close();
        final sqlite.Database other = sqlite.sqlite3.open(path);
        addTearDown(() => StoreFixture.closeRaw(other));
        other.execute('BEGIN IMMEDIATE');

        await expectLater(persistence.clear(key), throwsStateError);

        other.execute('ROLLBACK');
        expect(File(path).existsSync(), isTrue);
      },
    );

    test('a clear whose deletion failed leaves a tombstone: opens are memory-only and a second '
        'clear is refused until it expires', () async {
      // Fails without the live-tombstone refusal of SqlitePersistence._tombstone
      // (sqlite_persistence.dart:183-185), or if a tombstone never expires there; and without
      // the side-files-first rule of SqliteFiles.deleteAll (sqlite_files.dart:75).
      final String path = persistence.pathOf(key);
      (await persistence.open(key)).close();
      writeLease(path, '17:crashed');
      // While clear watches the row, something makes the journal path undeletable (a directory
      // stands in for it on every platform).
      final Directory blocker = Directory('$path-journal');
      fixture.clock.onAdvance = () {
        if (!blocker.existsSync()) {
          blocker.createSync();
          File(SqliteFiles.join(blocker.path, 'x')).writeAsStringSync('x');
        }
      };

      await expectLater(
        persistence.clear(key),
        throwsA(isA<ClearPersistenceException>()),
      );
      fixture.clock.onAdvance = null;
      blocker.deleteSync(recursive: true);

      expect(File(path).existsSync(), isTrue);
      expect(readLease(path)?.ownerId, SqliteLease.clearingOwnerId);
      final PersistenceStorageEngine racing = await persistence.open(key);
      expect(racing.isDurable, isFalse);
      expect(fixture.log.last, contains('being deleted'));
      racing.close();
      await expectLater(persistence.clear(key), throwsStateError);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);

      fixture.clock.advance(
        SqliteLease.tombstoneDuration + const Duration(milliseconds: 1),
      );
      await persistence.clear(key);

      expect(File(path).existsSync(), isFalse);
    });

    test('of a database that never existed does nothing', () async {
      await persistence.clear(key);

      expect(Directory(fixture.directory).existsSync(), isFalse);
    });

    test('of a damaged file deletes it', () async {
      final String path = persistence.pathOf(key);
      Directory(fixture.directory).createSync(recursive: true);
      File(path).writeAsBytesSync(List<int>.filled(4096, 0x78));

      await persistence.clear(key);

      expect(File(path).existsSync(), isFalse);
      expect(SqliteFiles.badCopies(path), isEmpty);
    });
  });
}
