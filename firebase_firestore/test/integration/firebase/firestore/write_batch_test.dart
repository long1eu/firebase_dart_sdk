// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  FirebaseFirestore firestore;

  setUp(() async {
    IntegrationTestUtil.currentDatabasePath = 'integration/write_batch.db';
    firestore = await testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testSupportEmptyBatches', () async {
    await firestore.batch().commit();
  });

  test('testSetDocuments', () async {
    final DocumentReference doc = testDocument(firestore);
    await firestore
        .batch()
        .set(doc, map<String>(<String>['foo', 'bar']))
        .commit();
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map<String>(<String>['foo', 'bar']));
  });

  test('testSetDocumentsWithMerge', () async {
    final DocumentReference doc = testDocument(firestore);
    await firestore
        .batch()
        .set(
            doc,
            map(<dynamic>[
              'a',
              'b',
              'nested',
              map<String>(<String>['a', 'remove'])
            ]),
            SetOptions.mergeAllFields)
        .commit();
    await firestore
        .batch()
        .set(
            doc,
            map(<dynamic>[
              'c',
              'd',
              'ignore',
              true,
              'nested',
              map<String>(<String>['c', 'd'])
            ]),
            SetOptions.mergeFields(<String>['c', 'nested']))
        .commit();
    await firestore
        .batch()
        .set(
            doc,
            map(<dynamic>[
              'e',
              'f',
              'nested',
              map<dynamic>(<dynamic>['e', 'f', 'ignore', true])
            ]),
            SetOptions.mergeFieldPaths(<FieldPath>[
              FieldPath.of(<String>['e']),
              FieldPath.of(<String>['nested', 'e'])
            ]))
        .commit();
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(
        snapshot.data,
        map<dynamic>(<dynamic>[
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
          'nested',
          map<String>(<String>['c', 'd', 'e', 'f'])
        ]));
  });

  test('testUpdateDocuments', () async {
    final DocumentReference doc = testDocument(firestore);
    await doc.set(map(<String>['foo', 'bar']));
    await firestore.batch().update(doc, map(<dynamic>['baz', 42])).commit();
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map<dynamic>(<dynamic>['foo', 'bar', 'baz', 42]));
  });

  test('testUpdateFieldsWithDots', () async {
    final DocumentReference doc = testDocument(firestore);
    await doc.set(map(<String>['a.b', 'old', 'c.d', 'old']));

    await firestore.batch().updateFromList(doc, <dynamic>[
      FieldPath.of(<String>['a.b']),
      'new'
    ]).commit();
    await firestore.batch().updateFromList(doc, <dynamic>[
      FieldPath.of(<String>['c.d']),
      'new'
    ]).commit();

    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, map<String>(<String>['a.b', 'new', 'c.d', 'new']));
  });

  test('testUpdateNestedFields', () async {
    final DocumentReference doc = testDocument(firestore);
    await doc.set(map(<dynamic>[
      'a',
      map<String>(<String>['b', 'old']),
      'c',
      map<String>(<String>['d', 'old'])
    ]));

    await firestore
        .batch()
        .updateFromList(doc, <String>['a.b', 'new']).commit();
    await firestore.batch().update(doc, map(<String>['c.d', 'new'])).commit();

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

  test('testDeleteDocuments', () async {
    final DocumentReference doc = testDocument(firestore);
    await doc.set(map(<String>['foo', 'bar']));
    DocumentSnapshot snapshot = await doc.get();

    expect(snapshot.exists, isTrue);
    await firestore.batch().delete(doc).commit();
    snapshot = await doc.get();
    expect(snapshot.exists, isFalse);
  });

  test('testBatchesCommitAtomicallyRaisingCorrectEvents', () async {
    final CollectionReference collection = testCollection(firestore);
    final DocumentReference docA = collection.document('a');
    final DocumentReference docB = collection.document('b');
    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    collection
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    final QuerySnapshot initialSnap = await accumulator.wait();
    expect(initialSnap.length, 0);

    // Atomically write two documents.
    await firestore
        .batch()
        .set(docA, map(<dynamic>['a', 1]))
        .set(docB, map(<dynamic>['b', 2]))
        .commit();

    final QuerySnapshot localSnap = await accumulator.wait();
    expect(localSnap.metadata.hasPendingWrites, isTrue);
    expect(querySnapshotToValues(localSnap), <dynamic>[
      map<dynamic>(<dynamic>['a', 1]),
      map<dynamic>(<dynamic>['b', 2])
    ]);

    final QuerySnapshot serverSnap = await accumulator.wait();
    expect(serverSnap.metadata.hasPendingWrites, isFalse);
    expect(querySnapshotToValues(serverSnap), <dynamic>[
      map<dynamic>(<dynamic>['a', 1]),
      map<dynamic>(<dynamic>['b', 2])
    ]);
  });

  test('testBatchesFailAtomicallyRaisingCorrectEvents', () async {
    final CollectionReference collection = testCollection(firestore);
    final DocumentReference docA = collection.document('a');
    final DocumentReference docB = collection.document('b');
    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    collection
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);

    final QuerySnapshot initialSnap = await accumulator.wait();
    expect(initialSnap.length, 0);

    dynamic err;
    try {
      // Atomically write 1 document and update a nonexistent document.
      await firestore
          .batch()
          .set(docA, map(<dynamic>['a', 1]))
          .update(docB, map(<dynamic>['b', 2]))
          .commit();
    } catch (e) {
      err = e;
    }

    // Local event with the set document.
    final QuerySnapshot localSnap = await accumulator.wait();
    expect(localSnap.metadata.hasPendingWrites, isTrue);
    expect(querySnapshotToValues(localSnap), <Map<String, int>>[
      map<int>(<dynamic>['a', 1])
    ]);

    // Server event with the set reverted
    final QuerySnapshot serverSnap = await accumulator.wait();
    expect(serverSnap.metadata.hasPendingWrites, isFalse);
    expect(serverSnap.length, 0);

    expect(err, isNotNull);
    expect(err, const TypeMatcher<FirebaseFirestoreError>());
    expect((err as FirebaseFirestoreError).code,
        FirebaseFirestoreErrorCode.notFound);
  });

  test('testWriteTheSameServerTimestampAcrossWrites', () async {
    final CollectionReference collection = testCollection(firestore);
    final DocumentReference docA = collection.document('a');
    final DocumentReference docB = collection.document('b');
    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    collection
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    final QuerySnapshot initialSnap = await accumulator.wait();
    expect(initialSnap.length, 0);

    // Atomically write two documents with server timestamps.
    await firestore
        .batch()
        .set(docA, map(<dynamic>['when', FieldValue.serverTimestamp()]))
        .set(docB, map(<dynamic>['when', FieldValue.serverTimestamp()]))
        .commit();

    final QuerySnapshot localSnap = await accumulator.wait();
    expect(localSnap.metadata.hasPendingWrites, isTrue);
    expect(querySnapshotToValues(localSnap), <dynamic>[
      map<String>(<String>['when', null]),
      map<String>(<String>['when', null])
    ]);

    final QuerySnapshot serverSnap = await accumulator.wait();
    expect(serverSnap.metadata.hasPendingWrites, isFalse);
    expect(serverSnap.length, 2);
    final Timestamp when = serverSnap.documents[0].getTimestamp('when');
    expect(when, isNotNull);
    expect(querySnapshotToValues(serverSnap), <dynamic>[
      map<dynamic>(<dynamic>['when', when]),
      map<dynamic>(<dynamic>['when', when])
    ]);
  });

  test('testCanWriteTheSameDocumentMultipleTimes', () async {
    final DocumentReference doc = testDocument(firestore);
    final EventAccumulator<DocumentSnapshot> accumulator =
        EventAccumulator<DocumentSnapshot>();
    doc
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    final DocumentSnapshot initialSnap = await accumulator.wait();
    expect(initialSnap.exists, isFalse);

    await firestore
        .batch()
        .delete(doc)
        .set(doc, map(<dynamic>['a', 1, 'b', 1, 'when', 'when']))
        .update(
            doc, map(<dynamic>['b', 2, 'when', FieldValue.serverTimestamp()]))
        .commit();

    final DocumentSnapshot localSnap = await accumulator.wait();
    expect(localSnap.metadata.hasPendingWrites, isTrue);
    expect(
        localSnap.data, map<dynamic>(<dynamic>['a', 1, 'b', 2, 'when', null]));

    final DocumentSnapshot serverSnap = await accumulator.wait();
    expect(serverSnap.metadata.hasPendingWrites, isFalse);
    final Timestamp when = serverSnap.getTimestamp('when');
    expect(when, isNotNull);
    expect(
        serverSnap.data, map<dynamic>(<dynamic>['a', 1, 'b', 2, 'when', when]));
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const writeAllDocs = IntegrationTestUtil.writeAllDocs;
// ignore: always_specify_types
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;
// ignore: always_specify_types
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types
const testDocument = IntegrationTestUtil.testDocument;
