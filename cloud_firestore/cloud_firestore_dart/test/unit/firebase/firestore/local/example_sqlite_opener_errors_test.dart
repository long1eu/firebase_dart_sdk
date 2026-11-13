// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../../../../../example/sqlite_database.dart';

/// The opener of `example/sqlite_database.dart` reports the SQLite errors that may go away on their own as a
/// [TransientDatabaseException] (Firestore then goes offline and retries), and every other error as it is.
void main() {
  late Directory directory;
  late Database database;
  late sqlite.Database other;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('example_opener_test');
    database = await sqliteOpener(directory)('errors', version: 1);
    await database.execute('CREATE TABLE t (a INTEGER)');
    other = sqlite.sqlite3.open('${directory.path}/errors.db');
  });

  tearDown(() async {
    other.dispose();
    database.close();
    await directory.delete(recursive: true);
  });

  test('a database locked by another connection is transient', () async {
    other.execute('BEGIN IMMEDIATE');
    other.execute('INSERT INTO t VALUES (1)');

    await expectLater(
      database.execute('BEGIN IMMEDIATE'),
      throwsA(isA<TransientDatabaseException>()),
    );

    other.execute('COMMIT');
    // Once the lock is gone, the same statement works.
    await database.execute('BEGIN IMMEDIATE');
    await database.execute('COMMIT');
    expect(await database.query('SELECT a FROM t'), hasLength(1));
  });

  test(
    'the string of a transient error does not repeat the statement or its arguments',
    () async {
      // Firestore puts the error into the message of the `unavailable` error the app sees and logs it as a warning;
      // the arguments hold document contents, paths and user ids.
      other.execute('BEGIN IMMEDIATE');
      other.execute('INSERT INTO t VALUES (1)');
      try {
        await database.execute('INSERT INTO t VALUES (?)', <Object?>[
          'private user data',
        ]);
        fail('expected a TransientDatabaseException');
      } on TransientDatabaseException catch (e) {
        expect(e.cause, isA<sqlite.SqliteException>());
        expect('$e', isNot(contains('private user data')));
        expect('$e', isNot(contains('INSERT INTO')));
        expect('$e', contains('database is locked'));
      } finally {
        other.execute('ROLLBACK');
      }
    },
  );

  test(
    'a lock held at COMMIT is transient and the transaction can be rolled back',
    () async {
      await database.execute('BEGIN IMMEDIATE');
      await database.execute('INSERT INTO t VALUES (1)');
      // Another connection reads: in rollback journal mode the COMMIT needs the exclusive lock and is busy.
      other.execute('BEGIN');
      other.select('SELECT * FROM t');

      await expectLater(
        database.execute('COMMIT'),
        throwsA(isA<TransientDatabaseException>()),
      );
      // As SQLitePersistence does after a failed transaction: nothing was stored.
      await database.execute('ROLLBACK');
      other.execute('COMMIT');
      expect(await database.query('SELECT a FROM t'), isEmpty);
    },
  );

  test(
    'a full database is transient and keeps nothing of the transaction',
    () async {
      final int pages =
          (await database.query('PRAGMA page_count')).single.values.single
              as int;
      await database.query('PRAGMA max_page_count = $pages');

      await database.execute('BEGIN IMMEDIATE');
      await expectLater(
        database.execute('INSERT INTO t VALUES (randomblob(1048576))'),
        throwsA(isA<TransientDatabaseException>()),
      );
      // SQLite rolls the transaction back itself on a full disk (SQLitePersistence logs the ROLLBACK that then
      // fails): nothing of it was stored.
      await expectLater(
        database.execute('ROLLBACK'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(await database.query('SELECT a FROM t'), isEmpty);
    },
  );

  test('other errors are thrown as they are', () async {
    await expectLater(
      database.query('SELECT * FROM missing_table'),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });

  test('the page cache size is applied, the default is left alone', () async {
    // The default of the library: -2000 (2 MB) in SQLite's own build, 2000 pages (8 MB) in the one of macOS.
    expect((await database.query('PRAGMA cache_size')).single.values.single,
        anyOf(-2000, 2000));
    final Database sized =
        await sqliteOpener(directory, pageCacheMb: 16)('sized', version: 1);
    addTearDown(sized.close);
    expect((await sized.query('PRAGMA cache_size')).single.values.single,
        -16 * 1024);
  });
}
