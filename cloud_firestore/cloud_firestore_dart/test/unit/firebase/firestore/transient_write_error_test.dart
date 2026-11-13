// A write whose mutation can not be stored because the database is busy for a
// moment (a TransientDatabaseException) fails the future of the write with
// `unavailable`, as `firestoreClientWrite` and `syncEngineWrite` do in the JS
// SDK (packages/firestore/src/core/firestore_client.ts,
// packages/firestore/src/core/sync_engine_impl.ts). Before, the error reached
// the completer of the write before anyone listened to it and surfaced as an
// uncaught error of the zone instead.

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/test_hygiene.dart';
import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings;
import 'local/mock/database_mock.dart';

/// Fails the next [failures] statements that insert into `mutations`.
class _BusyMutationsDatabase implements Database {
  _BusyMutationsDatabase(this._database);

  final Database _database;
  int failures = 0;

  void _maybeFail(String statement) {
    if (failures > 0 &&
        RegExp(r'^\s*INSERT\b[^;]*\bmutations\b').hasMatch(statement)) {
      failures--;
      throw TransientDatabaseException('busy');
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

void main() {
  checkTestsLeaveNothingBehind();

  test('a write that can not be stored fails with unavailable', () async {
    final String name = 'transient-write-${const Uuid().v4()}';
    final FirebaseApp app = newApp(name);
    addTearDown(app.delete);
    late _BusyMutationsDatabase database;
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase:
          (
            String path, {
            int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen,
          }) async {
            final DatabaseMock mock = await DatabaseMock.create(
              name,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen,
            );
            return database = _BusyMutationsDatabase(mock);
          },
    );
    addTearDown(firestore.clearPersistence);
    addTearDown(firestore.terminate);
    final DocumentReference<Map<String, Object?>> doc = firestore.doc(
      'col/doc',
    );
    // Opens the cache.
    await doc.get(Source.cache).then((_) {}, onError: (Object _) {});

    database.failures = 1;
    await expectLater(
      doc.set(<String, Object?>{'a': 1}),
      throwsA(firestoreErrorWithCode(FirestoreErrorCode.unavailable)),
    );

    // Nothing was stored (a cache read of a document that is not in the cache
    // fails), and the next write is.
    await expectLater(
      doc.get(Source.cache),
      throwsA(firestoreErrorWithCode(FirestoreErrorCode.unavailable)),
    );
    // ignore: unawaited_futures, the write stays pending: nothing listens on the port.
    doc.set(<String, Object?>{'a': 2});
    expect((await doc.get(Source.cache)).data, <String, Object?>{'a': 2});
  });
}
