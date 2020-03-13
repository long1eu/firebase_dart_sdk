// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/transaction.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/transaction';
  Firestore firestore;

  setUp(() async {
    firestore = await testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testGetDocuments', () async {
    final DocumentReference doc = firestore.collection('spaces').document();
    final Map<String, Object> value =
        map(<dynamic>['foo', 1, 'desc', 'Stuff', 'owner', 'Jonny']);
    await doc.set(value);

    try {
      await firestore
          .runTransaction((Transaction transaction) => transaction.get(doc));
    } catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Fix this check once we drop that requirement.
      expect(e.message, 'Transaction failed all retries.');
      expect(e.cause.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testDeleteDocument', () async {
    final DocumentReference doc = firestore.collection('towns').document();
    await doc.set(map(<String>['foo', 'bar']));
    DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.getString('foo'), 'bar');
    await firestore.runTransaction<void>((Transaction transaction) {
      transaction.delete(doc);
      return null;
    });
    snapshot = await doc.get();
    expect(snapshot.exists, isFalse);
  });

  test('testGetNonexistentDocumentThenCreate', () async {
    final DocumentReference docRef = firestore.collection('towns').document();
    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot docSnap = await transaction.get(docRef);
      expect(docSnap.exists, isFalse);
      transaction.set(docRef, map(<String>['foo', 'bar']));
      return null;
    });
    final DocumentSnapshot snapshot = await docRef.get();
    expect(snapshot.getString('foo'), 'bar');
  });

  test('testWriteDocumentTwice', () async {
    final DocumentReference doc = firestore.collection('towns').document();
    await firestore.runTransaction<void>((Transaction transaction) {
      transaction
          .set(doc, map(<String>['a', 'b']))
          .set(doc, map(<String>['c', 'd']));
      return null;
    });
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.data, map<String>(<String>['c', 'd']));
  });

  test('testSetDocumentWithMerge', () async {
    final DocumentReference doc = firestore.collection('towns').document();
    await firestore.runTransaction<void>((Transaction transaction) {
      transaction
          .set(
              doc,
              map(<dynamic>[
                'a',
                'b',
                'nested',
                map<String>(<String>['a', 'b'])
              ]))
          .set(
              doc,
              map(<dynamic>[
                'c',
                'd',
                'nested',
                map<String>(<String>['c', 'd'])
              ]),
              SetOptions.mergeAllFields);
      return null;
    });
    final DocumentSnapshot snapshot = await doc.get();
    expect(
        snapshot.data,
        map<dynamic>(<dynamic>[
          'a',
          'b',
          'c',
          'd',
          'nested',
          map<String>(<String>['a', 'b', 'c', 'd'])
        ]));
  });

  test('testIncrementTransactionally', () async {
    // A set of concurrent transactions.
    final List<Future<void>> transactionTasks = <Future<void>>[];
    final List<Future<void>> readTasks = <Future<void>>[];
    // A barrier to make sure every transaction reaches the same spot.
    final Completer<void> barrier = Completer<void>();
    int started = 0;

    final DocumentReference doc = firestore.collection('counters').document();
    await doc.set(map(<dynamic>['count', 5.0]));

    // Make 3 transactions that will all increment.
    for (int i = 0; i < 3; i++) {
      final Completer<void> resolveRead = Completer<void>();
      readTasks.add(resolveRead.future);
      transactionTasks
          .add(firestore.runTransaction<void>((Transaction transaction) async {
        final DocumentSnapshot snapshot = await transaction.get(doc);
        expect(snapshot, isNotNull);
        started++;

        if (!resolveRead.isCompleted) {
          resolveRead.complete(null);
        }

        await barrier.future;
        transaction.set(
            doc, map(<dynamic>['count', snapshot.getDouble('count') + 1.0]));
        return null;
      }));
    }

    // Let all of the transactions fetch the old value and stop once.
    await Future.wait(readTasks);
    expect(started, 3);
    // Let all of the transactions continue and wait for them to finish.
    barrier.complete(null);
    await Future.wait(transactionTasks);
    // Now all transaction should be completed, so check the result.
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.getDouble('count').toInt(), 8);
  });

  test('testTransactionRejectsUpdatesForNonexistentDocuments', () async {
    // Make a transaction that will fail
    final Future<void> transactionTask =
        firestore.runTransaction<void>((Transaction transaction) async {
      // Get and update a document that doesn't exist so that the transaction fails
      final DocumentSnapshot doc =
          await transaction.get(firestore.collection('nonexistent').document());
      transaction.updateFromList(doc.reference, <String>['foo', 'bar']);
      return null;
    });

    try {
      await transactionTask;
    } catch (e) {
      // Let all of the transactions fetch the old value and stop once.
      // TODO(long1eu): should this really be raised as a FirebaseFirestoreError?
      // Note that this test might change if transaction.get throws a FirebaseFirestoreError.
      expect(e, const TypeMatcher<StateError>());
    }
  });

  test('testCantDeleteDocumentThenPatch', () async {
    final DocumentReference docRef = firestore.collection('docs').document();
    await docRef.set(map(<String>['foo', 'bar']));

    // Make a transaction that will fail
    final Future<void> transactionTask =
        firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot doc = await transaction.get(docRef);
      expect(doc.exists, isTrue);
      transaction
        ..delete(docRef)
        // Since we deleted the doc, the update will fail
        ..updateFromList(docRef, <String>['foo', 'bar']);
      return null;
    });

    try {
      // Let all of the transactions fetch the old value and stop once.
      await transactionTask;
    } catch (e) {
      // TODO(long1eu): should this really be raised as a FirebaseFirestoreError?
      // Note that this test might change if transaction.update throws a FirebaseFirestoreError.
      expect(e, const TypeMatcher<StateError>());
    }
  });

  test('testCantDeleteDocumentThenSet', () async {
    final DocumentReference docRef = firestore.collection('docs').document();
    await docRef.set(map(<String>['foo', 'bar']));

    // Make a transaction that will fail
    final Future<void> transactionTask =
        firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot doc = await transaction.get(docRef);
      expect(doc.exists, isTrue);
      transaction
        ..delete(docRef)
        // TODO(long1eu): In theory this should work, but it's complex to make it work, so instead we just let the
        //  transaction fail and verify it's unsupported for now
        ..set(docRef, map(<String>['foo', 'new-bar']));
      return null;
    });

    try {
      // Let all of the transactions fetch the old value and stop once.
      await transactionTask;
    } catch (e) {
      expect(e, const TypeMatcher<FirebaseFirestoreError>());

      final FirebaseFirestoreError error = e;
      expect(error.code, FirestoreErrorCode.aborted);
    }
  });

  test('testTransactionRaisesErrorsForInvalidUpdates', () async {
    // Make a transaction that will fail server-side.
    final Future<void> transactionTask =
        firestore.runTransaction<void>((Transaction transaction) async {
      // Try to read / write a document with an invalid path.
      final DocumentSnapshot doc = await transaction
          .get(firestore.collection('nonexistent').document('__badpath__'));
      transaction.set(doc.reference, map(<String>['foo', 'value']));
      return null;
    });

    try {
      // Let all of the transactions fetch the old value and stop once.
      await transactionTask;
    } catch (e) {
      expect(e, const TypeMatcher<FirebaseFirestoreError>());
      print(e);

      final FirebaseFirestoreError error = e;
      expect(error.code, FirestoreErrorCode.invalidArgument);
    }
  });

  test('testUpdateTransactionally', () async {
    // A set of concurrent transactions.
    final List<Future<void>> transactionTasks = <Future<void>>[];
    final List<Future<void>> readTasks = <Future<void>>[];
    // A barrier to make sure every transaction reaches the same spot.
    final Completer<void> barrier = Completer<void>();
    int started = 0;

    final DocumentReference doc = firestore.collection('counters').document();
    await doc.set(map(<dynamic>['count', 5.0, 'other', 'yes']));

    // Make 3 transactions that will all increment.
    for (int i = 0; i < 3; i++) {
      final Completer<void> resolveRead = Completer<void>();
      readTasks.add(resolveRead.future);
      transactionTasks
          .add(firestore.runTransaction<void>((Transaction transaction) async {
        final DocumentSnapshot snapshot = await transaction.get(doc);
        expect(snapshot, isNotNull);
        started++;
        if (!resolveRead.isCompleted) {
          resolveRead.complete();
        }
        await barrier.future;

        transaction.update(
            doc, map(<dynamic>['count', snapshot.getDouble('count') + 1.0]));
        return null;
      }));
    }

    // Let all of the transactions fetch the old value and stop once.
    await Future.wait(readTasks);
    expect(started, 3);
    // Let all of the transactions continue and wait for them to finish.
    barrier.complete();
    await Future.wait(transactionTasks);
    // Now all transaction should be completed, so check the result.
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.getDouble('count').toInt(), 8);
    expect(snapshot.getString('other'), 'yes');
  });

  test('testUpdateFieldsWithDotsTransactionally', () async {
    final DocumentReference doc = firestore.collection('fieldnames').document();
    await doc.set(map(<String>['a.b', 'old', 'c.d', 'old']));

    await firestore.runTransaction<void>((Transaction transaction) {
      transaction
        ..updateFromList(doc, <dynamic>[
          FieldPath.of(<String>['a.b']),
          'new'
        ])
        ..updateFromList(doc, <dynamic>[
          FieldPath.of(<String>['c.d']),
          'new'
        ]);
      return null;
    });

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map<String>(<String>['a.b', 'new', 'c.d', 'new']));
  });

  test('testUpdateNestedFieldsTransactionally', () async {
    final DocumentReference doc = firestore.collection('fieldnames').document();
    await doc.set(map(<dynamic>[
      'a',
      map<String>(<String>['b', 'old']),
      'c',
      map<String>(<String>['d', 'old'])
    ]));

    await firestore.runTransaction<void>((Transaction transaction) {
      transaction
        ..updateFromList(doc, <String>['a.b', 'new'])
        ..update(doc, map<String>(<String>['c.d', 'new']));
      return null;
    });

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(
        snapshot.data,
        map<dynamic>(<dynamic>[
          'a',
          map<String>(<String>['b', 'new']),
          'c',
          map<String>(<String>['d', 'new'])
        ]));
  });

  test('testHandleReadingOneDocAndWritingAnother', () async {
    final DocumentReference doc1 = firestore.collection('counters').document();
    final DocumentReference doc2 = firestore.collection('counters').document();
    await doc1.set(map(<dynamic>['count', 15]));

    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        // Get the first doc.
        await transaction.get(doc1);
        // Do a write outside of the transaction. The first time the transaction is tried, this will bump the version,
        // which will cause the write to doc2 to fail. The second time, it will be a no-op and not bump the version.
        await doc1.set(map(<dynamic>['count', 1234]));
        // Now try to update the other doc from within the transaction. This should fail once, because we read 15
        // earlier.
        transaction.set(doc2, map(<dynamic>['count', 16]));
        return null;
      });
    } catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Add this check back once we drop that.
      // Document snapshot = await doc1.get();
      // expect(tries.getCount(), 0);
      // expect(snapshot.getDouble('count'), 1234);
      // snapshot = await doc2.get();
      // expect(snapshot.getDouble('count'), 16);
      expect(e.message, 'Transaction failed all retries.');
      expect(e.cause.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testReadingADocTwiceWithDifferentVersions', () async {
    final DocumentReference doc = firestore.collection('counters').document();
    await doc.set(map(<dynamic>['count', 15.0]));

    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        // Get the doc once.
        final DocumentSnapshot snapshot1 = await transaction.get(doc);
        expect(snapshot1.getDouble('count').toInt(), 15);
        // Do a write outside of the transaction.
        await doc.set(map(<dynamic>['count', 1234.0]));
        // Get the doc again in the transaction with the new version.
        final DocumentSnapshot _ = await transaction.get(doc);
        // The get itself will fail, because we already read an earlier version of this document.
        fail('Should have thrown exception');
      });
    } catch (_) {}

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.getDouble('count').toInt(), 1234);
  });

  test('testCannotReadAfterWriting', () async {
    final DocumentReference doc = firestore.collection('anything').document();

    try {
      await firestore.runTransaction<void>((Transaction transaction) {
        transaction.set(doc, map(<String>['foo', 'bar']));
        return transaction.get(doc);
      });
    } catch (e) {
      expect(e, isNotNull);
    }
  });

  test('testCannotHaveAGetWithoutMutations', () async {
    final DocumentReference doc = firestore.collection('foo').document();
    await doc.set(map(<String>['foo', 'bar']));

    try {
      await firestore.runTransaction<void>(
          (Transaction transaction) => transaction.get(doc));
    } catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Add this check back once we drop that.
      // expect(snapshot.getString('foo'), 'bar');
      expect(e.message, 'Transaction failed all retries.');
      expect(e.cause.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testSuccessWithNoTransactionOperations', () async {
    await firestore.runTransaction<void>((Transaction transaction) => null);
  });

  test('testCancellationOnThrow', () async {
    final DocumentReference doc = firestore.collection('towns').document();
    int count = 0;

    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        count++;
        transaction.set(doc, map(<String>['foo', 'bar']));
        throw StateError('no');
      });
    } catch (e) {
      expect(e.message, 'no');
      expect(count, 1);
    }

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isFalse);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types, type_annotate_public_apis
const testDocumentWithData = IntegrationTestUtil.testDocumentWithData;
// ignore: always_specify_types, type_annotate_public_apis
const toDataMap = IntegrationTestUtil.toDataMap;
// ignore: always_specify_types, type_annotate_public_apis
const testDocument = IntegrationTestUtil.testDocument;
