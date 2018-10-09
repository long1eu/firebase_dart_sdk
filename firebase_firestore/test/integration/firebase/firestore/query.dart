// File created by
// Lung Razvan <long1eu>
// on 08/10/2018
import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

// public void (.+?)\(\) \{([\S\s]*?)\}([\S\s]*?)@Test

const map = TestUtil.map;
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
const testFirestore = IntegrationTestUtil.testFirestore;
const writeAllDocs = IntegrationTestUtil.writeAllDocs;
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;

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

  test('testLimitQueries', () async {
    final CollectionReference collection = await testCollectionWithDocs(
        firestore,
        map<Map<String, dynamic>>(<dynamic>[
          'a',
          map<String>(<String>['k', 'a']),
          'b',
          map<String>(<String>['k', 'b']),
          'c',
          map<String>(<String>['k', 'c'])
        ]));

    final Query query = collection.limit(2);
    final QuerySnapshot set = await query.get();
    final List<Map<String, Object>> data = querySnapshotToValues(set);

    expect(data, <Map<String, String>>[
      map<String>(<String>['k', 'a']),
      map<String>(<String>['k', 'b'])
    ]);
  });

  test('testLimitQueriesUsingDescendingSortOrder', () async {
    final CollectionReference collection = await testCollectionWithDocs(
        firestore,
        map<Map<String, dynamic>>(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['k', 'a', 'sort', 0]),
          'b',
          map<dynamic>(<dynamic>['k', 'b', 'sort', 1]),
          'c',
          map<dynamic>(<dynamic>['k', 'c', 'sort', 1]),
          'd',
          map<dynamic>(<dynamic>['k', 'd', 'sort', 2])
        ]));

    final Query query = collection.limit(2).orderBy('sort', Direction.DESCENDING);
    final QuerySnapshot set = await query.get();
    final List<Map<String, Object>> data = querySnapshotToValues(set);

    expect(data, <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2]),
      map<dynamic>(<dynamic>['k', 'c', 'sort', 1])
    ]);
  });

  test('testKeyOrderIsDescendingForDescendingInequality', () async {
    final CollectionReference collection = await testCollectionWithDocs(
        firestore,
        map<Map<String, dynamic>>(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['foo', 42]),
          'b',
          map<dynamic>(<dynamic>['foo', 42.0]),
          'c',
          map<dynamic>(<dynamic>['foo', 42]),
          'd',
          map<dynamic>(<dynamic>['foo', 21]),
          'e',
          map<dynamic>(<dynamic>['foo', 21.0]),
          'f',
          map<dynamic>(<dynamic>['foo', 66]),
          'g',
          map<dynamic>(<dynamic>['foo', 66.0])
        ]));

    final Query query = collection.whereGreaterThan('foo', 21.0).orderBy('foo', Direction.DESCENDING);
    final QuerySnapshot result = await query.get();
    expect(querySnapshotToIds(result), <String>['g', 'f', 'c', 'b', 'a']);
  });

  test('testUnaryFilterQueries', () async {
    final CollectionReference collection = await testCollectionWithDocs(
        firestore,
        map(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['null', null, 'nan', double.nan]),
          'b',
          map<dynamic>(<dynamic>['null', null, 'nan', 0]),
          'c',
          map<dynamic>(<dynamic>['null', false, 'nan', double.nan])
        ]));

    final QuerySnapshot results = await collection.whereEqualTo('null', null).whereEqualTo('nan', double.nan).get();
    expect(results.length, 1);
    final DocumentSnapshot result = results.documents.first;
    // Can't use assertEquals() since NaN != NaN.
    expect(result.get('null'), isNull);
    expect(result.get('nan'), isNaN);
  });

