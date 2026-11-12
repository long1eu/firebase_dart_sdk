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
import 'package:cloud_firestore_vm/src/firebase/firestore/transaction_options.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/transaction';
  late Firestore firestore;

  setUp(() async {
    firestore = await testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testGetDocuments', () async {
    final DocumentReference doc = firestore.collection('spaces').document();
    final Map<String, Object?> value =
        map(<dynamic>['foo', 1, 'desc', 'Stuff', 'owner', 'Jonny']);
    await doc.set(value);

    try {
      await firestore
          .runTransaction((Transaction transaction) => transaction.get(doc));
    } on FirestoreError catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Fix this check once we drop that requirement.
      expect(e.code, FirestoreErrorCode.invalidArgument);
      expect(e.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testReadOnlyTransactionReadsWithoutWriting', () async {
    final DocumentReference doc = firestore.collection('spaces').document();
    await doc.set(map(<dynamic>['foo', 1]));

    final DocumentSnapshot snapshot = await firestore.runTransaction(
        (Transaction transaction) => transaction.get(doc),
        options: TransactionOptions(readOnly: true));
    expect(snapshot.getDouble('foo'), 1);

    await expectLater(
        firestore.runTransaction((Transaction transaction) async {
          await transaction.get(doc);
          transaction.set(doc, map(<dynamic>['foo', 2]));
        }, options: TransactionOptions(readOnly: true)),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.invalidArgument)));
  });

  test('testReadOnlyTransactionRetriesWhenADocumentChanges', () async {
    final DocumentReference doc = firestore.collection('spaces').document();
    await doc.set(map(<dynamic>['foo', 1]));

    int attempts = 0;
    final Object? result =
        await firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot snapshot = await transaction.get(doc);
      if (attempts++ == 0) {
        // Changes the document after it was read, so the verification fails.
        await doc.set(map(<dynamic>['foo', 2]));
      }
      return snapshot.get('foo');
    }, options: TransactionOptions(readOnly: true));

    expect(attempts, 2);
    expect(result, 2);
  });

  test('testRunsTransactionsAfterGettingExistingDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  test('testRunsTransactionsAfterGettingNonexistentDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.set2
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  test('testRunsTransactionsOnExistingDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withExistingDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  test('testRunsTransactionsOnNonexistentDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectError(FirestoreErrorCode.notFound);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.notFound);
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.set2
    ])._expectError(FirestoreErrorCode.notFound);

    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
    await tt.withNonexistentDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  // This test is identical to testRunsTransactionsAfterGettingNonexistentDoc, except that withNonexistentDoc() is
  // replaced by withDeletedDoc(), to guard against regression of firebase-js-sdk issue 5871, where transactions would
  // incorrectly fail with FAILED_PRECONDITION when operations were performed on a deleted document (rather than a
  // non-existent document).
  test('testRunsTransactionsAfterGettingDeletedDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.update1,
      TransactionTester.set2
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.get,
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  test('testRunsTransactionsOnDeletedDoc', () async {
    final Firestore firestore = await testFirestore();
    final TransactionTester tt = TransactionTester._(firestore);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.delete1
    ])._expectNoDoc();

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.invalidArgument);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.delete1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.delete1
    ])._expectError(FirestoreErrorCode.notFound);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.update2
    ])._expectError(FirestoreErrorCode.notFound);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.update1,
      TransactionTester.set2
    ])._expectError(FirestoreErrorCode.notFound);

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.delete1
    ])._expectNoDoc();

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.update2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));

    await tt.withDeletedDoc().run(<TransactionStage>[
      TransactionTester.set1,
      TransactionTester.set2
    ]).expectDoc(map<String>(<String>['foo', 'bar2']));
  });

  test('testRetryOnAlreadyExistsError', () async {
    final Firestore firestore = await testFirestore();
    final DocumentReference doc = firestore.collection('foo').document();
    int transactionCallbackCount = 0;
    await firestore.runTransaction<void>((Transaction transaction) async {
      transactionCallbackCount++;
      await transaction.get(doc);
      // Do a write outside of the transaction.
      if (transactionCallbackCount == 1) {
        await doc.set(map(<String>['foo1', 'bar1']));
      }
      // Now try to set the doc within the transaction. This should fail once with ALREADY_EXISTS error.
      transaction.set(doc, map(<String>['foo2', 'bar2']));
      return null;
    });
    final DocumentSnapshot snapshot = await doc.get();
    expect(transactionCallbackCount, 2);
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map(<String>['foo2', 'bar2']));
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
      return Future<void>.value();
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
            doc, map(<dynamic>['count', snapshot.getDouble('count')! + 1.0]));
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
    expect(snapshot.getDouble('count')!.toInt(), 8);
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
      expect(e, const TypeMatcher<FirestoreError>());
      print(e);

      final FirestoreError error = e as FirestoreError;
      expect(error.code, FirestoreErrorCode.invalidArgument);
    }
  });

  test('testUpdateTransactionally', () async {
    // A set of concurrent transactions.
    final List<Future<void>> transactionTasks = <Future<void>>[];
    final List<Future<void>> readTasks = <Future<void>>[];
    // A barrier to make sure every transaction reaches the same spot.
    final Completer<void> barrier = Completer<void>();
    int counter = 0;

    final DocumentReference doc = firestore.collection('counters').document();
    await doc.set(map(<dynamic>['count', 5.0, 'other', 'yes']));

    // Make 3 transactions that will all increment.
    for (int i = 0; i < 3; i++) {
      final Completer<void> resolveRead = Completer<void>();
      readTasks.add(resolveRead.future);
      transactionTasks
          .add(firestore.runTransaction<void>((Transaction transaction) async {
        counter++;
        final DocumentSnapshot snapshot = await transaction.get(doc);
        expect(snapshot, isNotNull);
        if (!resolveRead.isCompleted) {
          resolveRead.complete();
        }
        await barrier.future;

        transaction.update(
            doc, map(<dynamic>['count', snapshot.getDouble('count')! + 1.0]));
        return null;
      }));
    }

    // Let all of the transactions fetch the old value and stop once.
    await Future.wait(readTasks);
    // There should be 3 initial transaction runs
    expect(counter, 3);
    barrier.complete();
    await Future.wait(transactionTasks);
    // There should be a maximum of 3 retries: once for the 2nd update, and
    // twice for the 3rd update
    expect(counter, lessThanOrEqualTo(6));
    // Now all transaction should be completed, so check the result.
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.getDouble('count')!.toInt(), 8);
    expect(snapshot.getString('other'), 'yes');
  });

  test('testMakesDefaultMaxAttempts', () async {
    final DocumentReference doc1 = firestore.collection('counters').document();
    int count = 0;
    await doc1.set(map(<dynamic>['count', 15]));

    Object? error;
    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        // Get the first doc.
        await transaction.get(doc1);
        // Do a write outside of the transaction to cause the transaction to
        // fail.
        await doc1.set(map(<dynamic>['count', 1234 + ++count]));
        transaction.update(doc1, map(<dynamic>['count', 1]));
      });
    } catch (e) {
      error = e;
    }

    expect(error, isA<FirestoreError>());
    expect(
        (error! as FirestoreError).code, FirestoreErrorCode.failedPrecondition);
    expect(count, TransactionOptions.defaultMaxAttempts);
  });

  test('testMakesOptionSpecifiedMaxAttempts', () async {
    final TransactionOptions options = TransactionOptions(maxAttempts: 1);
    final DocumentReference doc1 = firestore.collection('counters').document();
    int count = 0;
    await doc1.set(map(<dynamic>['count', 15]));

    Object? error;
    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        await transaction.get(doc1);
        await doc1.set(map(<dynamic>['count', 1234 + ++count]));
        transaction.update(doc1, map(<dynamic>['count', 1]));
      }, options: options);
    } catch (e) {
      error = e;
    }

    expect(error, isA<FirestoreError>());
    expect(
        (error! as FirestoreError).code, FirestoreErrorCode.failedPrecondition);
    expect(count, options.maxAttempts);
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
      return Future<void>.value();
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
      return Future<void>.value();
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
    } on FirestoreError catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Add this check back once we drop that.
      // Document snapshot = await doc1.get();
      // expect(tries.getCount(), 0);
      // expect(snapshot.getDouble('count'), 1234);
      // snapshot = await doc2.get();
      // expect(snapshot.getDouble('count'), 16);
      expect(e.code, FirestoreErrorCode.invalidArgument);
      expect(e.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testReadingADocTwiceWithDifferentVersions', () async {
    final DocumentReference doc = firestore.collection('counters').document();
    await doc.set(map(<dynamic>['count', 15.0]));
    int counter = 0;

    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        counter++;
        // Get the doc once.
        await transaction.get(doc);
        // Do a write outside of the transaction. Because the transaction will
        // retry, set the document to a different value each time.
        await doc.set(map(<dynamic>['count', 1234.0 + counter]));
        // Get the doc again in the transaction with the new version.
        final DocumentSnapshot _ = await transaction.get(doc);
        // The get itself will fail, because we already read an earlier version of this document.
        fail('Should have thrown exception');
      });
    } on FirestoreError catch (e) {
      expect(e.code, FirestoreErrorCode.aborted);
    }
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

  test('testReadAndUpdateNonExistentDocumentWithExternalWrite', () async {
    final Firestore firestore = await testFirestore();

    try {
      await firestore.runTransaction<void>((Transaction transaction) async {
        // Get and update a document that doesn't exist so that the transaction fails.
        final DocumentReference doc =
            firestore.collection('nonexistent').document();
        await transaction.get(doc);
        // Do a write outside of the transaction.
        await doc.set(map(<dynamic>['count', 1234]));
        // Now try to update the other doc from within the transaction.
        // This should fail, because the document didn't exist at the
        // start of the transaction.
        transaction.update(doc, <String, int>{'count': 16});
        return null;
      });
    } on FirestoreError catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Add this check back once we drop that.
      // expect(snapshot.getString('foo'), 'bar');
      expect(e.code, FirestoreErrorCode.invalidArgument);
      expect(e.message, 'Can\'t update a document that doesn\'t exist.');
    }
  });

  test('testCannotHaveAGetWithoutMutations', () async {
    final DocumentReference doc = firestore.collection('foo').document();
    await doc.set(map(<String>['foo', 'bar']));

    try {
      await firestore.runTransaction<void>(
          (Transaction transaction) => transaction.get(doc));
    } on FirestoreError catch (e) {
      // We currently require every document read to also be written.
      // TODO(long1eu): Add this check back once we drop that.
      // expect(snapshot.getString('foo'), 'bar');
      expect(e.code, FirestoreErrorCode.invalidArgument);
      expect(e.message,
          'Every document read in a transaction must also be written.');
    }
  });

  test('testDoesNotRetryOnPermanentError', () async {
    final Firestore firestore = await testFirestore();
    int count = 0;
    try {
      // Make a transaction that should fail with a permanent error
      await firestore.runTransaction((Transaction transaction) async {
        count++;
        // Get and update a document that doesn't exist so that the transaction fails
        final DocumentSnapshot doc = await transaction
            .get(firestore.collection('nonexistent').document());
        transaction.update(doc.reference, <String, String>{'foo': 'bar'});
        return null;
      });
    } on FirestoreError catch (e) {
      expect(e.code, FirestoreErrorCode.invalidArgument);
      expect(count, 1);
    }
  });

  test('testSuccessWithNoTransactionOperations', () async {
    await firestore.runTransaction<void>(
        (Transaction transaction) => Future<void>.value());
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
      expect((e as StateError).message, 'no');
      expect(count, 1);
    }

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isFalse);
  });
  test('testRetriesWhenDocumentThatWasReadWithoutBeingWrittenChanges',
      () async {
    final DocumentReference doc1 = firestore.collection('counters').document();
    final DocumentReference doc2 = firestore.collection('counters').document();
    int attempts = 0;
    await doc1.set(map<dynamic>(<dynamic>['count', 15]));
    await firestore.runTransaction<void>((Transaction transaction) async {
      attempts++;
      // Get the first doc.
      await transaction.get(doc1);
      // Write outside of the transaction. The first time the transaction runs this bumps the version, which makes the
      // write to doc2 fail; the second time it is a no-op and does not bump the version.
      await doc1.set(map<dynamic>(<dynamic>['count', 1234]));
      // This must fail once, because the transaction read 15 earlier.
      transaction.set(doc2, map<dynamic>(<dynamic>['count', 16]));
    });
    final DocumentSnapshot snapshot = await doc1.get();
    expect(attempts, 2);
    expect(snapshot.exists, isTrue);
    expect(snapshot.data!['count'], 1234);
  },
      skip:
          'Needs upstream ef38ef7 (VerifyMutation for documents that were read but not written, analysis_0.md): core/transaction.dart still fails read-without-write transactions with "Every document read in a transaction must also be written."');

  test('testCanHaveGetsWithoutMutations', () async {
    final DocumentReference doc = firestore.collection('foo').document();
    final DocumentReference doc2 = firestore.collection('foo').document();
    await doc.set(map<String>(<String>['foo', 'bar']));
    await firestore
        .runTransaction<DocumentSnapshot>((Transaction transaction) async {
      await transaction.get(doc2);
      return transaction.get(doc);
    });
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map<String>(<String>['foo', 'bar']));
  },
      skip:
          'Needs upstream ef38ef7 (VerifyMutation for documents that were read but not written, analysis_0.md): core/transaction.dart still fails read-without-write transactions with "Every document read in a transaction must also be written."');

  test('testTransactionOptionsZeroMaxAttemptsThrows', () {
    expect(() => TransactionOptions(maxAttempts: 0), throwsArgumentError);
  });
}

