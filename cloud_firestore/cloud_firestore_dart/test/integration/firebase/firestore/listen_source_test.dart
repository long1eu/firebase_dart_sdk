// Copyright 2024 Google LLC (modelled on the upstream SnapshotListenerSourceTest, b77c218)
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

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

// NOT RUN by the author: written without executing it, needs the emulator.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/listen_source_test';

  setUp(IntegrationTestUtil.testFirestore);

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  /// Waits until [events] has at least [count] elements.
  Future<void> waitFor(List<Object?> events, int count) async {
    for (int i = 0; i < 100 && events.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(events.length, greaterThanOrEqualTo(count));
  }

  const SnapshotListenOptions cacheOptions =
      SnapshotListenOptions(source: ListenSource.cache);

  test('cache listener on an empty cache raises an empty snapshot', () async {
    final CollectionReference collection =
        await IntegrationTestUtil.testCollection();
    await collection.firestore.disableNetwork();

    final List<QuerySnapshot> events = <QuerySnapshot>[];
    final StreamSubscription<QuerySnapshot> sub =
        collection.getSnapshotsWithOptions(cacheOptions).listen(events.add);
    await waitFor(events, 1);

    expect(events.first.documentChanges, isEmpty);
    expect(events.first.metadata.isFromCache, isTrue);
    await sub.cancel();
  });

  test('cache listener returns the cached documents and local writes',
      () async {
    final CollectionReference collection =
        await IntegrationTestUtil.testCollectionWithDocs(map(<dynamic>[
      'a',
      map<String>(<String>['k', 'a']),
      'b',
      map<String>(<String>['k', 'b']),
    ]));
    // Fill the cache from the backend.
    await collection.get();

    final List<QuerySnapshot> events = <QuerySnapshot>[];
    final StreamSubscription<QuerySnapshot> sub =
        collection.getSnapshotsWithOptions(cacheOptions).listen(events.add);
    await waitFor(events, 1);

    expect(events.first.metadata.isFromCache, isTrue);
    expect(events.first.documentChanges.length, 2);

    // A local write raises an event even though the cache only listener never
    // contacts the backend itself.
    unawaited(collection.document('c').set(map(<String>['k', 'c'])));
    await waitFor(events, 2);
    expect(events.last.documentChanges.length, 1);
    expect(events.last.metadata.hasPendingWrites, isTrue);
    expect(events.last.metadata.isFromCache, isTrue);
    await sub.cancel();
  });

  test('cache listener on a document does not raise server snapshots',
      () async {
    final DocumentReference doc =
        await IntegrationTestUtil.testDocumentWithData(
            map(<String>['key', 'value']));
    await doc.get();

    final List<DocumentSnapshot> events = <DocumentSnapshot>[];
    final StreamSubscription<DocumentSnapshot> sub =
        doc.getSnapshotsWithOptions(cacheOptions).listen(events.add);
    await waitFor(events, 1);

    expect(events.first.exists, isTrue);
    expect(events.first.metadata.isFromCache, isTrue);
    expect(events.first.data, map(<String>['key', 'value']));
    await sub.cancel();
  });

  test('default and cache listeners on the same query', () async {
    final CollectionReference collection =
        await IntegrationTestUtil.testCollectionWithDocs(map(<dynamic>[
      'a',
      map<String>(<String>['k', 'a']),
    ]));

    final List<QuerySnapshot> cacheEvents = <QuerySnapshot>[];
    final List<QuerySnapshot> remoteEvents = <QuerySnapshot>[];
    // Cache first: the backend listen is started when the second one is added.
    final StreamSubscription<QuerySnapshot> cacheSub = collection
        .getSnapshotsWithOptions(cacheOptions)
        .listen(cacheEvents.add);
    await waitFor(cacheEvents, 1);
    final StreamSubscription<QuerySnapshot> remoteSub =
        collection.snapshots.listen(remoteEvents.add);

    // The default listener gets the server data.
    for (int i = 0;
        i < 100 &&
            !remoteEvents.any((QuerySnapshot s) => !s.metadata.isFromCache);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(remoteEvents.last.metadata.isFromCache, isFalse);
    expect(remoteEvents.last.documentChanges.length, 1);

    // Removing the default listener leaves the cache listener working.
    await remoteSub.cancel();
    await collection.document('b').set(map(<String>['k', 'b']));
    await waitFor(cacheEvents, 2);
    expect(cacheEvents.last.documentChanges.length, 1);
    await cacheSub.cancel();
  });


  // The emulator behaviour of these two is not verified (not run).
  test('memory cache settings with LRU gc open a working instance', () async {
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final Firestore firestore =
        await IntegrationTestUtil.testFirestore(FirestoreSettings(
      host: base.host,
      port: base.port,
      sslEnabled: base.sslEnabled,
      cacheSettings: MemoryCacheSettings(
          gcSettings: MemoryLruGcSettings(sizeBytes: 2 * 1024 * 1024)),
    ));
    final DocumentReference doc = firestore.collection('lru').document();
    await doc.set(map(<String>['k', 'v']));
    expect((await doc.get()).data, map(<String>['k', 'v']));
  });
}
