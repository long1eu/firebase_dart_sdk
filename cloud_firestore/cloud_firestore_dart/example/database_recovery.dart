// Recovery from a cache that is not available for a while.
//
// A `Database` reports an error that may go away on its own (SQLite busy or
// locked, an I/O error, a full disk) by throwing `TransientDatabaseException`;
// the opener in sqlite_database.dart does. Firestore then:
// - fails a write or a listen that could not be stored with `unavailable`,
//   so that the app can try again;
// - keeps what the backend sent when it could not be stored, goes offline and
//   tries the cache again with a backoff until it works.
//
// Here a wrapper around the SQLite database fails the next few writes to one
// table, as a busy disk would.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/database_recovery.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';
import 'sqlite_database.dart';

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_recovery_',
  );
  late FlakyDatabase database;
  final OpenDatabase sqlite = sqliteOpener(directory);
  final Firestore firestore = Firestore.instanceFor(
    app: exampleApp(),
    openDatabase:
        (
          String path, {
          int version = 1,
          OnConfigure onConfigure = _nothing,
          OnCreate onCreate = _nothingFor,
          OnVersionChange onUpgrade = _nothingBetween,
          OnVersionChange onDowngrade = _nothingBetween,
          OnOpen onOpen = _nothing,
        }) async {
          return database = FlakyDatabase(
            await sqlite(
              path,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen,
            ),
          );
        },
    settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
  );
  final DocumentReference<Map<String, Object?>> doc = firestore.doc(
    '${scratch('recovery')}/status',
  );
  await doc.set(<String, Object?>{'step': 1});

  // A write is stored in the mutation queue before it is sent. When that
  // fails, the write fails with `unavailable` and nothing was changed: it is
  // safe to try again.
  database.failNextWrites('mutations', 1);
  try {
    await doc.set(<String, Object?>{'step': 2});
  } on FirestoreError catch (e) {
    if (e.code != FirestoreErrorCode.unavailable) {
      rethrow;
    }
    print('write failed with unavailable, nothing was stored');
  }
  await doc.set(<String, Object?>{'step': 2});
  print('write tried again: ${(await doc.get(Source.cache)).data}');

  // A change from the backend is stored in remote_documents before the
  // listener sees it. While that fails, the client goes offline and tries
  // again with a backoff; the listener gets the change once it is stored.
  final StreamIterator<DocumentSnapshot<Map<String, Object?>>> listener =
      StreamIterator<DocumentSnapshot<Map<String, Object?>>>(doc.snapshots);
  await listener.moveNext();
  print('listener: ${listener.current.data}');

  database.failNextWrites('remote_documents', 3);
  // Another client changes the document on the backend.
  final Firestore other = connect('other-client');
  await other.doc(doc.path).set(<String, Object?>{'step': 3});
  do {
    await listener.moveNext();
  } while (listener.current.data!['step'] != 3);
  print(
    'listener after ${database.failures} failed attempts to store the '
    'change: ${listener.current.data}',
  );

  await listener.cancel();
  await other.terminate();
  await firestore.terminate();
  directory.deleteSync(recursive: true);
}

/// A [Database] that fails the next writes to one table with a
/// [TransientDatabaseException], before running them, like a database that
/// is busy for a moment. Everything else goes to the wrapped database.
class FlakyDatabase implements Database {
  FlakyDatabase(this._database);

  final Database _database;
  RegExp? _table;
  int _remaining = 0;

  /// How many statements failed since the last [failNextWrites].
  int failures = 0;

  /// Makes the next [count] statements that change [table] fail.
  void failNextWrites(String table, int count) {
    failures = 0;
    _table = RegExp(
      '^\\s*(INSERT|UPDATE|DELETE|REPLACE)\\b[^;]*\\b$table\\b',
      caseSensitive: false,
    );
    _remaining = count;
  }

  void _maybeFail(String statement) {
    final RegExp? table = _table;
    if (_remaining > 0 && table != null && table.hasMatch(statement)) {
      _remaining--;
      failures++;
      throw TransientDatabaseException('simulated: the database is busy');
    }
  }

  @override
  String get path => _database.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) {
    _maybeFail(statement);
    return _database.execute(statement, arguments);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) {
    _maybeFail(statement);
    return _database.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) {
    _maybeFail(statement);
    return _database.delete(statement, arguments);
  }

  @override
  void close() => _database.close();
}

Future<void> _nothing(Database db) async {}

Future<void> _nothingFor(Database db, int version) async {}

Future<void> _nothingBetween(Database db, int from, int to) async {}
