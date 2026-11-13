// The offline cache in a browser with its database in the origin private
// file system (OPFS): example/sqlite_database_web.dart with `opfsWorker`,
// SQLite in the dedicated worker of example/sqlite_opfs_worker.dart.
//
// Needs test/browser/sqlite3.wasm (see web_persistence_test.dart) and the
// compiled worker test/browser/opfs/sqlite_opfs_worker.js
// (tool/build_web_test_assets.sh, which tool/test_browser.sh runs); skips
// itself with a reason without them, and in a browser without synchronous
// OPFS access in workers. Run against a private emulator, one file at a time:
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_persistence_opfs_test.dart

@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../example/sqlite_database_web.dart';
import '../../example/sqlite_opfs_worker.dart' show isTransientError;
import 'browser_test_util.dart';

typedef Json = Map<String, Object?>;

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');
final Uri opfsWorker = Uri.base.resolve('opfs/sqlite_opfs_worker.js');
final Uri noOpfsWorker = Uri.base.resolve('opfs/no_opfs_worker.js');
final Uri faultyOpfsWorker = Uri.base.resolve('opfs/faulty_opfs_worker.js');

/// Arms a fault in the worker of faulty_opfs_worker.dart that is running
/// (see that file), or disarms it with a null [point].
Future<void> armFault(
  String? point,
  int code, {
  bool afterEffect = false,
}) async {
  final web.BroadcastChannel channel = web.BroadcastChannel('opfs-faults');
  try {
    final Completer<void> armed = Completer<void>();
    channel.onmessage = (web.MessageEvent event) {
      if (!armed.isCompleted) {
        armed.complete();
      }
    }.toJS;
    channel.postMessage(
      jsonEncode(<String, Object?>{
        'point': point,
        'code': code,
        'afterEffect': afterEffect,
      }).toJS,
    );
    await armed.future.timeout(const Duration(seconds: 5));
  } finally {
    channel.close();
  }
}

const String storagePrefix = 'cloud_firestore_dart';

OpenDatabase opener() =>
    sqliteWebOpener(sqlite3Wasm: sqlite3Wasm, opfsWorker: opfsWorker);
OpenDatabase indexedDbOpener() => sqliteWebOpener(sqlite3Wasm: sqlite3Wasm);

int _names = 0;
String newAppName() =>
    'opfs-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

Future<bool> exists(Uri uri) async {
  try {
    return (await web.window.fetch(uri.toString().toJS).toDart).ok;
  } catch (_) {
    return false;
  }
}

/// The names of the OPFS directories under [storagePrefix] that belong to
/// [app].
Future<List<String>> opfsDirectories(String app) async {
  final web.FileSystemDirectoryHandle root = await web.window.navigator.storage
      .getDirectory()
      .toDart;
  final web.FileSystemDirectoryHandle prefix;
  try {
    prefix = await root.getDirectoryHandle(storagePrefix).toDart;
  } catch (_) {
    return <String>[];
  }
  final List<String> names = <String>[];
  // The keys of the async iterator of the directory, as a list.
  final JSObject iterator = prefix.callMethod<JSObject>('keys'.toJS);
  while (true) {
    final JSObject step = await iterator
        .callMethod<JSPromise<JSObject>>('next'.toJS)
        .toDart;
    if ((step.getProperty<JSBoolean>('done'.toJS)).toDart) {
      break;
    }
    final String name = step.getProperty<JSString>('value'.toJS).toDart;
    if (name.contains(app)) {
      names.add(name);
    }
  }
  return names;
}

/// The names of the IndexedDB databases of this origin that belong to [app].
Future<List<String>> indexedDbDatabases(String app) async =>
    (await sqlite.IndexedDbFileSystem.databases() ?? <String>[])
        .where((String name) => name.contains(app))
        .toList();