/*
  
  test('testFilterOnInfinity', () async {
    CollectionReference collection =
        testCollectionWithDocs(
            map(
                'a', map<dynamic>(<dynamic>['inf', Double.POSITIVE_INFINITY]),
                'b', map<dynamic>(<dynamic>['inf', Double.NEGATIVE_INFINITY])));
    QuerySnapshot results = waitFor(collection.whereEqualTo('inf', Double.POSITIVE_INFINITY).get());
    assertEquals(1, results.length);
    assertEquals(asList(map<dynamic>(<dynamic>['inf', Double.POSITIVE_INFINITY])), querySnapshotToValues(results));
  });

  
  test('testWillNotGetMetadataOnlyUpdates', () async {
    CollectionReference collection = testCollection();
    waitFor(collection.document('a').set(map<dynamic>(<dynamic>['v', 'a'])));
    waitFor(collection.document('b').set(map<dynamic>(<dynamic>['v', 'b'])));

    List<QuerySnapshot> snapshots = new ArrayList();

    Semaphore testCounter = new Semaphore(0);
    ListenerRegistration listener =
        collection.addSnapshotListener(
            (snapshot, error) {
              assertNull(error);
              snapshots.add(snapshot);
              testCounter.release();
             );

    waitFor(testCounter);
    assertEquals(1, snapshots.length);
    assertEquals(asList(map(<String>['v', 'a']), map(<String>['v', 'b'])), querySnapshotToValues(snapshots.get(0)));
    waitFor(collection.document('a').set(map(<String>['v', 'a1'])));

    waitFor(testCounter);
    assertEquals(2, snapshots.length);
    assertEquals(asList(map(<String>['v', 'a1']), map(<String>['v', 'b'])), querySnapshotToValues(snapshots.get(1)));

    listener.remove();
  }

  });
  test('testCanListenForTheSameQueryWithDifferentOptions', () async {
    CollectionReference collection = testCollection();
    waitFor(collection.document('a').set(map(<String>['v', 'a'])));
    waitFor(collection.document('b').set(map(<String>['v', 'b'])));

    List<QuerySnapshot> snapshots = new ArrayList();
    List<QuerySnapshot> snapshotsFull = new ArrayList();

    Semaphore testCounter = new Semaphore(0);
    Semaphore testCounterFull = new Semaphore(0);
    ListenerRegistration listener =
        collection.addSnapshotListener(
            (snapshot, error) {
              assertNull(error);
              snapshots.add(snapshot);
              testCounter.release();
             /*dd*/);

    ListenerRegistration listenerFull =
        collection.addSnapshotListener(
            MetadataChanges.INCLUDE,
            (snapshot, error) {
              assertNull(error);
              snapshotsFull.add(snapshot);
              testCounterFull.release();
            });

    waitFor(testCounter);
    waitFor(testCounterFull, 2);
    assertEquals(1, snapshots.length);
    assertEquals(asList(map(<String>['v', 'a']), map(<String>['v', 'b'])), querySnapshotToValues(snapshots.get(0)));
    assertEquals(2, snapshotsFull.length);
    assertEquals(asList(map(<String>['v', 'a']), map(<String>['v', 'b'])), querySnapshotToValues(snapshotsFull.get(0)));
    assertEquals(asList(map(<String>['v', 'a']), map(<String>['v', 'b'])), querySnapshotToValues(snapshotsFull.get(1)));
    assertTrue(snapshotsFull.get(0).getMetadata().isFromCache());
    assertFalse(snapshotsFull.get(1).getMetadata().isFromCache());

    waitFor(collection.document('a').set(map(<String>['v', 'a1'])));

    // Expect two events for the write, once from latency compensation and once from the
    // acknowledgement from the server.
    waitFor(testCounterFull, 2);
    // Only one event without options
    waitFor(testCounter);

    assertEquals(4, snapshotsFull.length);
    assertEquals(
        asList(map(<String>['v', 'a1']), map(<String>['v', 'b'])), querySnapshotToValues(snapshotsFull.get(2)));
    assertEquals(
        asList(map(<String>['v', 'a1']), map(<String>['v', 'b'])), querySnapshotToValues(snapshotsFull.get(3)));
    assertTrue(snapshotsFull.get(2).getMetadata().hasPendingWrites());
    assertFalse(snapshotsFull.get(3).getMetadata().hasPendingWrites());

    assertEquals(2, snapshots.length);
    assertEquals(asList(map(<String>['v', 'a1']), map(<String>['v', 'b'])), querySnapshotToValues(snapshots.get(1)));

    waitFor(collection.document('b').set(map(<String>['v', 'b1'])));

    // Expect two events for the write, once from latency compensation and once from the
    // acknowledgement from the server.
    waitFor(testCounterFull, 2);
    // Only one event without options
    waitFor(testCounter);

    assertEquals(6, snapshotsFull.length);
    assertEquals(
        asList(map(<String>['v', 'a1']), map(<String>['v', 'b1'])), querySnapshotToValues(snapshotsFull.get(4)));
    assertEquals(
        asList(map(<String>['v', 'a1']), map(<String>['v', 'b1'])), querySnapshotToValues(snapshotsFull.get(5)));
    assertTrue(snapshotsFull.get(4).getMetadata().hasPendingWrites());
    assertFalse(snapshotsFull.get(5).getMetadata().hasPendingWrites());

    assertEquals(3, snapshots.length);
    assertEquals(asList(map(<String>['v', 'a1']), map(<String>['v', 'b1'])), querySnapshotToValues(snapshots.get(2)));

    listener.remove();
    listenerFull.remove();
  }

  });
  test('testCanListenForQueryMetadataChanges', () async {
    Map<String, Map<String, Object>> testDocs =
        map(
            '1', map(<String>['sort', 1.0, 'filter', true, 'key', '1']),
            '2', map(<String>['sort', 2.0, 'filter', true, 'key', '2']),
            '3', map(<String>['sort', 2.0, 'filter', true, 'key', '3']),
            '4', map(<String>['sort', 3.0, 'filter', false, 'key', '4']));
    CollectionReference collection = testCollectionWithDocs(testDocs);
    List<QuerySnapshot> snapshots = new ArrayList();

    Semaphore testCounter = new Semaphore(0);
    Query query1 = collection.whereLessThan('key', '4');
    ListenerRegistration listener1 =
        query1.addSnapshotListener(
            (snapshot, error) {
              assertNull(error);
              snapshots.add(snapshot);
              testCounter.release();
             /*dd*/);

    waitFor(testCounter);
    assertEquals(1, snapshots.length);
    assertEquals(
        asList(testDocs.get('1'), testDocs.get('2'), testDocs.get('3')),
        querySnapshotToValues(snapshots.get(0)));

    Query query2 = collection.whereEqualTo('filter', true);
    ListenerRegistration listener2 =
        query2.addSnapshotListener(
            MetadataChanges.INCLUDE,
            (snapshot, error) {
              assertNull(error);
              snapshots.add(snapshot);
              testCounter.release();
            });

    waitFor(testCounter, 2);
    assertEquals(3, snapshots.length);
    assertEquals(
        asList(testDocs.get('1'), testDocs.get('2'), testDocs.get('3')),
        querySnapshotToValues(snapshots.get(1)));
    assertEquals(
        asList(testDocs.get('1'), testDocs.get('2'), testDocs.get('3')),
        querySnapshotToValues(snapshots.get(2)));
    assertTrue(snapshots.get(1).getMetadata().isFromCache());
    assertFalse(snapshots.get(2).getMetadata().isFromCache());

    listener1.remove();
    listener2.remove();
  }

  });
  test('testCanExplicitlySortByDocumentId', () async {
    Map<String, Map<String, Object>> testDocs =
        map(
            'a', map(<String>['key', 'a']),
            'b', map(<String>['key', 'b']),
            'c', map(<String>['key', 'c']));
    CollectionReference collection = testCollectionWithDocs(testDocs);
    // Ideally this would be descending to validate it's different than
    // the default, but that requires an extra index
    QuerySnapshot docs = waitFor(collection.orderBy(FieldPath.documentId()).get());
    assertEquals(
        asList(testDocs.get('a'), testDocs.get('b'), testDocs.get('c')),
        querySnapshotToValues(docs));
  });

  
  test('testCanQueryByDocumentId', () async {
    Map<String, Map<String, Object>> testDocs =
        map(
            'aa', map(<String>['key', 'aa']),
            'ab', map(<String>['key', 'ab']),
            'ba', map(<String>['key', 'ba']),
            'bb', map(<String>['key', 'bb']));
    CollectionReference collection = testCollectionWithDocs(testDocs);
    QuerySnapshot docs = waitFor(collection.whereEqualTo(FieldPath.documentId(), 'ab').get());
    assertEquals(singletonList(testDocs.get('ab')), querySnapshotToValues(docs));

    docs =
        waitFor(
            collection
                .whereGreaterThan(FieldPath.documentId(), 'aa')
                .whereLessThanOrEqualTo(FieldPath.documentId(), 'ba')
                .get());
    assertEquals(asList(testDocs.get('ab'), testDocs.get('ba')), querySnapshotToValues(docs));
  });

  
  test('testCanQueryByDocumentIdUsingRefs', () async {
    Map<String, Map<String, Object>> testDocs =
        map(
            'aa', map(<String>['key', 'aa']),
            'ab', map(<String>['key', 'ab']),
            'ba', map(<String>['key', 'ba']),
            'bb', map(<String>['key', 'bb']));
    CollectionReference collection = testCollectionWithDocs(testDocs);
    QuerySnapshot docs =
        waitFor(collection.whereEqualTo(FieldPath.documentId(), collection.document('ab')).get());
    assertEquals(singletonList(testDocs.get('ab')), querySnapshotToValues(docs));

    docs =
        waitFor(
            collection
                .whereGreaterThan(FieldPath.documentId(), collection.document('aa'))
                .whereLessThanOrEqualTo(FieldPath.documentId(), collection.document('ba'))
                .get());
    assertEquals(asList(testDocs.get('ab'), testDocs.get('ba')), querySnapshotToValues(docs));
  });

  
  test('testCanQueryWithAndWithoutDocumentKey', () async {
    CollectionReference collection = testCollection();
    collection.add(map());
    Task<QuerySnapshot> query1 =
        collection.orderBy(FieldPath.documentId(), Direction.ASCENDING).get();
    Task<QuerySnapshot> query2 = collection.get();

    waitFor(query1);
    waitFor(query2);

    assertEquals(
        querySnapshotToValues(query1.getResult()), querySnapshotToValues(query2.getResult()));
  });

  
  test('watchSurvivesNetworkDisconnect', () async {
    CollectionReference collectionReference = testCollection();
    FirebaseFirestore firestore = collectionReference.getFirestore();

    Semaphore receivedDocument = new Semaphore(0);

    collectionReference.addSnapshotListener(
        MetadataChanges.INCLUDE,
        (snapshot, error) {
          if (!snapshot.isEmpty() && !snapshot.getMetadata().isFromCache()) {
            receivedDocument.release();
           /*dd*/
        });

    waitFor(firestore.disableNetwork());
    collectionReference.add(map('foo', FieldValue.serverTimestamp()));
    waitFor(firestore.enableNetwork());

    waitFor(receivedDocument);
  }

  });
  
  test('testQueriesFireFromCacheWhenOffline', () async {
    Map<String, Map<String, Object>> testDocs = map('a', map('foo', 1));
    CollectionReference collection = testCollectionWithDocs(testDocs);
    EventAccumulator<QuerySnapshot> accum = new EventAccumulator();
    ListenerRegistration listener =
        collection.addSnapshotListener(MetadataChanges.INCLUDE, accum.listener());

    // initial event
    QuerySnapshot querySnapshot = accum.await();
    assertEquals(singletonList(testDocs.get('a')), querySnapshotToValues(querySnapshot));
    assertFalse(querySnapshot.getMetadata().isFromCache());

    // offline event with fromCache=true
    waitFor(collection.firestore.getClient().disableNetwork());
    querySnapshot = accum.await();
    assertTrue(querySnapshot.getMetadata().isFromCache());

    // back online event with fromCache=false
    waitFor(collection.firestore.getClient().enableNetwork());
    querySnapshot = accum.await();
    assertFalse(querySnapshot.getMetadata().isFromCache());

    listener.remove();
  });
  
  test('testQueriesCanUseArrayContainsFilters', () async {
    Map<String, Object> docA = map('array', asList(42));
    Map<String, Object> docB = map('array', asList('a', 42, 'c'));
    Map<String, Object> docC = map('array', asList(41.999, '42', map('a', asList(42))));
    Map<String, Object> docD = map('array', asList(42), 'array2', asList('bingo'));
    CollectionReference collection =
        testCollectionWithDocs(map('a', docA, 'b', docB, 'c', docC, 'd', docD));

    // Search for 'array' to contain 42
    QuerySnapshot snapshot = waitFor(collection.whereArrayContains('array', 42).get());
    assertEquals(asList(docA, docB, docD), querySnapshotToValues(snapshot));

    // NOTE: The backend doesn't currently support null, NaN, objects, or arrays, so there isn't
    // much of anything else interesting to test.
  });
  */
}