typedef TransactionStage = Future<void> Function(
    Transaction transaction, DocumentReference docRef);

enum _FromDocumentType {
  // The operation will be performed on a document that exists.
  existing,
  // The operation will be performed on a document that has never existed.
  nonExistent,
  // The operation will be performed on a document that existed, but was deleted.
  deleted,
}

class TransactionTester {
  TransactionTester._(this._db);

  static Future<void> delete1(
      Transaction transaction, DocumentReference docRef) async {
    transaction.delete(docRef);
  }

  static Future<void> update1(
      Transaction transaction, DocumentReference docRef) async {
    transaction.update(docRef, map(<String>['foo', 'bar1']));
  }

  static Future<void> update2(
      Transaction transaction, DocumentReference docRef) async {
    transaction.update(docRef, map(<String>['foo', 'bar2']));
  }

  static Future<void> set1(
      Transaction transaction, DocumentReference docRef) async {
    transaction.set(docRef, map(<String>['foo', 'bar1']));
  }

  static Future<void> set2(
      Transaction transaction, DocumentReference docRef) async {
    transaction.set(docRef, map(<String>['foo', 'bar2']));
  }

  static Future<void> get(
      Transaction transaction, DocumentReference docRef) async {
    await transaction.get(docRef);
  }

  final Firestore _db;
  late DocumentReference _docRef;
  _FromDocumentType _fromDocumentType = _FromDocumentType.nonExistent;
  List<TransactionStage> _stages = <TransactionStage>[];

