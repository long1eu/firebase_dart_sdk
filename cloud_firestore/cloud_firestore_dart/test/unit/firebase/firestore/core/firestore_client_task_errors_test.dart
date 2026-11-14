// The errors of client operations are settled inside the operation on the
// queue of the client, as the JS SDK does with a `Deferred`
// (packages/firestore/src/core/firestore_client.ts,
// packages/firestore/src/core/sync_engine_impl.ts): the caller gets the error,
// and no error leaves the operation on the queue.

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_hygiene.dart';
import '../clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings;
import '../local/mock/database_mock.dart';

/// Fails the statements that match [pattern] with the error of [error].
class _FaultyDatabase implements Database {
  _FaultyDatabase(this._database);

  final Database _database;
  RegExp? pattern;
  Object Function()? error;

  void _maybeFail(String statement) {
    final RegExp? pattern = this.pattern;
    if (pattern != null && pattern.hasMatch(statement)) {
      throw error!();
    }
  }

  void fail(String pattern, Object Function() error) {
    this.pattern = RegExp(pattern);
    this.error = error;
  }

  void heal() => pattern = null;

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

TransientDatabaseException _busy() => TransientDatabaseException('busy');

TypeMatcher<FirestoreError> _unavailable(String messagePrefix) =>
    firestoreErrorWithCode(FirestoreErrorCode.unavailable).having(
      (FirestoreError e) => e.message,
      'message',
      startsWith(messagePrefix),
    );

void main() {
  checkTestsLeaveNothingBehind();

  late _FaultyDatabase database;
  late Firestore firestore;
  late DocumentReference<Map<String, Object?>> doc;

  SerialQueue queue() => firestore.client.queue;

  /// Nothing left an operation of the queue, and the client still works.
  Future<void> expectClientWorks() async {
    database.heal();
    expect(queue().escapedErrors, 0);
    // ignore: unawaited_futures, the write stays pending: nothing listens on the port.
    doc.set(<String, Object?>{'works': true});
    expect((await doc.get(Source.cache)).data, <String, Object?>{
      'works': true,
    });
    expect(queue().escapedErrors, 0);
  }

  Future<void> open({Object Function()? openError}) async {
    final String name = 'task-errors-${const Uuid().v4()}';
    final FirebaseApp app = newApp(name);
    addTearDown(app.delete);
    firestore = Firestore.instanceFor(
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
            if (openError != null) {
              throw openError();
            }
            final DatabaseMock mock = await DatabaseMock.create(
              name,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen,
            );
            return database = _FaultyDatabase(mock);
          },
    );
    addTearDown(firestore.clearPersistence);
    addTearDown(firestore.terminate);
    doc = firestore.doc('col/doc');
    if (openError == null) {
      // Opens the cache.
      await doc.get(Source.cache).then((_) {}, onError: (Object _) {});
    }
  }

  group('a cache read of a document', () {
    test('fails with unavailable when the persistence is busy', () async {
      await open();
      database.fail(r'\bremote_documents\b', _busy);
      await expectLater(
        doc.get(Source.cache),
        throwsA(
          _unavailable('Failed to get document ').having(
            (FirestoreError e) => e.message,
            'message',
            contains('from cache: TransientDatabaseException: busy'),
          ),
        ),
      );
      await expectClientWorks();
    });

    test('fails with any other error of the read as it is', () async {
      await open();
      final StateError error = StateError('broken');
      database.fail(r'\bremote_documents\b', () => error);
      await expectLater(doc.get(Source.cache), throwsA(same(error)));
      await expectClientWorks();
    });
  });

  group('a cache read of a query', () {
    test('fails with unavailable when the persistence is busy', () async {
      await open();
      database.fail(r'\bremote_documents\b', _busy);
      await expectLater(
        firestore.collection('col').get(Source.cache),
        throwsA(_unavailable('Failed to execute query ')),
      );
      await expectClientWorks();
    });

    test('fails with any other error of the read as it is', () async {
      await open();
      final StateError error = StateError('broken');
      database.fail(r'\bremote_documents\b', () => error);
      await expectLater(
        firestore.collection('col').get(Source.cache),
        throwsA(same(error)),
      );
      await expectClientWorks();
    });
  });

  group('a write', () {
    test('fails with unavailable when the persistence is busy', () async {
      await open();
      database.fail(r'^\s*INSERT\b[^;]*\bmutations\b', _busy);
      await expectLater(
        doc.set(<String, Object?>{'a': 1}),
        throwsA(_unavailable('Failed to persist write: ')),
      );
      await expectClientWorks();
    });

    test('fails with any other error of the local write as it is', () async {
      await open();
      final StateError error = StateError('broken');
      database.fail(r'^\s*INSERT\b[^;]*\bmutations\b', () => error);
      // The write API reports an error that is not a FirestoreError as `unknown`.
      await expectLater(
        doc.set(<String, Object?>{'a': 1}),
        throwsA(
          firestoreErrorWithCode(FirestoreErrorCode.unknown).having(
            (FirestoreError e) => e.message,
            'message',
            'Bad state: broken',
          ),
        ),
      );
      await expectClientWorks();
    });
  });

  group('a listener', () {
    test('gets unavailable when the persistence is busy', () async {
      await open();
      database.fail(r'\btargets\b', _busy);
      await expectLater(
        doc.snapshots.first,
        throwsA(_unavailable('Initialization of query ')),
      );
      await expectClientWorks();
    });

    test('gets any other error of the local query as it is', () async {
      await open();
      final StateError error = StateError('broken');
      database.fail(r'\btargets\b', () => error);
      await expectLater(doc.snapshots.first, throwsA(same(error)));
      await expectClientWorks();
    });
  });

  group('waitForPendingWrites', () {
    test('fails with unavailable when the persistence is busy', () async {
      await open();
      database.fail(r'\bmutations\b', _busy);
      await expectLater(
        firestore.waitForPendingWrites(),
        throwsA(
          _unavailable(
            'Initialization of waitForPendingWrites() operation failed: ',
          ),
        ),
      );
      await expectClientWorks();
    });

    test('fails with any other error of the persistence as it is', () async {
      await open();
      final StateError error = StateError('broken');
      database.fail(r'\bmutations\b', () => error);
      await expectLater(firestore.waitForPendingWrites(), throwsA(same(error)));
      await expectClientWorks();
    });
  });

  test(
    'every operation fails with the error of a failed initialization',
    () async {
      final FirestoreError error = FirestoreError(
        'The cache can not be opened',
        FirestoreErrorCode.failedPrecondition,
      );
      await open(openError: () => error);

      // The write API reports an error that is not a FirestoreError as `unknown`.
      await expectLater(
        doc.set(<String, Object?>{'a': 1}),
        throwsA(same(error)),
      );
      await expectLater(
        firestore.collection('col').get(Source.cache),
        throwsA(same(error)),
      );
      await expectLater(firestore.waitForPendingWrites(), throwsA(same(error)));
      await expectLater(doc.snapshots.first, throwsA(same(error)));
      expect(queue().escapedErrors, 0);
    },
  );
}
