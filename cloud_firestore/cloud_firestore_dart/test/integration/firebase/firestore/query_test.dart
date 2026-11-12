// File created by
// Lung Razvan <long1eu>
// on 08/10/2018
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/write_batch.dart';
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
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
      'a',
      map<String>(<String>['k', 'a']),
      'b',
      map<String>(<String>['k', 'b']),
      'c',
      map<String>(<String>['k', 'c'])
    ]));

    final Query query = collection.limit(2);
    final QuerySnapshot set = await query.get();
    final List<Map<String, Object?>> data = querySnapshotToValues(set);

    expect(data, <Map<String, String>>[
      map<String>(<String>['k', 'a']),
      map<String>(<String>['k', 'b'])
    ]);
  });

  test('testLimitQueriesUsingDescendingSortOrder', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
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
    final List<Map<String, Object?>> data = querySnapshotToValues(set);

    expect(data, <Map<String, Object?>>[
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2]),
      map<dynamic>(<dynamic>['k', 'c', 'sort', 1])
    ]);
  });

  test('testKeyOrderIsDescendingForDescendingInequality', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
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
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
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
    expect(querySnapshotToValues(snapshots[0]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(snapshotsFull.length, 2);
    expect(querySnapshotToValues(snapshotsFull[0]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[1]), <Map<String, Object?>>[
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
    expect(querySnapshotToValues(snapshotsFull[2]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[3]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);

    expect(snapshotsFull[2].metadata.hasPendingWrites, isTrue);
    expect(snapshotsFull[3].metadata.hasPendingWrites, isFalse);

    expect(snapshots.length, 2);
    expect(querySnapshotToValues(snapshots[1]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b'])
    ]);

    await collection.document('b').set(map<String>(<String>['v', 'b1']));
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(snapshotsFull.length, 6);
    expect(querySnapshotToValues(snapshotsFull[4]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);
    expect(querySnapshotToValues(snapshotsFull[5]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);
    expect(snapshotsFull[4].metadata.hasPendingWrites, isTrue);
    expect(snapshotsFull[5].metadata.hasPendingWrites, isFalse);

    expect(snapshots.length, 3);
    expect(querySnapshotToValues(snapshots[2]), <Map<String, Object?>>[
      map<String>(<String>['v', 'a1']),
      map<String>(<String>['v', 'b1'])
    ]);

    await listener.cancel();
    await listenerFull.cancel();
  });

  test('testCanListenForQueryMetadataChanges', () async {
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
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
        <Map<String, Object?>>[testDocs['1']!, testDocs['2']!, testDocs['3']!]);

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
        <Map<String, Object?>>[testDocs['1']!, testDocs['2']!, testDocs['3']!]);
    expect(querySnapshotToValues(snapshots[2]),
        <Map<String, Object?>>[testDocs['1']!, testDocs['2']!, testDocs['3']!]);
    expect(snapshots[1].metadata.isFromCache, isTrue);
    expect(snapshots[2].metadata.isFromCache, isFalse);

    await listener1.cancel();
    await listener2.cancel();
  });

  test('testCanExplicitlySortByDocumentId', () async {
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
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
        <Map<String, Object?>>[testDocs['a']!, testDocs['b']!, testDocs['c']!]);
  });

  test('testCanQueryByDocumentId', () async {
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
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
    expect(
        querySnapshotToValues(docs), <Map<String, Object?>>[testDocs['ab']!]);

    docs = await collection
        .whereGreaterThanField(FieldPath.documentId(), 'aa')
        .whereLessThanOrEqualToField(FieldPath.documentId(), 'ba')
        .get();
    expect(querySnapshotToValues(docs),
        <Map<String, Object?>>[testDocs['ab']!, testDocs['ba']!]);
  });

  test('testCanQueryByDocumentIdUsingRefs', () async {
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
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
    expect(
        querySnapshotToValues(docs), <Map<String, Object?>>[testDocs['ab']!]);

    docs = await collection
        .whereGreaterThanField(
            FieldPath.documentId(), collection.document('aa'))
        .whereLessThanOrEqualToField(
            FieldPath.documentId(), collection.document('ba'))
        .get();
    expect(querySnapshotToValues(docs),
        <Map<String, Object?>>[testDocs['ab']!, testDocs['ba']!]);
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
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
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
        <Map<String, Object?>>[testDocs['a']!]);
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

  test('testQueriesCanRaiseInitialSnapshotFromCachedEmptyResults', () async {
    final CollectionReference collectionReference = await testCollection();

    // Populate the cache with empty query result.
    final QuerySnapshot querySnapshotA = await collectionReference.get();
    expect(querySnapshotA.metadata.isFromCache, isFalse);
    expect(querySnapshotToValues(querySnapshotA), <Map<String, Object?>>[]);

    // Add a snapshot listener whose first event should be raised from cache.
    final EventAccumulator<QuerySnapshot> accum =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collectionReference
        .getSnapshots(MetadataChanges.include)
        .listen(accum.onData, onError: accum.onError);
    final QuerySnapshot querySnapshotB = await accum.wait();
    expect(querySnapshotB.metadata.isFromCache, isTrue);
    expect(querySnapshotToValues(querySnapshotB), <Map<String, Object?>>[]);

    await listener.cancel();
  });

  test('testQueriesCanRaiseInitialSnapshotFromEmptyDueToDeleteCachedResults',
      () async {
    final Map<String, Map<String, Object?>> testDocs = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['foo', 1])
    ]);
    final CollectionReference collectionReference =
        await testCollectionWithDocs(testDocs);
    // Populate the cache with single document.
    final QuerySnapshot querySnapshotA = await collectionReference.get();
    expect(querySnapshotA.metadata.isFromCache, isFalse);
    expect(querySnapshotToValues(querySnapshotA),
        <Map<String, Object?>>[testDocs['a']!]);

    // Delete the document, make cached result empty.
    final DocumentReference docRef = collectionReference.document('a');
    await docRef.delete();

    // Add a snapshot listener whose first event should be raised from cache.
    final EventAccumulator<QuerySnapshot> accum =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collectionReference
        .getSnapshots(MetadataChanges.include)
        .listen(accum.onData, onError: accum.onError);
    final QuerySnapshot querySnapshotB = await accum.wait();
    expect(querySnapshotB.metadata.isFromCache, isTrue);
    expect(querySnapshotToValues(querySnapshotB), <Map<String, Object?>>[]);

    await listener.cancel();
  });

  test('testQueriesCanUseArrayContainsFilters',
      skip: IntegrationTestUtil.skipOnEnterprise(
          'array-contains matches null and NaN'), () async {
    final Map<String, Object?> docA = map(<dynamic>[
      'array',
      <int>[42]
    ]);
    final Map<String, Object?> docB = map(<dynamic>[
      'array',
      <dynamic>['a', 42, 'c']
    ]);
    final Map<String, Object?> docC = map(<dynamic>[
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
    final Map<String, Object?> docD = map(<dynamic>[
      'array',
      <int>[42],
      'array2',
      <String>['bingo']
    ]);
    final Map<String, Object?> docE = map(<dynamic>[
      'array',
      <Object?>[null]
    ]);
    final Map<String, Object?> docF = map(<dynamic>[
      'array',
      <double>[double.nan]
    ]);
    final CollectionReference collection = await testCollectionWithDocs(
        map<Map<String, Object?>>(<dynamic>[
      'a',
      docA,
      'b',
      docB,
      'c',
      docC,
      'd',
      docD,
      'e',
      docE,
      'f',
      docF
    ]));

    // Search for 'array' to contain 42
    QuerySnapshot snapshot =
        await collection.whereArrayContains('array', 42).get();
    expect(querySnapshotToValues(snapshot),
        <Map<String, Object?>>[docA, docB, docD]);

    // Note: whereArrayContains() requires a non-null value parameter, so no null test is needed.
    // With NaN.
    snapshot = await collection.whereArrayContains('array', double.nan).get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[]);
  });

  test('testQueriesCanUseInFilters',
      skip: IntegrationTestUtil.skipOnEnterprise('in matches null and NaN'),
      () async {
    final Map<String, Object?> docA = map(<dynamic>['zip', 98101]);
    final Map<String, Object?> docB = map(<dynamic>['zip', 91102]);
    final Map<String, Object?> docC = map(<dynamic>['zip', 98103]);
    final Map<String, Object?> docD = map(<dynamic>[
      'zip',
      <int>[98101]
    ]);
    final Map<String, Object?> docE = map(<dynamic>[
      'zip',
      <dynamic>[
        '98101',
        map<dynamic>(<dynamic>['zip', 98101])
      ]
    ]);
    final Map<String, Object?> docF = map(<dynamic>[
      'zip',
      map<dynamic>(<dynamic>['code', 500])
    ]);
    final Map<String, Object?> docG = map(<dynamic>['zip', null]);
    final Map<String, Object?> docH = map(<dynamic>['zip', double.nan]);
    final Map<String, Object?> docI = map(<dynamic>[
      'zip',
      <int>[98101, 98102]
    ]);
    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      docA,
      'b',
      docB,
      'c',
      docC,
      'd',
      docD,
      'e',
      docE,
      'f',
      docF,
      'g',
      docG,
      'h',
      docH,
      'i',
      docI
    ]));

    // Search for zips matching [98101, 98103].
    QuerySnapshot snapshot =
        await collection.whereIn('zip', <int>[98101, 98103]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docA, docC]);

    // With arrays as values.
    snapshot = await collection.whereIn('zip', <dynamic>[
      98101,
      98103,
      <int>[98101, 98102]
    ]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docA, docC, docI]);

    // With objects.
    snapshot = await collection.whereIn('zip', <dynamic>[
      map<dynamic>(<dynamic>['code', 500])
    ]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docF]);

    // With null.
    snapshot = await collection.whereIn('zip', <Object?>[null]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[]);

    // With null and a value.
    snapshot = await collection.whereIn('zip', <Object?>[null, 98101]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docA]);

    // With NaN.
    snapshot = await collection.whereIn('zip', <Object?>[double.nan]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[]);

    // With NaN and a value.
    snapshot =
        await collection.whereIn('zip', <Object?>[double.nan, 98101]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docA]);
  });

  // The documents used by the not-equal and not-in tests. Since both filters
  // are inequalities, results come back ordered by the value of "zip".
  Map<String, Object?> notEqualTestDocs() => <String, Object?>{
        'a': <String, Object?>{'zip': double.nan},
        'b': <String, Object?>{'zip': 91102},
        'c': <String, Object?>{'zip': 98101},
        'd': <String, Object?>{'zip': 98103},
        'e': <String, Object?>{
          'zip': <Object?>[98101]
        },
        'f': <String, Object?>{
          'zip': <Object?>[98101, 98102]
        },
        'g': <String, Object?>{
          'zip': <Object?>[
            '98101',
            <String, Object?>{'zip': 98101}
          ]
        },
        'h': <String, Object?>{
          'zip': <String, Object?>{'code': 500}
        },
        'i': <String, Object?>{'code': 500},
        'j': <String, Object?>{'zip': null},
      };

  List<Object?> docsExcept(Map<String, Object?> all, List<String> excluded) {
    return all.entries
        .where((MapEntry<String, Object?> e) => !excluded.contains(e.key))
        .map((MapEntry<String, Object?> e) => e.value)
        .toList();
  }

  test('testQueriesCanUseNotEqualFilters', () async {
    final Map<String, Object?> all = notEqualTestDocs();
    final CollectionReference collection = await testCollectionWithDocs(all.map(
        (String k, Object? v) => MapEntry<String, Map<String, Object?>>(
            k, v! as Map<String, Object?>)));

    // Search for zips not matching 98101.
    QuerySnapshot snapshot =
        await collection.whereNotEqualTo('zip', 98101).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['c', 'i', 'j']));

    // With objects.
    snapshot = await collection
        .whereNotEqualTo('zip', <String, Object?>{'code': 500}).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['h', 'i', 'j']));

    // With null.
    snapshot = await collection.whereNotEqualTo('zip', null).get();
    expect(
        querySnapshotToValues(snapshot), docsExcept(all, <String>['i', 'j']));

    // With NaN.
    snapshot = await collection.whereNotEqualTo('zip', double.nan).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['a', 'i', 'j']));
  });

  test('testQueriesCanUseNotEqualFiltersWithDocIds',
      skip: IntegrationTestUtil.skipOnEnterprise(
          'emulator bug (v1.22.0): a listen with != on the document id fails with "__key__ filter value must be a Key"; the same query works with RunQuery'),
      () async {
    final Map<String, Object?> docA = map(<dynamic>['key', 'aa']);
    final Map<String, Object?> docB = map(<dynamic>['key', 'ab']);
    final Map<String, Object?> docC = map(<dynamic>['key', 'ba']);
    final Map<String, Object?> docD = map(<dynamic>['key', 'bb']);
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
      'aa', docA, //
      'ab', docB,
      'ba', docC,
      'bb', docD
    ]));
    final QuerySnapshot docs = await collection
        .whereNotEqualToField(FieldPath.documentId(), 'aa')
        .get();
    expect(querySnapshotToValues(docs), <dynamic>[docB, docC, docD]);
  });

  test('testQueriesCanUseNotInFilters', () async {
    final Map<String, Object?> all = notEqualTestDocs();
    final CollectionReference collection = await testCollectionWithDocs(all.map(
        (String k, Object? v) => MapEntry<String, Map<String, Object?>>(
            k, v! as Map<String, Object?>)));

    // Search for zips not matching 98101, 98103, or [98101, 98102].
    QuerySnapshot snapshot = await collection.whereNotIn('zip', <Object?>[
      98101,
      98103,
      <Object?>[98101, 98102]
    ]).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['c', 'd', 'f', 'i', 'j']));

    // With objects.
    snapshot = await collection.whereNotIn('zip', <Object?>[
      <String, Object?>{'code': 500}
    ]).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['h', 'i', 'j']));

    // With null.
    snapshot = await collection.whereNotIn('zip', <Object?>[null]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[]);

    // With NaN.
    snapshot = await collection.whereNotIn('zip', <Object?>[double.nan]).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['a', 'i', 'j']));

    // With NaN and a number.
    snapshot =
        await collection.whereNotIn('zip', <Object?>[double.nan, 98101]).get();
    expect(querySnapshotToValues(snapshot),
        docsExcept(all, <String>['a', 'c', 'i', 'j']));
  });

  test('testQueriesCanUseNotInFiltersWithDocIds',
      skip: IntegrationTestUtil.skipOnEnterprise(
          'emulator bug (v1.22.0): a listen with not-in on the document id fails with "__key__ filter value must be a Key"; the same query works with RunQuery'),
      () async {
    final Map<String, Object?> docA = map(<dynamic>['key', 'aa']);
    final Map<String, Object?> docB = map(<dynamic>['key', 'ab']);
    final Map<String, Object?> docC = map(<dynamic>['key', 'ba']);
    final Map<String, Object?> docD = map(<dynamic>['key', 'bb']);
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
      'aa', docA, //
      'ab', docB,
      'ba', docC,
      'bb', docD
    ]));
    final QuerySnapshot docs = await collection
        .whereNotInField(FieldPath.documentId(), <Object?>['aa', 'ab']).get();
    expect(querySnapshotToValues(docs), <dynamic>[docC, docD]);
  });

  // Checks that the SDK's local filtering of the (cached) documents agrees with
  // the backend.
  Future<void> checkOnlineAndOfflineResultsMatch(
      Query query, List<String> expectedDocs) async {
    final QuerySnapshot server = await query.get(Source.server);
    expect(querySnapshotToIds(server), expectedDocs);
    final QuerySnapshot cache = await query.get(Source.cache);
    expect(querySnapshotToIds(cache), expectedDocs);
  }

  test('testSDKUsesNotEqualFiltersSameAsServer', () async {
    final Map<String, Object?> all = notEqualTestDocs()
      ..['d'] = <String, Object?>{'zip': '98101'};
    final CollectionReference collection = await testCollectionWithDocs(all.map(
        (String k, Object? v) => MapEntry<String, Map<String, Object?>>(
            k, v! as Map<String, Object?>)));

    await checkOnlineAndOfflineResultsMatch(
        collection.whereNotEqualTo('zip', 98101),
        <String>['a', 'b', 'd', 'e', 'f', 'g', 'h']);
    await checkOnlineAndOfflineResultsMatch(
        collection.whereNotEqualTo('zip', double.nan),
        <String>['b', 'c', 'd', 'e', 'f', 'g', 'h']);
    await checkOnlineAndOfflineResultsMatch(
        collection.whereNotEqualTo('zip', null),
        <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
  });

  test('testSDKUsesNotInFiltersSameAsServer', () async {
    final Map<String, Object?> all = notEqualTestDocs()
      ..['d'] = <String, Object?>{'zip': '98101'};
    final CollectionReference collection = await testCollectionWithDocs(all.map(
        (String k, Object? v) => MapEntry<String, Map<String, Object?>>(
            k, v! as Map<String, Object?>)));

    await checkOnlineAndOfflineResultsMatch(
        collection.whereNotIn('zip', <Object?>[
          98101,
          98103,
          <Object?>[98101, 98102]
        ]),
        <String>['a', 'b', 'd', 'e', 'g', 'h']);
    await checkOnlineAndOfflineResultsMatch(
        collection.whereNotIn('zip', <Object?>[null]), <String>[]);
  });

  test('testQueriesCanUseInFiltersWithArrayValues', () async {
    final Map<String, Object?> docA = map(<dynamic>['zip', 98101]);
    final Map<String, Object?> docB = map(<dynamic>[
      'zip',
      <int>[98101, 98102]
    ]);
    final CollectionReference collection = await testCollectionWithDocs(
        map<Map<String, Object?>>(<dynamic>['a', docA, 'b', docB]));

    final QuerySnapshot snapshot = await collection.whereIn('zip', <dynamic>[
      <int>[98101, 98102]
    ]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docB]);
  });

  test('testQueriesCanUseArrayContainsAnyFilters',
      skip: IntegrationTestUtil.skipOnEnterprise(
          'array-contains-any matches null and NaN'), () async {
    final Map<String, Object?> docA = map(<dynamic>[
      'array',
      <dynamic>[42]
    ]);
    final Map<String, Object?> docB = map(<dynamic>[
      'array',
      <dynamic>['a', 42, 'c']
    ]);
    final Map<String, Object?> docC = map(<dynamic>[
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
    final Map<String, Object?> docD = map(<dynamic>[
      'array',
      <dynamic>[42],
      'array2',
      <dynamic>['bingo']
    ]);
    final Map<String, Object?> docE = map(<dynamic>[
      'array',
      <dynamic>[43]
    ]);
    final Map<String, Object?> docF = map(<dynamic>[
      'array',
      <dynamic>[
        map<dynamic>(<dynamic>['a', 42])
      ]
    ]);
    final Map<String, Object?> docG = map(<dynamic>['array', 42]);
    final Map<String, Object?> docH = map(<dynamic>[
      'array',
      <Object?>[null]
    ]);
    final Map<String, Object?> docI = map(<dynamic>[
      'array',
      <double>[double.nan]
    ]);

    final CollectionReference collection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      docA,
      'b',
      docB,
      'c',
      docC,
      'd',
      docD,
      'e',
      docE,
      'f',
      docF,
      'g',
      docG,
      'h',
      docH,
      'i',
      docI
    ]));

    // Search for 'array' to contain [42, 43].
    QuerySnapshot snapshot = await collection
        .whereArrayContainsAny('array', <dynamic>[42, 43]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docA, docB, docD, docE]);

    // With objects.
    snapshot = await collection.whereArrayContainsAny('array', <dynamic>[
      map<dynamic>(<dynamic>['a', 42])
    ]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docF]);

    // With null.
    snapshot =
        await collection.whereArrayContainsAny('array', <Object?>[null]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[]);

    // With null and a value.
    snapshot = await collection
        .whereArrayContainsAny('array', <Object?>[null, 43]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docE]);

    // With NaN.
    snapshot = await collection
        .whereArrayContainsAny('array', <Object?>[double.nan]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[]);

    // With NaN and a value.
    snapshot = await collection
        .whereArrayContainsAny('array', <Object?>[double.nan, 43]).get();
    expect(querySnapshotToValues(snapshot), <dynamic>[docE]);
  });

  /// Writes a document with `{x: 1}` for each of [docPaths] (with `${collectionGroup}` replaced) and returns the
  /// collection group name, which starts with 'b' for a predictable ordering.
  Future<String> writeCollectionGroupDocs(
      Firestore db, List<String> docPaths) async {
    final String collectionGroup = 'b${db.collection('foo').document().id}';
    final WriteBatch batch = db.batch();
    for (final String path in docPaths) {
      batch.set(
        db.document(path.replaceAll(r'${collectionGroup}', collectionGroup)),
        <String, Object?>{'x': 1},
      );
    }
    await batch.commit();
    return collectionGroup;
  }

  test('testCollectionGroupQueries', () async {
    final Firestore db = await testFirestore();
    final String group = await writeCollectionGroupDocs(db, <String>[
      r'abc/123/${collectionGroup}/cg-doc1',
      r'abc/123/${collectionGroup}/cg-doc2',
      r'${collectionGroup}/cg-doc3',
      r'${collectionGroup}/cg-doc4',
      r'def/456/${collectionGroup}/cg-doc5',
      r'${collectionGroup}/virtual-doc/nested-coll/not-cg-doc',
      r'x${collectionGroup}/not-cg-doc',
      r'${collectionGroup}x/not-cg-doc',
      r'abc/123/${collectionGroup}x/not-cg-doc',
      r'abc/123/x${collectionGroup}/not-cg-doc',
      r'abc/${collectionGroup}',
    ]);

    final QuerySnapshot querySnapshot = await db.collectionGroup(group).get();
    expect(
      IntegrationTestUtil.querySnapshotToIds(querySnapshot),
      <String>['cg-doc1', 'cg-doc2', 'cg-doc3', 'cg-doc4', 'cg-doc5'],
    );
  });

  test('testCollectionGroupQueriesWithStartAtEndAtWithArbitraryDocumentIds',
      () async {
    final Firestore db = await testFirestore();
    final String group = await writeCollectionGroupDocs(db, <String>[
      r'a/a/${collectionGroup}/cg-doc1',
      r'a/b/a/b/${collectionGroup}/cg-doc2',
      r'a/b/${collectionGroup}/cg-doc3',
      r'a/b/c/d/${collectionGroup}/cg-doc4',
      r'a/c/${collectionGroup}/cg-doc5',
      r'${collectionGroup}/cg-doc6',
      r'a/b/nope/nope',
    ]);

    QuerySnapshot querySnapshot = await db
        .collectionGroup(group)
        .orderByField(FieldPath.documentId())
        .startAt(<Object?>['a/b']).endAt(<Object?>['a/b0']).get();
    expect(IntegrationTestUtil.querySnapshotToIds(querySnapshot),
        <String>['cg-doc2', 'cg-doc3', 'cg-doc4']);

    querySnapshot = await db
        .collectionGroup(group)
        .orderByField(FieldPath.documentId())
        .startAfter(<Object?>['a/b']).endBefore(
            <Object?>['a/b/$group/cg-doc3']).get();
    expect(IntegrationTestUtil.querySnapshotToIds(querySnapshot),
        <String>['cg-doc2']);
  });

  test('testCollectionGroupQueriesWithWhereFiltersOnArbitraryDocumentIds',
      () async {
    final Firestore db = await testFirestore();
    final String group = await writeCollectionGroupDocs(db, <String>[
      r'a/a/${collectionGroup}/cg-doc1',
      r'a/b/a/b/${collectionGroup}/cg-doc2',
      r'a/b/${collectionGroup}/cg-doc3',
      r'a/b/c/d/${collectionGroup}/cg-doc4',
      r'a/c/${collectionGroup}/cg-doc5',
      r'${collectionGroup}/cg-doc6',
      r'a/b/nope/nope',
    ]);

    QuerySnapshot querySnapshot = await db
        .collectionGroup(group)
        .whereGreaterThanOrEqualToField(FieldPath.documentId(), 'a/b')
        .whereLessThanOrEqualToField(FieldPath.documentId(), 'a/b0')
        .get();
    expect(IntegrationTestUtil.querySnapshotToIds(querySnapshot),
        <String>['cg-doc2', 'cg-doc3', 'cg-doc4']);

    querySnapshot = await db
        .collectionGroup(group)
        .whereGreaterThanField(FieldPath.documentId(), 'a/b')
        .whereLessThanField(FieldPath.documentId(), 'a/b/$group/cg-doc3')
        .get();
    expect(IntegrationTestUtil.querySnapshotToIds(querySnapshot),
        <String>['cg-doc2']);
  });

  // See https://github.com/firebase/firebase-android-sdk/issues/3528
  test('testAddThenUpdatesWhileOffline', () async {
    final CollectionReference collection = await testCollection();
    await collection.firestore.disableNetwork();

    unawaited(collection.add(<String, Object?>{'foo': 'zzyzx', 'bar': '1'}));

    final QuerySnapshot snapshot1 = await collection.get(Source.cache);
    expect(querySnapshotToValues(snapshot1), <Map<String, Object?>>[
      <String, Object?>{'foo': 'zzyzx', 'bar': '1'}
    ]);
    final DocumentReference doc = snapshot1.documents.first.reference;

    unawaited(doc.update(<String, Object?>{'bar': '2'}));

    final QuerySnapshot snapshot2 = await collection.get(Source.cache);
    expect(querySnapshotToValues(snapshot2), <Map<String, Object?>>[
      <String, Object?>{'foo': 'zzyzx', 'bar': '2'}
    ]);
  });

  test('testMultipleUpdatesWhileOffline', () async {
    final CollectionReference collection = await testCollection();
    await collection.firestore.disableNetwork();

    final DocumentReference doc = collection.document();
    unawaited(doc.set(<String, Object?>{'foo': 'zzyzx', 'bar': '1'},
        SetOptions.mergeFields(<String>['foo', 'bar'])));

    final QuerySnapshot snapshot1 = await collection.get(Source.cache);
    expect(querySnapshotToValues(snapshot1), <Map<String, Object?>>[
      <String, Object?>{'foo': 'zzyzx', 'bar': '1'}
    ]);

    unawaited(doc.update(<String, Object?>{'bar': '2'}));

    final QuerySnapshot snapshot2 = await collection.get(Source.cache);
    expect(querySnapshotToValues(snapshot2), <Map<String, Object?>>[
      <String, Object?>{'foo': 'zzyzx', 'bar': '2'}
    ]);
  });

  // These two upstream tests count existence filter mismatches through TestingHooks (a test-only hook of the Android
  // SDK that the port does not have) against a backend that sends bloom filters, which the emulator does not.
  test('resumingAQueryShouldUseBloomFilterToAvoidFullRequery', () {},
      skip:
          'NOT PORTABLE: needs the upstream TestingHooks (existence filter mismatch capture) and a production '
          'backend that sends bloom filters; the bloom filter logic itself is covered by the existence_filter spec '
          'tests.');

  test('bloomFilterShouldCorrectlyEncodeComplexUnicodeCharacters', () {},
      skip:
          'NOT PORTABLE: needs the upstream TestingHooks (existence filter mismatch capture) and a production '
          'backend that sends bloom filters; the bloom filter logic itself is covered by the existence_filter spec '
          'tests.');
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
