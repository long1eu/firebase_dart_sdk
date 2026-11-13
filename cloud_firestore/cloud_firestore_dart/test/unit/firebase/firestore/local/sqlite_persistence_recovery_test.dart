// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

/// [SQLitePersistence] with a database that is not available for a while (a [TransientDatabaseException]). The
/// counterparts of the `IndexedDbTransactionError` tests of the JS SDK
/// (packages/firestore/test/unit/local/indexeddb_persistence.test.ts, "allowTabSynchronization").
void main() {
  late _FailingDatabase database;
  late SQLitePersistence persistence;

  Future<SQLitePersistence> create() {
    final String name = 'recovery-${const Uuid().v4()}';
    final DatabaseId databaseId = DatabaseId.forProject('projectId');
    return SQLitePersistence.create(
      name,
      databaseId,
      LocalSerializer(RemoteSerializer(databaseId)),
      (
        String path, {
        int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen,
      }) async {
        database = _FailingDatabase(
          await DatabaseMock.create(
            name,
            version: version,
            onConfigure: onConfigure,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
            onDowngrade: onDowngrade,
            onOpen: onOpen,
          ),
        );
        return database;
      },
      const LruGarbageCollectorParams(),
    );
  }

  test('ignores intermittent transient errors during lease refresh', () async {
    persistence = await create();
    await persistence.start();
    expect(persistence.isPrimary, isTrue);

    database.failing = true;
    // The refresh fails: it is logged and the state stays as it was.
    await persistence.refreshClientMetadata();
    expect(persistence.isPrimary, isTrue);

    database.failing = false;
    await persistence.runPrimaryTransaction<void>('check success', () async {});
    await persistence.shutdown();
  });

  test('a transaction that fails transiently can be run again', () async {
    persistence = await create();
    await persistence.start();

    database.failing = true;
    final Object error = await persistence
        .runTransaction('Simulated', () async {})
        .then<Object>((_) => 'no error', onError: (Object e) => e);
    expect(error, isA<TransientDatabaseException>());
    expect(isRecoverablePersistenceError(error), isTrue);

    database.failing = false;
    await persistence.runTransaction('check success', () async {});
    await persistence.shutdown();
  });

  test('blocks start() on a transient error of the client metadata', () async {
    // PORTING NOTE: JS blocks start() of a client without tab synchronization; the port has no such setting and
    // always fails the start, so that the client reports the error of its initialization.
    persistence = await create();
    _FailingDatabase.failNextStart = true;
    await expectLater(
      persistence.start(),
      throwsA(isA<TransientDatabaseException>()),
    );
    // A persistence whose start failed is not started (it can not be shut down) and has closed its connection.
    expect(persistence.started, isFalse);
    expect(database.closed, isTrue);
  });
}

/// A [Database] that throws a [TransientDatabaseException] for every statement while [failing], as a database that is
/// locked by another connection or can not be written does.
class _FailingDatabase implements Database {
  _FailingDatabase(this._delegate) {
    if (failNextStart) {
      failNextStart = false;
      failing = true;
      // Fails from the first transaction on: the schema setup is done by the opener, before this database is returned.
    }
  }

  /// Makes the next database fail right after it was opened.
  static bool failNextStart = false;

  final Database _delegate;
  bool failing = false;

  void _check(String statement) {
    if (failing) {
      throw TransientDatabaseException('Simulated error', statement);
    }
  }

  @override
  String get path => _delegate.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {
    _check(statement);
    await _delegate.execute(statement, arguments);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) async {
    _check(statement);
    return _delegate.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async {
    _check(statement);
    return _delegate.delete(statement, arguments);
  }

  /// Whether [close] was called.
  bool closed = false;

  @override
  void close() {
    closed = true;
    _delegate.close();
  }
}