  TransactionTester withExistingDoc() {
    _fromDocumentType = _FromDocumentType.existing;
    return this;
  }

  TransactionTester withNonexistentDoc() {
    _fromDocumentType = _FromDocumentType.nonExistent;
    return this;
  }

  TransactionTester withDeletedDoc() {
    _fromDocumentType = _FromDocumentType.deleted;
    return this;
  }

  TransactionTester run(List<TransactionStage> inputStages) {
    _stages = inputStages.toList();
    return this;
  }

  Future<void> expectDoc(Object expected) async {
    try {
      await _prepareDoc();
      await _runTransaction();
      final DocumentSnapshot snapshot = await _docRef.get();
      expect(snapshot.exists, isTrue);
      expect(snapshot.data, expected);
    } catch (e) {
      fail(
          'Expected the sequence (${_listStages(_stages)}) to succeed, but got $e');
    }
    _cleanupTester();
  }

  Future<void> _expectNoDoc() async {
    try {
      await _prepareDoc();
      await _runTransaction();
      final DocumentSnapshot snapshot = await _docRef.get();
      expect(snapshot.exists, isFalse);
    } catch (e) {
      fail(
          'Expected the sequence (${_listStages(_stages)}) to succeed, but got $e');
    }
    _cleanupTester();
  }

