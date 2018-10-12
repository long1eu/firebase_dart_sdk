// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  FirebaseFirestore firestore;

  setUp(() async {
    IntegrationTestUtil.currentDatabasePath = 'integration/smoke.db';
    firestore = await testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testCanWriteADocument', () async {
    final Map<String, Object> testData = map(
        <String>['name', 'Patryk', 'message', 'We are actually writing data!']);
    final CollectionReference collection = testCollection(firestore);
    await collection.add(testData);
  });

  test('testCanReadAWrittenDocument', () async {
    final Map<String, Object> testData = map(<String>['foo', 'bar']);
    final CollectionReference collection = testCollection(firestore);

    final DocumentReference newRef = await collection.add(testData);
    final DocumentSnapshot result = await newRef.get();
    expect(result.data, testData);
  });

  test('testObservesExistingDocument', () async {
    final Map<String, Object> testData = map(<String>['foo', 'bar']);
    final CollectionReference collection = testCollection(firestore);
    final DocumentReference writerRef = collection.document();
    final DocumentReference readerRef = collection.document(writerRef.id);
    await writerRef.set(testData);
    final EventAccumulator<DocumentSnapshot> accumulator =
        EventAccumulator<DocumentSnapshot>();
    final StreamSubscription<DocumentSnapshot> listener = readerRef
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    final DocumentSnapshot doc = await accumulator.wait();
    expect(doc.data, testData);
    listener.cancel();
  });

  test('testObservesNewDocument', () async {
    final CollectionReference collection = testCollection(firestore);
    final DocumentReference writerRef = collection.document();
    final DocumentReference readerRef = collection.document(writerRef.id);
    final EventAccumulator<DocumentSnapshot> accumulator =
        EventAccumulator<DocumentSnapshot>();
    final StreamSubscription<DocumentSnapshot> listener = readerRef
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    DocumentSnapshot doc = await accumulator.wait();
    expect(doc.exists, isFalse);
    final Map<String, Object> testData = map(<String>['foo', 'bar']);
    await writerRef.set(testData);
    doc = await accumulator.wait();
    expect(doc.data, testData);
    expect(doc.metadata.hasPendingWrites, isTrue);
    doc = await accumulator.wait();
    expect(doc.data, testData);
    expect(doc.metadata.hasPendingWrites, isFalse);
    listener.cancel();
  });

  test('testWillFireValueEventsForEmptyCollections', () async {
    final CollectionReference collection =
        testCollection(firestore, 'empty-collection');
    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);
    final QuerySnapshot querySnap = await accumulator.wait();
    expect(querySnap.length, 0);
    expect(querySnap, isEmpty);
    listener.cancel();
  });

  test('testGetCollectionQuery', () async {
    final Map<String, Map<String, Object>> testData = map(<dynamic>[
      '1',
      map<dynamic>(<dynamic>['name', 'Patryk', 'message', 'Real data, yo!']),
      '2',
      map<dynamic>(<dynamic>['name', 'Gil', 'message', 'Yep!']),
      '3',
      map<dynamic>(<dynamic>['name', 'Jonny', 'message', 'Back to work!'])
    ]);
    final CollectionReference collection = testCollection(firestore);
    final List<Future<void>> tasks = <Future<void>>[];
    for (MapEntry<String, Map<String, Object>> entry in testData.entries) {
      tasks.add(collection.document(entry.key).set(entry.value));
    }
    await Future.wait(tasks);

    final QuerySnapshot set = await collection.get();
    final List<DocumentSnapshot> documents = set.documents;
    expect(set, isNotEmpty);
    expect(documents, hasLength(3));
    expect(documents[0].data, testData['1']);
    expect(documents[1].data, testData['2']);
    expect(documents[2].data, testData['3']);
  });

  test(
    'testGetCollectionQueryByFieldAndOrdering',
    () async {
      final Map<String, Map<String, Object>> testData = map(<dynamic>[
        '1',
        map<dynamic>(<dynamic>['sort', 1.0, 'filter', true, 'key', '1']),
        '2',
        map<dynamic>(<dynamic>['sort', 2.0, 'filter', true, 'key', '2']),
        '3',
        map<dynamic>(<dynamic>['sort', 2.0, 'filter', true, 'key', '3']),
        '4',
        map<dynamic>(<dynamic>['sort', 3.0, 'filter', false, 'key', '4'])
      ]);
      final CollectionReference collection = testCollection(firestore);
      final List<Future<void>> tasks = <Future<void>>[];
      for (MapEntry<String, Map<String, Object>> entry in testData.entries) {
        tasks.add(collection.document(entry.key).set(entry.value));
      }
      await Future.wait(tasks);
      final Query query = collection
          .whereEqualTo('filter', true)
          .orderBy('sort', Direction.DESCENDING);

      final QuerySnapshot set = await query.get();
      final List<DocumentSnapshot> documents = set.documents;
      expect(documents, hasLength(3));
      expect(documents[0].data, testData['2']);
      expect(documents[1].data, testData['3']);
      expect(documents[2].data, testData['1']);
    },
    skip: 'This broken because it requires a composite index on filter,sort.',
  );
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testCollection = IntegrationTestUtil.testCollection;
