// Copyright 2026 Google LLC
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

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

// Port of the upstream SnapshotListenerSourceTest (the cases that listen_source_test.dart does not cover).
void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration/snapshot_listener_source';

  setUp(IntegrationTestUtil.testFirestore);

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  const SnapshotListenOptions fromCache =
      SnapshotListenOptions(source: ListenSource.cache);
  const SnapshotListenOptions fromCacheWithMetadata = SnapshotListenOptions(
    source: ListenSource.cache,
    metadataChanges: MetadataChanges.include,
  );

  final List<Map<String, Object?>> Function(QuerySnapshot) values =
      IntegrationTestUtil.querySnapshotToValues;

  Map<String, Object?> doc(String k, int sort) => <String, Object?>{
        'k': k,
        'sort': sort,
      };

  Future<CollectionReference> collectionAB() =>
      IntegrationTestUtil.testCollectionWithDocs(<String, Map<String, Object?>>{
        'a': doc('a', 0),
        'b': doc('b', 1),
      });

  Future<void> writeWithTransaction(
      DocumentReference ref, Map<String, Object?> data) {
    return ref.firestore.runTransaction<void>((Transaction transaction) async {
      transaction.set(ref, data);
    });
  }

  test('canRaiseSnapshotFromCacheForQuery', () async {
    final CollectionReference collection = await IntegrationTestUtil
        .testCollectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'k': 'a'},
    });
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);

    final QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[
      <String, Object?>{'k': 'a'}
    ]);
    expect(snapshot.metadata.isFromCache, isTrue);

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('canRaiseSnapshotFromCacheForDocumentReference', () async {
    final DocumentReference docRef =
        await IntegrationTestUtil.testDocumentWithData(
            <String, Object?>{'k': 'a'});
    await docRef.get(); // Populate the cache.

    final EventAccumulator<DocumentSnapshot> accumulator =
        EventAccumulator<DocumentSnapshot>();
    final StreamSubscription<DocumentSnapshot> listener = docRef
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);

    final DocumentSnapshot snapshot = await accumulator.wait();
    expect(snapshot.data, <String, Object?>{'k': 'a'});
    expect(snapshot.metadata.isFromCache, isTrue);

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('listenToCacheShouldNotBeAffectedByOnlineStatusChange', () async {
    final CollectionReference collection = await IntegrationTestUtil
        .testCollectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'k': 'a'},
    });
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshotsWithOptions(fromCacheWithMetadata)
        .listen(accumulator.onData, onError: accumulator.onError);

    final QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[
      <String, Object?>{'k': 'a'}
    ]);
    expect(snapshot.metadata.isFromCache, isTrue);

    await collection.firestore.disableNetwork();
    await collection.firestore.enableNetwork();

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('multipleListenersSourcedFromCacheCanWorkIndependently', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereGreaterThan('sort', 0).orderBy('sort');
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener1 = query
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);
    final StreamSubscription<QuerySnapshot> listener2 = query
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);

    List<QuerySnapshot> snapshots = await accumulator.waitFor(2);
    expect(values(snapshots[0]), <Map<String, Object?>>[doc('b', 1)]);
    expect(values(snapshots[1]), values(snapshots[0]));
    expect(snapshots[0].metadata, snapshots[1].metadata);

    // Do a local mutation.
    await collection.add(doc('c', 2));

    snapshots = await accumulator.waitFor(2);
    expect(
        values(snapshots[0]), <Map<String, Object?>>[doc('b', 1), doc('c', 2)]);
    expect(values(snapshots[1]), values(snapshots[0]));
    expect(snapshots[0].metadata, snapshots[1].metadata);

    // Detach one listener and do a local mutation. The other listener should not be affected.
    await listener1.cancel();
    await collection.add(doc('d', 3));

    final QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[
      doc('b', 1),
      doc('c', 2),
      doc('d', 3),
    ]);
    expect(snapshot.metadata.isFromCache, isTrue);

    await accumulator.assertNoAdditionalEvents();
    await listener2.cancel();
  });

  // Two queries that map to the same target id are "mirror queries" (e.g. a limitToLast() query and the limit() query
  // that share the backend target).
  test('canListenUnlistenRelistenMirrorQueriesFromCache', () async {
    final CollectionReference collection = await IntegrationTestUtil
        .testCollectionWithDocs(<String, Map<String, Object?>>{
      'a': doc('a', 0),
      'b': doc('b', 1),
      'c': doc('c', 1),
    });
    await collection.get(); // Populate the cache.

    final Query limit = collection.limit(2).orderBy('sort');
    final EventAccumulator<QuerySnapshot> limitAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> limitRegistration = limit
        .getSnapshotsWithOptions(fromCache)
        .listen(limitAccumulator.onData, onError: limitAccumulator.onError);

    final Query limitToLast =
        collection.limitToLast(2).orderBy('sort', Direction.descending);
    final EventAccumulator<QuerySnapshot> limitToLastAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> limitToLastRegistration = limitToLast
        .getSnapshotsWithOptions(fromCache)
        .listen(limitToLastAccumulator.onData,
            onError: limitToLastAccumulator.onError);

    QuerySnapshot snapshot = await limitAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('a', 0), doc('b', 1)]);
    snapshot = await limitToLastAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1), doc('a', 0)]);

    // Un-listen then re-listen to the limit query.
    await limitRegistration.cancel();
    limitRegistration = limit
        .getSnapshotsWithOptions(fromCache)
        .listen(limitAccumulator.onData, onError: limitAccumulator.onError);

    snapshot = await limitAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('a', 0), doc('b', 1)]);
    expect(snapshot.metadata.isFromCache, isTrue);

    // Do a local mutation.
    await collection.add(doc('d', -1));

    snapshot = await limitAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('d', -1), doc('a', 0)]);
    expect(snapshot.metadata.hasPendingWrites, isTrue);
    snapshot = await limitToLastAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('a', 0), doc('d', -1)]);
    expect(snapshot.metadata.hasPendingWrites, isTrue);

    // Un-listen to limitToLast, update a doc, then re-listen to limitToLast.
    await limitToLastRegistration.cancel();
    await collection.document('a').update(doc('a', -2));
    limitToLastRegistration = limitToLast
        .getSnapshotsWithOptions(fromCache)
        .listen(limitToLastAccumulator.onData,
            onError: limitToLastAccumulator.onError);

    snapshot = await limitAccumulator.wait();
    expect(
        values(snapshot), <Map<String, Object?>>[doc('a', -2), doc('d', -1)]);
    expect(snapshot.metadata.hasPendingWrites, isTrue);
    snapshot = await limitToLastAccumulator.wait();
    expect(
        values(snapshot), <Map<String, Object?>>[doc('d', -1), doc('a', -2)]);
    // The limitToLast query was listened to after the doc update.
    expect(snapshot.metadata.hasPendingWrites, isFalse);

    await limitRegistration.cancel();
    await limitToLastRegistration.cancel();
  });

  test('canListenToDefaultSourceFirstAndThenCache', () async {
    final CollectionReference collection = await collectionAB();
    final Query query =
        collection.whereGreaterThanOrEqualTo('sort', 1).orderBy('sort');

    // Listen with the default options, which also populates the cache.
    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);

    QuerySnapshot snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1)]);
    expect(snapshot.metadata.isFromCache, isFalse);

    // Listen to the same query from the cache.
    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);

    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1)]);
    // The metadata is in sync with the server due to the default listener.
    expect(snapshot.metadata.isFromCache, isFalse);

    await defaultAccumulator.assertNoAdditionalEvents();
    await cacheAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
    await cacheRegistration.cancel();
  });

  test('canListenToCacheSourceFirstAndThenDefault', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereNotEqualTo('sort', 0).orderBy('sort');

    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCacheWithMetadata)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);

    QuerySnapshot snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), isEmpty); // The cache is empty.
    expect(snapshot.metadata.isFromCache, isTrue);

    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .getSnapshots(MetadataChanges.include)
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);

    snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1)]);
    expect(snapshot.metadata.isFromCache, isFalse);

    // The default listener updates the cache, which makes the cache listener raise a snapshot.
    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1)]);
    expect(snapshot.metadata.isFromCache, isFalse);

    await defaultAccumulator.assertNoAdditionalEvents();
    await cacheAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
    await cacheRegistration.cancel();
  });

  test('willNotGetMetadataOnlyUpdatesIfListeningToCacheOnly', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereNotEqualTo('sort', 0).orderBy('sort');
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = query
        .getSnapshotsWithOptions(fromCacheWithMetadata)
        .listen(accumulator.onData, onError: accumulator.onError);

    QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1)]);
    expect(snapshot.metadata.isFromCache, isTrue);

    await collection.add(doc('c', 2));

    snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('b', 1), doc('c', 2)]);
    expect(snapshot.metadata.isFromCache, isTrue);
    expect(snapshot.metadata.hasPendingWrites, isTrue);

    // The listener is not told when the server acknowledges the local mutation.
    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('willHaveSyncedMetadataUpdatesWhenListeningToBothCacheAndDefaultSource',
      () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereNotEqualTo('sort', 0).orderBy('sort');
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCacheWithMetadata)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);

    QuerySnapshot snapshot = await cacheAccumulator.wait();
    List<Map<String, Object?>> expected = <Map<String, Object?>>[doc('b', 1)];
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isTrue);

    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .getSnapshots(MetadataChanges.include)
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);

    // The first snapshot is raised from the cache.
    snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isTrue);
    // The second one from the server result.
    snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);

    // As it listens to metadata changes, the cache listener is in sync with the default listener.
    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);

    await collection.add(doc('c', 2));

    // The local mutation raises a snapshot.
    snapshot = await defaultAccumulator.wait();
    expected = <Map<String, Object?>>[doc('b', 1), doc('c', 2)];
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);
    expect(snapshot.metadata.hasPendingWrites, isTrue);
    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);
    expect(snapshot.metadata.hasPendingWrites, isTrue);

    // The server acknowledges the local mutation.
    snapshot = await defaultAccumulator.wait();
    expect(snapshot.metadata.isFromCache, isFalse);
    expect(snapshot.metadata.hasPendingWrites, isFalse);
    snapshot = await cacheAccumulator.wait();
    expect(snapshot.metadata.isFromCache, isFalse);
    expect(snapshot.metadata.hasPendingWrites, isFalse);

    await defaultAccumulator.assertNoAdditionalEvents();
    await cacheAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
    await cacheRegistration.cancel();
  });

  test('canUnlistenToDefaultSourceWhileStillListeningToCache', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereNotEqualTo('sort', 0).orderBy('sort');

    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);
    await defaultAccumulator.wait();

    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);
    await cacheAccumulator.wait();

    await defaultRegistration.cancel();
    await defaultAccumulator.assertNoAdditionalEvents();

    // A new document must still reach the cache listener.
    await collection.add(doc('c', -1));

    final QuerySnapshot snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('c', -1), doc('b', 1)]);

    await cacheAccumulator.assertNoAdditionalEvents();
    await cacheRegistration.cancel();
  });

  test('canUnlistenToCacheSourceWhileStillListeningToServer', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereNotEqualTo('sort', 0).orderBy('sort');

    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);
    await defaultAccumulator.wait();

    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);
    await cacheAccumulator.wait();

    await cacheRegistration.cancel();
    await cacheAccumulator.assertNoAdditionalEvents();

    await collection.add(doc('c', -1));

    final QuerySnapshot snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('c', -1), doc('b', 1)]);

    await defaultAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
  });

  test('canListenUnlistenRelistenToSameQueryWithDifferentSourceOptions',
      () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereGreaterThan('sort', 0).orderBy('sort');

    // Default listener, which also populates the cache.
    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> defaultRegistration = query.snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);

    QuerySnapshot snapshot = await defaultAccumulator.wait();
    List<Map<String, Object?>> expected = <Map<String, Object?>>[doc('b', 1)];
    expect(values(snapshot), expected);

    // The same query from the cache.
    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);

    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);

    // Un-listen the default listener, add a doc and re-listen.
    await defaultRegistration.cancel();
    await collection.add(doc('c', 2));

    snapshot = await cacheAccumulator.wait();
    expected = <Map<String, Object?>>[doc('b', 1), doc('c', 2)];
    expect(values(snapshot), expected);

    defaultRegistration = query.snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);
    snapshot = await defaultAccumulator.wait();
    expect(values(snapshot), expected);

    // Un-listen the cache listener, update a doc and re-listen to the cache.
    await cacheRegistration.cancel();
    await collection.document('b').update(doc('b', 3));

    snapshot = await defaultAccumulator.wait();
    expected = <Map<String, Object?>>[doc('c', 2), doc('b', 3)];
    expect(values(snapshot), expected);

    cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);
    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);

    await defaultAccumulator.assertNoAdditionalEvents();
    await cacheAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
    await cacheRegistration.cancel();
  });

  test('canListenToCompositeIndexQueriesFromCache', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection
        .whereLessThanOrEqualTo('k', 'a')
        .whereGreaterThanOrEqualTo('sort', 0);
    await collection.get(); // Populate the cache.

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = query
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);

    final QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), <Map<String, Object?>>[doc('a', 0)]);
    expect(snapshot.metadata.isFromCache, isTrue);

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('canRaiseInitialSnapshotFromCacheEvenIfItIsEmpty', () async {
    final CollectionReference collection =
        await IntegrationTestUtil.testCollection();

    QuerySnapshot snapshot = await collection.get(); // Populate the cache.
    expect(values(snapshot), isEmpty);

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshotsWithOptions(fromCache)
        .listen(accumulator.onData, onError: accumulator.onError);

    snapshot = await accumulator.wait();
    expect(values(snapshot), isEmpty);
    expect(snapshot.metadata.isFromCache, isTrue);

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('willNotBeTriggeredByTransactionsWhileListeningToCache', () async {
    final CollectionReference collection =
        await IntegrationTestUtil.testCollection();

    final EventAccumulator<QuerySnapshot> accumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> listener = collection
        .getSnapshotsWithOptions(fromCacheWithMetadata)
        .listen(accumulator.onData, onError: accumulator.onError);

    final QuerySnapshot snapshot = await accumulator.wait();
    expect(values(snapshot), isEmpty);

    // A transaction writes without raising any local event.
    await writeWithTransaction(
        collection.document(), <String, Object?>{'k': 'a'});

    await accumulator.assertNoAdditionalEvents();
    await listener.cancel();
  });

  test('shareServerSideUpdatesWhenListeningToBothCacheAndDefault', () async {
    final CollectionReference collection = await collectionAB();
    final Query query = collection.whereGreaterThan('sort', 0).orderBy('sort');

    final EventAccumulator<QuerySnapshot> defaultAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> defaultRegistration = query
        .snapshots
        .listen(defaultAccumulator.onData, onError: defaultAccumulator.onError);
    QuerySnapshot snapshot = await defaultAccumulator.wait();
    List<Map<String, Object?>> expected = <Map<String, Object?>>[doc('b', 1)];
    expect(values(snapshot), expected);

    final EventAccumulator<QuerySnapshot> cacheAccumulator =
        EventAccumulator<QuerySnapshot>();
    final StreamSubscription<QuerySnapshot> cacheRegistration = query
        .getSnapshotsWithOptions(fromCache)
        .listen(cacheAccumulator.onData, onError: cacheAccumulator.onError);
    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);

    // A transaction mocks a server side update.
    await writeWithTransaction(collection.document(), doc('c', 2));

    snapshot = await defaultAccumulator.wait();
    expected = <Map<String, Object?>>[doc('b', 1), doc('c', 2)];
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);

    snapshot = await cacheAccumulator.wait();
    expect(values(snapshot), expected);
    expect(snapshot.metadata.isFromCache, isFalse);

    await defaultAccumulator.assertNoAdditionalEvents();
    await cacheAccumulator.assertNoAdditionalEvents();
    await defaultRegistration.cancel();
    await cacheRegistration.cancel();
  });
}