  Future<void> _expectError(FirestoreErrorCode expected) async {
    await _prepareDoc();
    try {
      await _runTransaction();
      throw AssertionError(
          'Expected the sequence (${_listStages(_stages)}) to fail with the error $expected');
    } on FirestoreError catch (e) {
      expect(e.code, expected);
      _cleanupTester();
    } catch (e) {
      throw AssertionError(
          'Expected the sequence (${_listStages(_stages)}) to fail with the error $expected');
    }
  }

  Future<void> _prepareDoc() async {
    _docRef = _db.collection('tester-docref').document();
    switch (_fromDocumentType) {
      case _FromDocumentType.existing:
        await _docRef.set(map(<String>['foo', 'bar0']));
        final DocumentSnapshot docSnap = await _docRef.get();
        expect(docSnap.exists, isTrue);
        break;
      case _FromDocumentType.nonExistent:
        // Nothing to do; document does not exist.
        break;
      case _FromDocumentType.deleted:
        await _docRef.set(map(<String>['foo', 'bar0']));
        await _docRef.delete();
        break;
    }
  }

  Future<void> _runTransaction() {
    return _db.runTransaction((Transaction transaction) async {
      for (TransactionStage stage in _stages) {
        await stage(transaction, _docRef);
      }
      return null;
    });
  }

  void _cleanupTester() {
    _stages = <TransactionStage>[];
    // Set the docRef to something else to lose the original reference.
    _docRef = _db.collection('reset').document();
  }

  static String _listStages(List<TransactionStage> stages) {
    final List<String> seqList = <String>[];
    for (TransactionStage stage in stages) {
      if (stage == delete1) {
        seqList.add('delete');
      } else if (stage == update1 || stage == update2) {
        seqList.add('update');
      } else if (stage == set1 || stage == set2) {
        seqList.add('set');
      } else if (stage == get) {
        seqList.add('get');
      } else {
        throw ArgumentError('Stage not recognized');
      }
    }
    return seqList.toString();
  }
}

// ignore: always_specify_types, type_annotate__apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate__apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate__apis
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types, type_annotate__apis
const testDocumentWithData = IntegrationTestUtil.testDocumentWithData;
// ignore: always_specify_types, type_annotate__apis
const toDataMap = IntegrationTestUtil.toDataMap;
// ignore: always_specify_types, type_annotate__apis
const testDocument = IntegrationTestUtil.testDocument;
