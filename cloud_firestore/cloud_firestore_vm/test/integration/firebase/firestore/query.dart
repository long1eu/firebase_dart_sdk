// File created by
// Lung Razvan <long1eu>
// on 08/10/2018
import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/await_helper.dart';
import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

// ignore_for_file: unawaited_futures
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/query';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('testLimitQueries', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, dynamic>>(<dynamic>[
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
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, dynamic>>(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['k', 'a', 'sort', 0]),
      'b',
      map<dynamic>(<dynamic>['k', 'b', 'sort', 1]),
      'c',
      map<dynamic>(<dynamic>['k', 'c', 'sort', 1]),
      'd',
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2])
    ]));

    final Query query =
        collection.limit(2).orderBy('sort', Direction.descending);
    final QuerySnapshot set = await query.get();
    final List<Map<String, Object>> data = querySnapshotToValues(set);

    expect(data, <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2]),
      map<dynamic>(<dynamic>['k', 'c', 'sort', 1])
    ]);
  });

  test('testKeyOrderIsDescendingForDescendingInequality', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, dynamic>>(<dynamic>[
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

    final Query query = collection
        .whereGreaterThan('foo', 21.0)
        .orderBy('foo', Direction.descending);
    final QuerySnapshot result = await query.get();
    expect(querySnapshotToIds(result), <String>['g', 'f', 'c', 'b', 'a']);
  });

  test('testUnaryFilterQueries', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['null', null, 'nan', double.nan]),
      'b',
      map<dynamic>(<dynamic>['null', null, 'nan', 0]),
      'c',
      map<dynamic>(<dynamic>['null', false, 'nan', double.nan])
    ]));

    final QuerySnapshot results = await collection
        .whereEqualTo('null', null)
        .whereEqualTo('nan', double.nan)
        .get();
    expect(results.length, 1);
    final DocumentSnapshot result = results.documents.first;
    // Can't use assertEquals() since NaN != NaN.
    expect(result.get('null'), isNull);
    expect(result.get('nan'), isNaN);
  });

  test('testFilterOnInfinity', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, dynamic>>(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['inf', double.infinity]),
      'b',
      map<dynamic>(<dynamic>['inf', double.negativeInfinity])
    ]));

    final QuerySnapshot results =
        await collection.whereEqualTo('inf', double.infinity).get();

    expect(results.length, 1);
    expect(querySnapshotToValues(results), <dynamic>[
      map<dynamic>(<dynamic>['inf', double.infinity])
    ]);
  });

  test('testWillNotGetMetadataOnlyUpdates', () async {
    final CollectionReference collection = await testCollection();
    await collection.document('a').set(map<dynamic>(<dynamic>['v', 'a']));
    await collection.document('b').set(map<dynamic>(<dynamic>['v', 'b']));

    final List<QuerySnapshot> snapshots = <QuerySnapshot>[];

    Completer<void> completer = Completer<void>();
    final StreamSubscription<QuerySnapshot> listener =
        collection.snapshots.listen((QuerySnapshot snapshot) {
      snapshots.add(snapshot);
      completer.complete();
    }, onError: (dynamic e) {
      assert(false, 'This should never be reached.');
    });

    await completer.future;
    completer = Completer<void>();

    expect(snapshots.length, 1);
    expect(querySnapshotToValues(snapshots[0]), <Map<String, String>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    await collection.document('a').set(map<String>(<String>['v', 'a1']));

    await completer.future;

    expect(snapshots.length, 2);
    expect(querySnapshotToValues(snapshots[1]), <Map<String, String>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);

    await listener.cancel();
  });

  test('testCanListenForTheSameQueryWithDifferentOptions', () async {
    final CollectionReference collection = await testCollection();
    await collection.document('a').set(map<String>(<String>['v', 'a']));
    await collection.document('b').set(map<String>(<String>['v', 'b']));

    final List<QuerySnapshot> snapshots = <QuerySnapshot>[];
    final List<QuerySnapshot> snapshotsFull = <QuerySnapshot>[];

    final AwaitHelper<dynamic> testCounter = AwaitHelper<dynamic>(3);
    final AwaitHelper<dynamic> testCounterFull = AwaitHelper<dynamic>(6);

    final StreamSubscription<QuerySnapshot> listener =
        collection.snapshots.listen(
      (QuerySnapshot snapshot) {
        print('listenerlistenerlistenerlistenerlistener');
        snapshots.add(snapshot);
        testCounter.completeNext();
      },
      onError: (dynamic error) {
        assert(false, 'This should never be reached.');
      },
    );

    final StreamSubscription<QuerySnapshot> listenerFull =
        collection.getSnapshots(MetadataChanges.include).listen(
      (QuerySnapshot snapshot) {
        print('snapshotsFullsnapshotsFullsnapshotsFullsnapshotsFull');
        snapshotsFull.add(snapshot);
        testCounterFull.completeNext();
      },
      onError: (dynamic error) {
        assert(false, 'This should never be reached.');
      },
    );

    await testCounter.next;
    await testCounterFull.following(2);

    expect(snapshots.length, 1);
    expect(querySnapshotToValues(snapshots[0]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(snapshotsFull.length, 2);
    expect(querySnapshotToValues(snapshotsFull[0]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[1]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(snapshotsFull[0].metadata.isFromCache, isTrue);
    expect(snapshotsFull[1].metadata.isFromCache, isFalse);

    collection.document('a').set(map<String>(<String>['v', 'a1']));

    // Only one event without options
    await testCounter.next;
    // Expect two events for the write, once from latency compensation and once
    // from the acknowledgement from the server.
    await testCounterFull.following(2);

    expect(snapshotsFull.length, 4);
    expect(querySnapshotToValues(snapshotsFull[2]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[3]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);

    expect(snapshotsFull[2].metadata.hasPendingWrites, isTrue);
    expect(snapshotsFull[3].metadata.hasPendingWrites, isFalse);

    expect(snapshots.length, 2);
    expect(querySnapshotToValues(snapshots[1]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);

    await collection.document('b').set(map<String>(<String>['v', 'b1']));
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(snapshotsFull.length, 6);
    expect(querySnapshotToValues(snapshotsFull[4]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[5]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);
    expect(snapshotsFull[4].metadata.hasPendingWrites, isTrue);
    expect(snapshotsFull[5].metadata.hasPendingWrites, isFalse);

    expect(snapshots.length, 3);
    expect(querySnapshotToValues(snapshots[2]), <Map<String, dynamic>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);

    await listener.cancel();
    await listenerFull.cancel();
  });

  test('testCanListenForQueryMetadataChanges', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      '1',
      map<dynamic>(<dynamic>['sort', 1.0, 'filter', true, 'key', '1']),
      '2',
      map<dynamic>(<dynamic>['sort', 2.0, 'filter', true, 'key', '2']),
      '3',
      map<dynamic>(<dynamic>['sort', 2.0, 'filter', true, 'key', '3']),
      '4',
      map<dynamic>(<dynamic>['sort', 3.0, 'filter', false, 'key', '4'])
    ]);
    final CollectionReference collection =
        await testCollectionWithDocs(testDocs);
    final List<QuerySnapshot> snapshots = <QuerySnapshot>[];

    final AwaitHelper<dynamic> testCounter = AwaitHelper<dynamic>(3);
    final Query query1 = collection.whereLessThan('key', '4');
    final StreamSubscription<QuerySnapshot> listener1 =
        query1.snapshots.listen((QuerySnapshot snapshot) {
      snapshots.add(snapshot);
      testCounter.completeNext();
    }, onError: (dynamic error) {
      assert(false, 'This should never be reached.');
    });

    await testCounter.next;
    expect(snapshots.length, 1);
    expect(querySnapshotToValues(snapshots[0]),
        <Map<String, dynamic>>[testDocs['1'], testDocs['2'], testDocs['3']]);

    final Query query2 = collection.whereEqualTo('filter', true);
    final StreamSubscription<QuerySnapshot> listener2 = query2
        .getSnapshots(MetadataChanges.include)
        .listen((QuerySnapshot snapshot) {
      snapshots.add(snapshot);
      testCounter.completeNext();
    }, onError: (dynamic error) {
      assert(false, 'This should never be reached.');
    });

    await testCounter.following(2);
    expect(snapshots.length, 3);
    expect(querySnapshotToValues(snapshots[1]),
        <Map<String, dynamic>>[testDocs['1'], testDocs['2'], testDocs['3']]);
    expect(querySnapshotToValues(snapshots[2]),
        <Map<String, dynamic>>[testDocs['1'], testDocs['2'], testDocs['3']]);
    expect(snapshots[1].metadata.isFromCache, isTrue);
    expect(snapshots[2].metadata.isFromCache, isFalse);

    await listener1.cancel();
    await listener2.cancel();
  });

  test('testCanExplicitlySortByDocumentId', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'a',
      map<String>(<String>['key', 'a']),
      'b',
      map<String>(<String>['key', 'b']),
      'c',
      map<String>(<String>['key', 'c'])
    ]);

    final CollectionReference collection =
        await testCollectionWithDocs(testDocs);
    // Ideally this would be descending to validate it's different than
    // the default, but that requires an extra index
    final QuerySnapshot docs =
        await collection.orderByField(FieldPath.documentId()).get();

    expect(querySnapshotToValues(docs),
        <Map<String, dynamic>>[testDocs['a'], testDocs['b'], testDocs['c']]);
  });

  test('testCanQueryByDocumentId', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'aa',
      map<String>(<String>['key', 'aa']),
      'ab',
      map<String>(<String>['key', 'ab']),
      'ba',
      map<String>(<String>['key', 'ba']),
      'bb',
      map<String>(<String>['key', 'bb'])
    ]);

    final CollectionReference collection =
        await testCollectionWithDocs(testDocs);
    QuerySnapshot docs =
        await collection.whereEqualToField(FieldPath.documentId(), 'ab').get();
    expect(querySnapshotToValues(docs), <Map<String, dynamic>>[testDocs['ab']]);

    docs = await collection
        .whereGreaterThanField(FieldPath.documentId(), 'aa')
        .whereLessThanOrEqualToField(FieldPath.documentId(), 'ba')
        .get();
    expect(querySnapshotToValues(docs),
        <Map<String, dynamic>>[testDocs['ab'], testDocs['ba']]);
  });

  test('testCanQueryByDocumentIdUsingRefs', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'aa',
      map<String>(<String>['key', 'aa']),
      'ab',
      map<String>(<String>['key', 'ab']),
      'ba',
      map<String>(<String>['key', 'ba']),
      'bb',
      map<String>(<String>['key', 'bb'])
    ]);
    final CollectionReference collection =
        await testCollectionWithDocs(testDocs);
    QuerySnapshot docs = await collection
        .whereEqualToField(FieldPath.documentId(), collection.document('ab'))
        .get();
    expect(querySnapshotToValues(docs), <Map<String, dynamic>>[testDocs['ab']]);

    docs = await collection
        .whereGreaterThanField(
            FieldPath.documentId(), collection.document('aa'))
        .whereLessThanOrEqualToField(
            FieldPath.documentId(), collection.document('ba'))
        .get();
    expect(querySnapshotToValues(docs),
        <Map<String, dynamic>>[testDocs['ab'], testDocs['ba']]);
  });

  test('testCanQueryWithAndWithoutDocumentKey', () async {
    final CollectionReference collection = await testCollection();
    collection.add(map());
    final Future<QuerySnapshot> query1 = collection
        .orderByField(FieldPath.documentId(), Direction.ascending)
        .get();
    final Future<QuerySnapshot> query2 = collection.get();

    final QuerySnapshot result1 = await query1;
    final QuerySnapshot result2 = await query2;

    expect(querySnapshotToValues(result2), querySnapshotToValues(result1));
  });

  test('watchSurvivesNetworkDisconnect', () async {
    final CollectionReference collectionReference = await testCollection();
    final Firestore firestore = collectionReference.firestore;
    final AwaitHelper<void> receivedDocument = AwaitHelper<void>(1);

    collectionReference
        .getSnapshots(MetadataChanges.include)
        .listen((QuerySnapshot snapshot) {
      if (snapshot.isNotEmpty && !snapshot.metadata.isFromCache) {
        receivedDocument.completeNext();
      }
    });

    await firestore.disableNetwork();
    collectionReference
        .add(map(<dynamic>['foo', FieldValue.serverTimestamp()]));
    await firestore.enableNetwork();

    await receivedDocument.next;
  });

  test('testQueriesFireFromCacheWhenOffline', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['foo', 1])
    ]);
    final CollectionReference collection =
        await testCollectionWithDocs(testDocs);
    final EventAccumulator<QuerySnapshot> accum =
        EventAccumulator<QuerySnapshot>();

    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshots(MetadataChanges.include)
        .listen(accum.onData, onError: accum.onError);

    // initial event
    QuerySnapshot querySnapshot = await accum.wait();

    expect(querySnapshotToValues(querySnapshot),
        <Map<String, dynamic>>[testDocs['a']]);
    expect(querySnapshot.metadata.isFromCache, isFalse);

    // offline event with fromCache=true
    await collection.firestore.client.disableNetwork();
    querySnapshot = await accum.wait();
    expect(querySnapshot.metadata.isFromCache, isTrue);

    // back online event with fromCache=false
    await collection.firestore.client.enableNetwork();
    querySnapshot = await accum.wait();
    expect(querySnapshot.metadata.isFromCache, isFalse);

    await listener.cancel();
  });

  test('testQueriesCanUseArrayContainsFilters', () async {
    final Map<String, Object> docA = map(<dynamic>[
      'array',
      <int>[42]
    ]);
    final Map<String, Object> docB = map(<dynamic>[
      'array',
      <dynamic>['a', 42, 'c']
    ]);
    final Map<String, Object> docC = map(<dynamic>[
      'array',
      <dynamic>[
        41.999,
        '42',
        map<dynamic>(<dynamic>[
          'a',
          <int>[42]
        ])
      ]
    ]);
    final Map<String, Object> docD = map(<dynamic>[
      'array',
      <int>[42],
      'array2',
      <String>['bingo']
    ]);
    final CollectionReference collection = await testCollectionWithDocs(
        map<Map<String, dynamic>>(
            <dynamic>['a', docA, 'b', docB, 'c', docC, 'd', docD]));

    // Search for 'array' to contain 42
    final QuerySnapshot snapshot =
        await collection.whereArrayContains('array', 42).get();
    expect(querySnapshotToValues(snapshot),
        <Map<String, dynamic>>[docA, docB, docD]);

    // NOTE: The backend doesn't currently support null, NaN, objects, or
    // arrays, so there isn't much of anything else interesting to test.
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
