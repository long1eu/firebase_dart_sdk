// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;

const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;

const testFirestore = IntegrationTestUtil.testFirestore;

// ignore_for_file: unawaited_futures
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/limit_to_last';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<CollectionReference> sortedCollection() {
    return testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['k', 'a', 'sort', 0]),
      'b',
      map<dynamic>(<dynamic>['k', 'b', 'sort', 1]),
      'c',
      map<dynamic>(<dynamic>['k', 'c', 'sort', 1]),
      'd',
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2])
    ]));
  }

  Map<String, Object?> value(String k, int sort) =>
      map<dynamic>(<dynamic>['k', k, 'sort', sort]);

  test('testLimitToLastReturnsTheLastDocumentsInQueryOrder', () async {
    final CollectionReference collection = await sortedCollection();

    QuerySnapshot snapshot =
        await collection.orderBy('sort').limitToLast(2).get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('c', 1),
      value('d', 2),
    ]);

    // The results are in the order of the query, not reversed.
    snapshot = await collection
        .orderBy('sort', Direction.descending)
        .limitToLast(2)
        .get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('b', 1),
      value('a', 0),
    ]);
  });

  test('testLimitToLastLargerThanTheResultReturnsEverything', () async {
    final CollectionReference collection = await sortedCollection();

    final QuerySnapshot snapshot =
        await collection.orderBy('sort').limitToLast(100).get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('a', 0),
      value('b', 1),
      value('c', 1),
      value('d', 2),
    ]);
  });

  test('testLimitToLastMustAlsoHaveExplicitOrderBy', () async {
    final CollectionReference collection = await sortedCollection();

    final Query query = collection.limitToLast(2);
    await expectError(query.get,
        'limitToLast() queries require specifying at least one orderBy() clause');
    await expectError(() => query.get(Source.cache),
        'limitToLast() queries require specifying at least one orderBy() clause');
    await expectError(() => query.snapshots.first,
        'limitToLast() queries require specifying at least one orderBy() clause');
  });

  test('testLimitAndLimitToLastOverrideEachOther', () async {
    final CollectionReference collection = await sortedCollection();

    // The last call wins.
    QuerySnapshot snapshot =
        await collection.orderBy('sort').limitToLast(1).limit(2).get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('a', 0),
      value('b', 1),
    ]);

    snapshot = await collection.orderBy('sort').limit(1).limitToLast(2).get();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('c', 1),
      value('d', 2),
    ]);
  });

  test('testLimitToLastWithCursors', () async {
    final CollectionReference collection =
        await testCollectionWithDocs(map<Map<String, Object?>>(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['k', 'a']),
      'b',
      map<dynamic>(<dynamic>['k', 'b']),
      'c',
      map<dynamic>(<dynamic>['k', 'c']),
      'd',
      map<dynamic>(<dynamic>['k', 'd']),
      'e',
      map<dynamic>(<dynamic>['k', 'e']),
    ]));

    List<Object?> keys(QuerySnapshot snapshot) =>
        snapshot.documents.map((dynamic d) => d.get('k') as Object?).toList();

    final Query base = collection.orderBy('k');

    expect(keys(await base.endBefore(<Object?>['d']).limitToLast(2).get()),
        <String>['b', 'c']);
    expect(keys(await base.endAt(<Object?>['d']).limitToLast(2).get()),
        <String>['c', 'd']);
    expect(keys(await base.startAfter(<Object?>['b']).limitToLast(2).get()),
        <String>['d', 'e']);
    expect(keys(await base.startAt(<Object?>['b']).limitToLast(10).get()),
        <String>['b', 'c', 'd', 'e']);
    expect(
        keys(await base
            .startAt(<Object?>['b'])
            .endBefore(<Object?>['e'])
            .limitToLast(2)
            .get()),
        <String>['c', 'd']);

    // Cursors that are given in the query order, with a descending ordering.
    final Query descending = collection.orderBy('k', Direction.descending);
    expect(keys(await descending.startAt(<Object?>['d']).limitToLast(2).get()),
        <String>['b', 'a']);
  });

  test('testLimitToLastFromCache', () async {
    final CollectionReference collection = await sortedCollection();
    final Query query = collection.orderBy('sort').limitToLast(2);

    // Populate the cache.
    await query.get();

    final QuerySnapshot snapshot = await query.get(Source.cache);
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('c', 1),
      value('d', 2),
    ]);
  });

  test('testListenToLimitToLastRaisesUpdatesInQueryOrder', () async {
    final CollectionReference collection = await sortedCollection();
    final Query query = collection.orderBy('sort').limitToLast(2);

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> subscription = query
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);

    QuerySnapshot snapshot = await accumulator.wait();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('c', 1),
      value('d', 2),
    ]);

    // A new last document pushes the first one out of the result.
    final DocumentReference added = await collection.add(value('e', 3));
    snapshot = await accumulator.awaitRemoteEvent();
    expect(querySnapshotToValues(snapshot), <Map<String, Object?>>[
      value('d', 2),
      value('e', 3),
    ]);

    // Deleting a document from the result pulls an older one back in.
    await added.delete();
    final QuerySnapshot afterDelete = await accumulator.awaitRemoteEvent();
    expect(querySnapshotToValues(afterDelete), <Map<String, Object?>>[
      value('c', 1),
      value('d', 2),
    ]);

    await subscription.cancel();
  });

  // Two queries that mapped to the same target ID are referred to as "mirror
  // queries". An example for a mirror query is a limitToLast() query and a
  // limit() query that share the same backend Target ID. Since limitToLast()
  // queries are sent to the backend with a modified orderBy() clause, they can
  // map to the same target representation as limit() query, even if both
  // queries appear separate to the user.
  test('testListenUnlistenRelistenSequenceOfMirrorQueries', () async {
    final CollectionReference collection = await sortedCollection();

    // Setup `limit` query.
    final Query limit = collection.limit(2).orderBy('sort');
    final EventAccumulator<QuerySnapshot> limitAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> limitSubscription = limit
        .getSnapshots(MetadataChanges.include)
        .listen(limitAccumulator.onData, onError: limitAccumulator.onError);

    // Setup mirroring `limitToLast` query.
    final Query limitToLast =
        collection.limitToLast(2).orderBy('sort', Direction.descending);
    final EventAccumulator<QuerySnapshot> limitToLastAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> limitToLastSubscription = limitToLast
        .getSnapshots(MetadataChanges.include)
        .listen(limitToLastAccumulator.onData,
            onError: limitToLastAccumulator.onError);

    // Verify both query get expected result.
    List<Map<String, Object?>> data =
        querySnapshotToValues(await limitAccumulator.wait());
    expect(data, <Map<String, Object?>>[value('a', 0), value('b', 1)]);
    data = querySnapshotToValues(await limitToLastAccumulator.wait());
    expect(data, <Map<String, Object?>>[value('b', 1), value('a', 0)]);

    // Unlisten then re-listen limit query.
    await limitSubscription.cancel();
    limitSubscription = limit
        .getSnapshots(MetadataChanges.include)
        .listen(limitAccumulator.onData, onError: limitAccumulator.onError);

    // Verify `limit` query still works.
    data = querySnapshotToValues(await limitAccumulator.wait());
    expect(data, <Map<String, Object?>>[value('a', 0), value('b', 1)]);

    // Add a document that would change the result set.
    await collection.add(value('e', -1));

    // Verify both query get expected result.
    data = querySnapshotToValues(await limitAccumulator.awaitRemoteEvent());
    expect(data, <Map<String, Object?>>[value('e', -1), value('a', 0)]);
    data =
        querySnapshotToValues(await limitToLastAccumulator.awaitRemoteEvent());
    expect(data, <Map<String, Object?>>[value('a', 0), value('e', -1)]);

    // Unlisten to limitToLast, update a doc, then relisten to limitToLast.
    await limitToLastSubscription.cancel();
    await collection.document('a').update(value('a', -2));
    limitToLastSubscription = limitToLast
        .getSnapshots(MetadataChanges.include)
        .listen(limitToLastAccumulator.onData,
            onError: limitToLastAccumulator.onError);

    // Verify both query get expected result.
    data = querySnapshotToValues(await limitAccumulator.awaitRemoteEvent());
    expect(data, <Map<String, Object?>>[value('a', -2), value('e', -1)]);
    data =
        querySnapshotToValues(await limitToLastAccumulator.awaitRemoteEvent());
    expect(data, <Map<String, Object?>>[value('e', -1), value('a', -2)]);

    await limitSubscription.cancel();
    await limitToLastSubscription.cancel();
  });
}
