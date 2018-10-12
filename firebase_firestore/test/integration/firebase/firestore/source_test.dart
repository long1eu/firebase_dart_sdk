// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  FirebaseFirestore firestore;

  setUp(() async {
    IntegrationTestUtil.currentDatabasePath = 'integration/query.db';
    firestore = await testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('getDocumentWhileOnlineWithDefaultGetOptions', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    final DocumentSnapshot doc = await docRef.get();

    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isFalse);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);
  });

  test('getCollectionWhileOnlineWithDefaultGetOptions', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    final QuerySnapshot qrySnap = await colRef.get();
    expect(qrySnap.metadata.isFromCache, isFalse);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
    expect(qrySnap.documentChanges.length, 3);
    expect(toDataMap(qrySnap), initialDocs);
  });

  test('getDocumentWhileOfflineWithDefaultGetOptions', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    await docRef.get();
    await docRef.firestore.disableNetwork();

    final DocumentSnapshot doc = await docRef.get();

    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);
  });

  test('getCollectionWhileOfflineWithDefaultGetOptions', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    await colRef.get();
    await colRef.firestore.disableNetwork();

    // Since we're offline, the returned promises won't complete
    colRef
        .document('doc2')
        .set(map(<String>['key2b', 'value2b']), SetOptions.mergeAllFields);
    colRef.document('doc3').set(map(<String>['key3b', 'value3b']));
    colRef.document('doc4').set(map(<String>['key4', 'value4']));

    final QuerySnapshot qrySnap = await colRef.get();
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isTrue);
    expect(qrySnap.documentChanges.length, 4);
    expect(
        toDataMap(qrySnap),
        map<dynamic>(<dynamic>[
          'doc1',
          map<String>(<String>['key1', 'value1']),
          'doc2',
          map<String>(<String>['key2', 'value2', 'key2b', 'value2b']),
          'doc3',
          map<String>(<String>['key3b', 'value3b']),
          'doc4',
          map<String>(<String>['key4', 'value4'])
        ]));
  });

  test('getDocumentWhileOnlineWithSourceEqualToCache', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    await docRef.get();

    final DocumentSnapshot doc = await docRef.get(Source.CACHE);

    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);
  });

  test('getCollectionWhileOnlineWithSourceEqualToCache', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    await colRef.get();

    final QuerySnapshot qrySnap = await colRef.get(Source.CACHE);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
    expect(qrySnap.documentChanges.length, 3);
    expect(toDataMap(qrySnap), initialDocs);
  });

  test('getDocumentWhileOfflineWithSourceEqualToCache', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    await docRef.get();
    await docRef.firestore.disableNetwork();

    final DocumentSnapshot doc = await docRef.get(Source.CACHE);
    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);
  });

  test('getCollectionWhileOfflineWithSourceEqualToCache', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    await colRef.get();
    await colRef.firestore.disableNetwork();

    // Since we're offline, the returned promises won't complete
    colRef
        .document('doc2')
        .set(map(<String>['key2b', 'value2b']), SetOptions.mergeAllFields);
    colRef.document('doc3').set(map(<String>['key3b', 'value3b']));
    colRef.document('doc4').set(map(<String>['key4', 'value4']));

    final QuerySnapshot qrySnap = await colRef.get(Source.CACHE);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isTrue);
    expect(qrySnap.documentChanges.length, 4);
    expect(
        toDataMap(qrySnap),
        map<dynamic>(<dynamic>[
          'doc1',
          map<String>(<String>['key1', 'value1']),
          'doc2',
          map<String>(<String>['key2', 'value2', 'key2b', 'value2b']),
          'doc3',
          map<String>(<String>['key3b', 'value3b']),
          'doc4',
          map<String>(<String>['key4', 'value4'])
        ]));
  });

  test('getDocumentWhileOnlineWithSourceEqualToServer', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    final DocumentSnapshot doc = await docRef.get(Source.SERVER);
    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isFalse);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);
  });

  test('getCollectionWhileOnlineWithSourceEqualToServer', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);

    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    final QuerySnapshot qrySnap = await colRef.get(Source.SERVER);
    expect(qrySnap.metadata.isFromCache, isFalse);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
    expect(qrySnap.documentChanges.length, 3);
    expect(toDataMap(qrySnap), initialDocs);
  });

  test('getDocumentWhileOfflineWithSourceEqualToServer', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    await docRef.get();
    await docRef.firestore.disableNetwork();

    expect(() => docRef.get(Source.SERVER), throwsA(anything));
  });

  test('getCollectionWhileOfflineWithSourceEqualToServer', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    await colRef.get();
    await colRef.firestore.disableNetwork();

    expect(() => colRef.get(Source.SERVER), throwsA(anything));
  });

  test('getDocumentWhileOfflineWithDifferentGetOptions', () async {
    final Map<String, Object> initialData = map(<String>['key', 'value']);
    final DocumentReference docRef =
        await testDocumentWithData(firestore, initialData);

    await docRef.get();
    await docRef.firestore.disableNetwork();

    // Create an initial listener for this query (to attempt to disrupt the gets
    // below) and wait for// the listener to deliver its initial snapshot before
    // continuing.
    final Completer<void> source = Completer<void>();
    docRef.snapshots.listen(
      (DocumentSnapshot docSnap) {
        source.complete(null);
      },
      onError: (dynamic error) {
        source.completeError(error);
      },
    );
    await source.future;

    DocumentSnapshot doc = await docRef.get(Source.CACHE);
    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);

    doc = await docRef.get();
    expect(doc.exists, isTrue);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
    expect(doc.data, initialData);

    expect(() => docRef.get(Source.SERVER), throwsA(anything));
  });

  test('getCollectionWhileOfflineWithDifferentGetOptions', () async {
    final Map<String, Map<String, Object>> initialDocs = map(<dynamic>[
      'doc1',
      map<String>(<String>['key1', 'value1']),
      'doc2',
      map<String>(<String>['key2', 'value2']),
      'doc3',
      map<String>(<String>['key3', 'value3'])
    ]);
    final CollectionReference colRef =
        await testCollectionWithDocs(firestore, initialDocs);

    await colRef.get();
    await colRef.firestore.disableNetwork();

    // since we're offline, the returned promises won't complete
    colRef
        .document('doc2')
        .set(map(<String>['key2b', 'value2b']), SetOptions.mergeAllFields);
    colRef.document('doc3').set(map(<String>['key3b', 'value3b']));
    colRef.document('doc4').set(map(<String>['key4', 'value4']));

    // Create an initial listener for this query (to attempt to disrupt the gets below) and wait for
    // the listener to deliver its initial snapshot before continuing.
    final Completer<void> source = Completer<void>();
    colRef.snapshots.listen(
      (QuerySnapshot qrySnap) {
        source.complete(null);
      },
      onError: (dynamic error) {
        source.completeError(error);
      },
    );
    await source.future;

    QuerySnapshot qrySnap = await colRef.get(Source.CACHE);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isTrue);
    expect(qrySnap.documentChanges.length, 4);
    expect(
        toDataMap(qrySnap),
        map<dynamic>(<dynamic>[
          'doc1',
          map<String>(<String>['key1', 'value1']),
          'doc2',
          map<String>(<String>['key2', 'value2', 'key2b', 'value2b']),
          'doc3',
          map<String>(<String>['key3b', 'value3b']),
          'doc4',
          map<String>(<String>['key4', 'value4'])
        ]));

    qrySnap = await colRef.get();
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isTrue);
    expect(qrySnap.documentChanges.length, 4);
    expect(
        toDataMap(qrySnap),
        map<dynamic>(<dynamic>[
          'doc1',
          map<String>(<String>['key1', 'value1']),
          'doc2',
          map<String>(<String>['key2', 'value2', 'key2b', 'value2b']),
          'doc3',
          map<String>(<String>['key3b', 'value3b']),
          'doc4',
          map<String>(<String>['key4', 'value4'])
        ]));

    expect(() => colRef.get(Source.SERVER), throwsA(anything));
  });

  test('getNonExistingDocWhileOnlineWithDefaultGetOptions', () async {
    final DocumentReference docRef = testDocument(firestore);

    final DocumentSnapshot doc = await docRef.get();
    expect(doc.exists, isFalse);
    expect(doc.metadata.isFromCache, isFalse);
    expect(doc.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingCollectionWhileOnlineWithDefaultGetOptions', () async {
    final CollectionReference colRef = testCollection(firestore);

    final QuerySnapshot qrySnap = await colRef.get();
    expect(qrySnap, isEmpty);
    expect(qrySnap.documentChanges.length, 0);
    expect(qrySnap.metadata.isFromCache, isFalse);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingDocWhileOfflineWithDefaultGetOptions', () async {
    final DocumentReference docRef = testDocument(firestore);

    await docRef.firestore.disableNetwork();
    expect(() => docRef.get(), throwsA(anything));
  });

  // TODO(b/112267729)
  test(
    'getDeletedDocWhileOfflineWithDefaultGetOptions',
    () async {
      final DocumentReference docRef = testDocument(firestore);
      await docRef.delete();

      await docRef.firestore.disableNetwork();

      final DocumentSnapshot doc = await docRef.get();
      expect(doc.exists, isFalse);
      expect(doc.data, isNull);
      expect(doc.metadata.isFromCache, isTrue);
      expect(doc.metadata.hasPendingWrites, isFalse);
    },
    skip: 'We should raise a fromCache=true event with a nonexistent snapshot,'
        ' but because the default source goes through a normal listener, we do'
        ' not.',
  );

  test('getNonExistingCollectionWhileOfflineWithDefaultGetOptions', () async {
    final CollectionReference colRef = testCollection(firestore);

    await colRef.firestore.disableNetwork();

    final QuerySnapshot qrySnap = await colRef.get();
    expect(qrySnap, isEmpty);
    expect(qrySnap.documentChanges.length, 0);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingDocWhileOnlineWithSourceEqualToCache', () async {
    final DocumentReference docRef = testDocument(firestore);

    // Attempt to get doc. This will fail since there's nothing in cache.
    expect(() => docRef.get(Source.CACHE), throwsA(anything));
  });

  test('getNonExistingCollectionWhileOnlineWithSourceEqualToCache', () async {
    final CollectionReference colRef = testCollection(firestore);

    final QuerySnapshot qrySnap = await colRef.get(Source.CACHE);
    expect(qrySnap, isEmpty);
    expect(qrySnap.documentChanges.length, 0);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingDocWhileOfflineWithSourceEqualToCache', () async {
    final DocumentReference docRef = testDocument(firestore);

    await docRef.firestore.disableNetwork();

    // Attempt to get doc. This will fail since there's nothing in cache.
    expect(() => docRef.get(Source.CACHE), throwsA(anything));
  });

  test('getDeletedDocWhileOfflineWithSourceEqualToCache', () async {
    final DocumentReference docRef = testDocument(firestore);
    await docRef.delete();

    await docRef.firestore.disableNetwork();

    final DocumentSnapshot doc = await docRef.get(Source.CACHE);
    expect(doc.exists, isFalse);
    expect(doc.data, isNull);
    expect(doc.metadata.isFromCache, isTrue);
    expect(doc.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingCollectionWhileOfflineWithSourceEqualToCache', () async {
    final CollectionReference colRef = testCollection(firestore);

    await colRef.firestore.disableNetwork();

    final QuerySnapshot qrySnap = await colRef.get(Source.CACHE);
    expect(qrySnap, isEmpty);
    expect(qrySnap.documentChanges.length, 0);
    expect(qrySnap.metadata.isFromCache, isTrue);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingDocWhileOnlineWithSourceEqualToServer', () async {
    final DocumentReference docRef = testDocument(firestore);

    final DocumentSnapshot doc = await docRef.get(Source.SERVER);
    expect(doc.exists, isFalse);
    expect(doc.metadata.isFromCache, isFalse);
    expect(doc.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingCollectionWhileOnlineWithSourceEqualToServer', () async {
    final CollectionReference colRef = testCollection(firestore);

    final QuerySnapshot qrySnap = await colRef.get(Source.SERVER);
    expect(qrySnap, isEmpty);
    expect(qrySnap.documentChanges.length, 0);
    expect(qrySnap.metadata.isFromCache, isFalse);
    expect(qrySnap.metadata.hasPendingWrites, isFalse);
  });

  test('getNonExistingDocWhileOfflineWithSourceEqualToServer', () async {
    final DocumentReference docRef = testDocument(firestore);

    await docRef.firestore.disableNetwork();

    expect(() => docRef.get(Source.SERVER), throwsA(anything));
  });

  test('getNonExistingCollectionWhileOfflineWithSourceEqualToServer', () async {
    final CollectionReference colRef = testCollection(firestore);

    await colRef.firestore.disableNetwork();
    expect(() => colRef.get(Source.SERVER), throwsA(anything));
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testCollection = IntegrationTestUtil.testCollection;
// ignore: always_specify_types
const testDocumentWithData = IntegrationTestUtil.testDocumentWithData;
// ignore: always_specify_types
const toDataMap = IntegrationTestUtil.toDataMap;
// ignore: always_specify_types
const testDocument = IntegrationTestUtil.testDocument;