void main() {
  String? skip;

  setUpAll(() async {
    if (!await exists(sqlite3Wasm)) {
      skip =
          'test/browser/sqlite3.wasm is missing: see '
          'web_persistence_test.dart';
    } else if (!await exists(opfsWorker)) {
      skip =
          'test/browser/opfs/sqlite_opfs_worker.js is missing: run '
          'tool/build_web_test_assets.sh';
    } else {
      final SqliteOpfsDatabase? probe = await inspectOpfsDatabase(
        opfsWorker: opfsWorker,
        sqlite3Wasm: sqlite3Wasm,
        storageName: 'probe/${newAppName()}',
      );
      if (probe == null) {
        skip = 'this browser has no synchronous OPFS access in workers';
      } else {
        await probe.clearStorage();
      }
    }
  });

  /// Registers the test, skipped at run time when it cannot run here.
  void opfsTest(String name, Future<void> Function() body) {
    test(name, () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      await body();
    });
  }

  opfsTest(
    'the cache is in OPFS and holds what was read and written',
    () async {
      final String app = newAppName();
      final Firestore firestore = await newClient(
        openDatabase: opener(),
        appName: app,
      );
      expect(firestore.client.persistence, isA<SQLitePersistence>());
      final DocumentReference<Json> doc = firestore
          .collection(newCollectionName())
          .doc('a');
      await doc.set(<String, Object?>{'a': 1, 'text': 'héllo \u{1F600}'});

      final DocumentSnapshot<Json> cached = await doc.get(Source.cache);
      expect(cached.data, <String, Object?>{'a': 1, 'text': 'héllo \u{1F600}'});
      expect(cached.metadata.hasPendingWrites, isFalse);
      expect(await opfsDirectories(app), hasLength(1));
      expect(await indexedDbDatabases(app), isEmpty);
    },
  );

  opfsTest(
    'acknowledged data and pending writes are there after a reopen',
    () async {
      final String app = newAppName();
      final String collection = newCollectionName();
      Firestore firestore = await newClient(
        openDatabase: opener(),
        appName: app,
      );
      for (int i = 0; i < 3; i++) {
        await firestore.collection(collection).doc('d$i').set(<String, Object?>{
          'n': i,
        });
      }
      await firestore.collection(collection).get(Source.server);
      await firestore.disableNetwork();
      unawaited(
        firestore.collection(collection).doc('pending').set(<String, Object?>{
          'n': 9,
        }),
      );
      expect(
        (await firestore
                .collection(collection)
                .doc('pending')
                .get(Source.cache))
            .metadata
            .hasPendingWrites,
        isTrue,
      );
      await shutDown(firestore);

      // A new worker that reads the files back, as after a page load.
      firestore = await newClient(openDatabase: opener(), appName: app);
      await firestore.disableNetwork();
      final QuerySnapshot<Json> cached = await firestore
          .collection(collection)
          .orderBy('n')
          .get(Source.cache);
      expect(
        cached.docs.map((QueryDocumentSnapshot<Json> d) => d.data).toList(),
        <Json>[
          <String, Object?>{'n': 0},
          <String, Object?>{'n': 1},
          <String, Object?>{'n': 2},
          <String, Object?>{'n': 9},
        ],
      );
      expect(cached.docs.last.metadata.hasPendingWrites, isTrue);

      await firestore.enableNetwork();
      await firestore.waitForPendingWrites().timeout(
        const Duration(seconds: 20),
      );
      final Firestore other = await newClient();
      expect(
        (await other.collection(collection).doc('pending').get(Source.server))
            .data,
        <String, Object?>{'n': 9},
      );
    },
  );

  opfsTest('values of every SQLite type make the round trip', () async {
    final String name = 'values-${newAppName()}';
    final Database db = await opener()(
      name,
      version: 1,
      onCreate: (Database db, int to) =>
          db.execute('CREATE TABLE v (i INTEGER, r REAL, t TEXT, b BLOB)'),
    );
    addTearDown(() => (db as ClearableDatabase).clearStorage());
    expect(db, isA<SqliteOpfsDatabase>());
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[0, 0.5, '', Uint8List(0)],
      <Object?>[
        -7,
        // Not an integral value: compiled to JavaScript, package:sqlite3 binds
        // those as integers, in the worker and without it.
        -1.25e-300,
        'héllo \u{1F600}',
        Uint8List.fromList(<int>[0, 255, 1]),
      ],
      <Object?>[9007199254740991, 2.0, 'x' * 10000, Uint8List(70000)],
      <Object?>[null, null, null, null],
      if (const bool.fromEnvironment('dart.tool.dart2wasm'))
        // Beyond 2^53: only Dart compiled to WebAssembly has such integers.
        <Object?>[-9223372036854775808, 1.5, 'big', Uint8List(1)],
    ];
    for (final List<Object?> row in rows) {
      await db.execute('INSERT INTO v VALUES (?, ?, ?, ?)', row);
    }
    final List<Map<String, dynamic>> read = await db.query(
      'SELECT i, r, t, b FROM v ORDER BY rowid',
    );
    expect(read, hasLength(rows.length));
    for (int i = 0; i < rows.length; i++) {
      expect(read[i].values.toList(), rows[i], reason: 'row $i');
    }
    expect(read[0]['r'], isA<double>());
    // The worker is compiled to JavaScript, where a REAL that is integral is
    // an int: 2.0 comes back as 2 (equal, but an int under dart2wasm). The
    // cache has no REAL columns.
    expect(read[2]['r'], 2);
    expect(await db.delete('DELETE FROM v WHERE i IS NULL'), 1);

    // A failing statement fails its future and leaves the database usable.
    await expectLater(
      db.execute('INSERT INTO nope VALUES (1)'),
      throwsA(isA<SqliteOpfsException>()),
    );
    expect(
      await db.query('SELECT count(*) AS c FROM v'),
      <Map<String, dynamic>>[
        <String, dynamic>{'c': rows.length - 1},
      ],
    );
  });

  opfsTest('a cache that is open cannot be opened a second time', () async {
    final String name = 'guard-${newAppName()}';
    final Database first = await opener()(name, version: 1);

    await expectLater(
      opener()(name, version: 1),
      throwsA(
        isA<FirestoreError>()
            .having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.failedPrecondition,
            )
            .having(
              (FirestoreError e) => e.message,
              'message',
              contains('another tab'),
            ),
      ),
    );

    first.close();
    // Closing ends the worker, which releases the files, and then the lock.
    Database? again;
    for (int i = 0; i < 50 && again == null; i++) {
      try {
        again = await opener()(name, version: 1);
      } on FirestoreError {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(again, isNotNull, reason: 'the lock is released by close()');
    await (again! as ClearableDatabase).clearStorage();
  });

  opfsTest(
    'an upgrade that fails halfway leaves the previous schema and version',
    () async {
      final String name = 'atomic-${newAppName()}';
      Database db = await opener()(
        name,
        version: 1,
        onCreate: (Database db, int to) => db.execute('CREATE TABLE one (a)'),
      );
      db.close();

      await expectLater(
        opener()(
          name,
          version: 2,
          onUpgrade: (Database db, int from, int to) async {
            await db.execute('CREATE TABLE two (a)');
            await db.execute('INSERT INTO one VALUES (1)');
            throw StateError('the tab would die here');
          },
        ),
        throwsStateError,
      );

      final List<String> upgrades = <String>[];
      db = await opener()(
        name,
        version: 2,
        onCreate: (Database db, int to) async => fail('not a new database'),
        onUpgrade: (Database db, int from, int to) async {
          upgrades.add('$from->$to');
          expect(await db.query('SELECT * FROM one'), isEmpty);
          expect(
            await db.query("SELECT name FROM sqlite_master WHERE name = 'two'"),
            isEmpty,
          );
          await db.execute('CREATE TABLE two (a)');
        },
      );
      expect(upgrades, <String>['1->2']);
      expect((await db.query('PRAGMA user_version')).single.values.first, 2);
      await (db as ClearableDatabase).clearStorage();
    },
  );

  opfsTest('the whole schema of the cache is created in OPFS', () async {
    final String name = 'schema-${newAppName()}';
    final Database db = await opener()(
      name,
      version: SQLiteSchema.version,
      onCreate: (Database db, int to) => SQLiteSchema(db).runMigrations(0, to),
    );
    final List<Map<String, dynamic>> tables = await db.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    expect(
      tables.map((Map<String, dynamic> row) => row['name']),
      containsAll(<String>['mutations', 'remote_documents', 'targets']),
    );
    await (db as ClearableDatabase).clearStorage();
  });

  opfsTest('clearPersistence deletes the OPFS directory', () async {
    final String app = newAppName();
    final String collection = newCollectionName();
    Firestore firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.collection(collection).doc('a').set(<String, Object?>{
      'a': 1,
    });
    await firestore.terminate();
    expect(await opfsDirectories(app), hasLength(1));
    await firestore.clearPersistence();
    expect(await opfsDirectories(app), isEmpty);
    await shutDown(firestore);

    firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.disableNetwork();
    expect(
      (await firestore.collection(collection).get(Source.cache)).docs,
      isEmpty,
    );
  });

  opfsTest(
    'a cache in IndexedDB is moved to OPFS with its pending writes',
    () async {
      final String app = newAppName();
      final String collection = newCollectionName();
      Firestore firestore = await newClient(
        openDatabase: indexedDbOpener(),
        appName: app,
      );
      await firestore.collection(collection).doc('synced').set(
        <String, Object?>{'v': 1},
      );
      await firestore.disableNetwork();
      unawaited(
        firestore.collection(collection).doc('pending').set(<String, Object?>{
          'v': 2,
        }),
      );
      expect(
        (await firestore
                .collection(collection)
                .doc('pending')
                .get(Source.cache))
            .metadata
            .hasPendingWrites,
        isTrue,
      );
      await shutDown(firestore);
      expect(await indexedDbDatabases(app), hasLength(1));
      expect(await opfsDirectories(app), isEmpty);

      firestore = await newClient(openDatabase: opener(), appName: app);
      expect(
        await indexedDbDatabases(app),
        isEmpty,
        reason: 'the IndexedDB database is deleted once it is in OPFS',
      );
      expect(await opfsDirectories(app), hasLength(1));
      await firestore.disableNetwork();
      final DocumentSnapshot<Json> pending = await firestore
          .collection(collection)
          .doc('pending')
          .get(Source.cache);
      expect(pending.data, <String, Object?>{'v': 2});
      expect(pending.metadata.hasPendingWrites, isTrue);
      expect(
        (await firestore.collection(collection).doc('synced').get(Source.cache))
            .data,
        <String, Object?>{'v': 1},
      );

      await firestore.enableNetwork();
      await firestore.waitForPendingWrites().timeout(
        const Duration(seconds: 20),
      );
      final Firestore other = await newClient();
      expect(
        (await other.collection(collection).doc('pending').get(Source.server))
            .data,
        <String, Object?>{'v': 2},
      );
    },
  );

  test('which SQLite errors the worker reports as transient', () {
    bool transient(
      int code,
      String sql, {
      bool query = false,
      bool was = false,
      bool still = false,
      bool? changed,
    }) => isTransientError(
      resultCode: code,
      sql: sql,
      isQuery: query,
      wasInTransaction: was,
      isInTransaction: still,
      fileChanged: changed,
    );
    const int ioerr = sqlite.SqlError.SQLITE_IOERR;
    // Inside a transaction: Firestore rolls back, nothing is stored.
    expect(
      transient(ioerr, 'INSERT INTO t VALUES (1)', was: true, still: true),
      isTrue,
    );
    expect(transient(ioerr, 'INSERT INTO t VALUES (1)', was: true), isTrue);
    expect(
      transient(
        sqlite.SqlError.SQLITE_FULL,
        'UPDATE t SET a = 1',
        was: true,
        still: true,
      ),
      isTrue,
    );
    // A COMMIT that ended the transaction may have stored it: unless the
    // database file is as before, or that was not checked.
    expect(transient(ioerr, 'COMMIT', was: true, changed: true), isFalse);
    expect(transient(ioerr, ' commit;', was: true, changed: true), isFalse);
    expect(transient(ioerr, 'END TRANSACTION', was: true), isFalse);
    expect(transient(ioerr, 'COMMIT', was: true, changed: false), isTrue);
    // A COMMIT that left it open did not.
    expect(
      transient(sqlite.SqlError.SQLITE_BUSY, 'COMMIT', was: true, still: true),
      isTrue,
    );
    // Outside a transaction: reads and BEGIN store nothing; a write commits
    // itself.
    expect(transient(ioerr, 'SELECT * FROM t', query: true), isTrue);
    expect(transient(ioerr, 'PRAGMA data_version', query: true), isTrue);
    expect(transient(ioerr, 'BEGIN IMMEDIATE'), isTrue);
    expect(transient(ioerr, 'INSERT INTO t VALUES (1)'), isFalse);
    expect(
      transient(ioerr, 'INSERT INTO t VALUES (1)', changed: true),
      isFalse,
    );
    expect(
      transient(ioerr, 'INSERT INTO t VALUES (1)', changed: false),
      isTrue,
    );
    // Not a passing condition.
    expect(
      transient(sqlite.SqlError.SQLITE_CORRUPT, 'SELECT 1', query: true),
      isFalse,
    );
    expect(
      transient(
        sqlite.SqlError.SQLITE_CONSTRAINT,
        'INSERT INTO t VALUES (1)',
        was: true,
        still: true,
      ),
      isFalse,
    );
  });

  opfsTest('an I/O error is transient only when nothing was stored', () async {
    if (!await exists(faultyOpfsWorker)) {
      markTestSkipped(
        'test/browser/opfs/faulty_opfs_worker.js is missing: '
        'run tool/build_web_test_assets.sh',
      );
      return;
    }
    final String app = newAppName();
    OpenDatabase faulty() =>
        sqliteWebOpener(sqlite3Wasm: sqlite3Wasm, opfsWorker: faultyOpfsWorker);
    Future<void> create(Database db, int version) =>
        db.execute('CREATE TABLE t (a INTEGER)');

    final List<(String, int, bool)> faults = <(String, int, bool)>[
      (
        'write:/database-journal',
        sqlite.SqlExtendedError.SQLITE_IOERR_WRITE,
        false,
      ),
      (
        'sync:/database-journal',
        sqlite.SqlExtendedError.SQLITE_IOERR_FSYNC,
        false,
      ),
      ('write:/database', sqlite.SqlExtendedError.SQLITE_IOERR_WRITE, false),
      ('write:/database', sqlite.SqlError.SQLITE_FULL, false),
      ('sync:/database', sqlite.SqlExtendedError.SQLITE_IOERR_FSYNC, false),
      (
        'delete:/database-journal',
        sqlite.SqlExtendedError.SQLITE_IOERR_DELETE,
        false,
      ),
      // After the journal is gone: the transaction is stored.
      (
        'delete:/database-journal',
        sqlite.SqlExtendedError.SQLITE_IOERR_DELETE,
        true,
      ),
    ];
    final List<String> outcomes = <String>[];
    int transientErrors = 0;
    for (int i = 0; i < faults.length; i++) {
      final (String point, int code, bool afterEffect) = faults[i];
      final String name = 'fault-$i-$app';
      final Database db = await faulty()(name, version: 1, onCreate: create);
      await armFault(point, code, afterEffect: afterEffect);
      Object? error;
      String? failedAt;
      for (final String statement in <String>[
        'BEGIN IMMEDIATE',
        'INSERT INTO t VALUES (1)',
        'COMMIT',
      ]) {
        try {
          await db.execute(statement);
        } catch (e) {
          error = e;
          failedAt = statement;
          // What Firestore does after a failed statement of a transaction.
          try {
            await db.execute('ROLLBACK');
          } catch (_) {
            // No transaction left.
          }
          break;
        }
      }
      await armFault(null, 0);
      db.close();
      await (db as SqliteOpfsDatabase).whenClosed;

      // Read back by a new worker, as after a page load.
      final Database check = await opener()(name, version: 1);
      final int rows =
          (await check.query('SELECT count(*) AS c FROM t')).single['c'] as int;
      expect(
        (await check.query('PRAGMA integrity_check')).single.values.first,
        'ok',
        reason: point,
      );
      await (check as ClearableDatabase).clearStorage();

      final String kind = error == null
          ? 'no error'
          : error is TransientDatabaseException
          ? 'transient'
          : 'fatal (${error.runtimeType})';
      outcomes.add(
        '$point${afterEffect ? ' (after)' : ''}: $kind at '
        '$failedAt, rows $rows',
      );
      if (error is TransientDatabaseException) {
        transientErrors++;
        expect(
          rows,
          0,
          reason: '$point: a transient error must leave nothing stored',
        );
        expect(error.cause, isA<SqliteOpfsException>());
        expect(error.toString(), isNot(contains('INSERT')));
      }
      if (afterEffect) {
        expect(rows, 1, reason: 'the fault came after the commit point');
        expect(
          error,
          isNot(isA<TransientDatabaseException>()),
          reason: 'a transaction that was stored must not be retried',
        );
      }
    }
    // ignore: avoid_print
    print('I/O faults: ${outcomes.join('; ')}');
    // A fault before the database file is written leaves it as it was and is
    // worth a retry. Once the file holds the new pages (a failed delete of
    // the journal, the commit point) the worker cannot tell a stored
    // transaction from one that the next open rolls back, and reports the
    // error as fatal: the last two faults.
    expect(transientErrors, faults.length - 2, reason: outcomes.join('; '));

    // A read that fails is transient: it stored nothing.
    final String name = 'fault-read-$app';
    Database db = await faulty()(name, version: 1, onCreate: create);
    db.close();
    await (db as SqliteOpfsDatabase).whenClosed;
    db = await faulty()(name, version: 1);
    await armFault('read:/database', sqlite.SqlExtendedError.SQLITE_IOERR_READ);
    await expectLater(
      db.query('SELECT * FROM t'),
      throwsA(isA<TransientDatabaseException>()),
    );
    await armFault(null, 0);
    expect(await db.query('SELECT * FROM t'), isEmpty);
    await (db as ClearableDatabase).clearStorage();
  });

  // These two do not need OPFS.
  test('without synchronous OPFS access the cache is in IndexedDB', () async {
    if (!await exists(sqlite3Wasm)) {
      markTestSkipped('test/browser/sqlite3.wasm is missing');
      return;
    }
    final String app = newAppName();
    final Firestore firestore = await newClient(
      openDatabase: sqliteWebOpener(
        sqlite3Wasm: sqlite3Wasm,
        opfsWorker: noOpfsWorker,
      ),
      appName: app,
    );
    await firestore.collection(newCollectionName()).doc('a').set(
      <String, Object?>{'a': 1},
    );
    expect(await indexedDbDatabases(app), hasLength(1));
    expect(await opfsDirectories(app), isEmpty);
    await shutDown(firestore);
    final Database db = await sqliteWebOpener(
      sqlite3Wasm: sqlite3Wasm,
      opfsWorker: noOpfsWorker,
    )('fallback-$app', version: 1);
    expect(db, isA<SqliteWebDatabase>());
    await (db as ClearableDatabase).clearStorage();
  });

  test('a worker script that cannot be loaded fails the open', () async {
    final String name = 'missing-${newAppName()}';
    OpenDatabase broken() => sqliteWebOpener(
      sqlite3Wasm: sqlite3Wasm,
      opfsWorker: Uri.base.resolve('opfs/does_not_exist.js'),
    );
    await expectLater(
      broken()(name, version: 1),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('does_not_exist.js'),
        ),
      ),
    );
    // The lock was given back: the next attempt fails the same way instead of
    // with `failedPrecondition`.
    await expectLater(broken()(name, version: 1), throwsStateError);
  });
}
