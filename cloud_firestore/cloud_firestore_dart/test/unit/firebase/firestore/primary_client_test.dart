// The primary lease seen from Firestore instances (stage 1 of the multi-client plan): two instances of different
// apps on one cache file, as after a hot restart or with a background isolate. The second takes the lease (forced
// ownership, the default), both keep working, the refresh timer hands the lease back when one terminates, and
// clearPersistence with the other one alive empties the cache in place and makes the other one terminate.

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/test_hygiene.dart';
import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

void main() {
  checkTestsLeaveNothingBehind();

  late String dbName;

  setUp(() {
    dbName = 'primary-${const Uuid().v4()}.db';
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
  });

  Future<Firestore> open(String appName) async {
    final FirebaseApp app = newApp('$appName-${const Uuid().v4()}');
    addTearDown(app.delete);
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase: openFixed(dbName),
    );
    addTearDown(firestore.terminate);
    // Waits for the initialization: the queue of the client runs it first.
    await firestore.waitForPendingWrites();
    return firestore;
  }

  /// Runs the metadata refresh of [firestore] now and waits for it, and for the change of the primary state that it
  /// queued.
  Future<void> refresh(Firestore firestore) async {
    firestore.scheduler.runUntil(TaskId.clientMetadataRefresh);
    // Anything that goes through the queue of the client after the refresh (not waitForPendingWrites: the writes
    // of these tests are never acknowledged). Twice: the refresh queues the change of the primary state behind the
    // first one.
    await firestore.getNamedQuery('none');
    await firestore.getNamedQuery('none');
  }

  /// Whether [firestore] acts as the primary client: it uses the network and schedules the garbage collection and
  /// the index backfill.
  bool actsAsPrimary(Firestore firestore) {
    final bool network = firestore.client.remoteStore.canUseNetwork;
    final bool gc =
        firestore.scheduler.getTask(TaskId.garbageCollection) != null;
    final bool backfill =
        firestore.scheduler.getTask(TaskId.indexBackfill) != null;
    expect(
      <bool>[
        network,
        gc,
        backfill,
        firestore.client.syncEngine.isPrimaryClient,
      ],
      everyElement(network),
      reason: 'network $network, garbage collection $gc, backfill $backfill',
    );
    return network;
  }

  test('the refresh timer is scheduled and stops with the instance', () async {
    final Firestore firestore = await open('timer');
    final TimerTask? task = firestore.scheduler.getTask(
      TaskId.clientMetadataRefresh,
    );
    expect(task, isNotNull);
    await refresh(firestore);
    expect(
      firestore.scheduler.getTask(TaskId.clientMetadataRefresh),
      isNotNull,
      reason: 'the refresh schedules the next one',
    );
    await firestore.terminate();
    expect(firestore.scheduler.getTask(TaskId.clientMetadataRefresh), isNull);
  });

  test('a memory cache is always primary', () async {
    final FirebaseApp app = newApp('memory-${const Uuid().v4()}');
    addTearDown(app.delete);
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(firestore.terminate);
    await firestore.waitForPendingWrites();
    expect(firestore.client.isPrimaryClient, isTrue);
    expect(firestore.scheduler.getTask(TaskId.clientMetadataRefresh), isNull);
  });

  test('two instances on one cache: the newer one is primary, both work, '
      'the lease comes back when it terminates', () async {
    final Firestore first = await open('first');
    expect(first.client.isPrimaryClient, isTrue);

    final Firestore second = await open('second');
    expect(second.client.isPrimaryClient, isTrue);
    await refresh(first);
    expect(first.client.isPrimaryClient, isFalse);

    // Both keep working on the cache, as before stage 1.
    first.doc('col/a').set(<String, Object?>{'by': 'first'}).ignore();
    second.doc('col/b').set(<String, Object?>{'by': 'second'}).ignore();
    expect((await first.doc('col/a').get(Source.cache)).data, <String, Object?>{
      'by': 'first',
    });
    expect(
      (await second.doc('col/b').get(Source.cache)).data,
      <String, Object?>{'by': 'second'},
    );

    await second.terminate();
    await refresh(first);
    expect(first.client.isPrimaryClient, isTrue);
  });

  test('only the primary uses the network, collects garbage and backfills '
      'indexes', () async {
    final Firestore first = await open('first');
    expect(actsAsPrimary(first), isTrue);

    final Firestore second = await open('second');
    await refresh(first);
    expect(first.client.isPrimaryClient, isFalse);
    expect(actsAsPrimary(first), isFalse);
    expect(actsAsPrimary(second), isTrue);

    // The secondary still serves its listeners and gets from the cache, and keeps its writes.
    first.doc('col/a').set(<String, Object?>{'by': 'first'}).ignore();
    final QuerySnapshot<Map<String, Object?>> snapshot = await first
        .collection('col')
        .get();
    expect(snapshot.metadata.isFromCache, isTrue);
    expect(
      snapshot.docs.map((DocumentSnapshot<Map<String, Object?>> d) => d.id),
      <String>['a'],
    );
    final QuerySnapshot<Map<String, Object?>> listened = await first
        .collection('col')
        .snapshots
        .first;
    expect(listened.docs, hasLength(1));
    // The listener is gone (first): unlistening on a secondary releases the target in memory only.
    await refresh(first);
    expect(actsAsPrimary(first), isFalse);

    await second.terminate();
    await refresh(first);
    expect(first.client.isPrimaryClient, isTrue);
    expect(actsAsPrimary(first), isTrue);
  });

  test(
    'becoming primary does not enable a network that the user disabled',
    () async {
      final Firestore first = await open('first');
      await first.disableNetwork();
      // Without another client, a client without network stays primary.
      await refresh(first);
      expect(first.client.isPrimaryClient, isTrue);

      final Firestore second = await open('second');
      await refresh(first);
      expect(first.client.isPrimaryClient, isFalse);
      await second.terminate();
      await refresh(first);
      expect(first.client.isPrimaryClient, isTrue);
      expect(first.client.syncEngine.isPrimaryClient, isTrue);
      expect(first.client.remoteStore.canUseNetwork, isFalse);

      await first.enableNetwork();
      expect(first.client.remoteStore.canUseNetwork, isTrue);
    },
  );

  test(
    'disabling the network gives the lease to an instance with network',
    () async {
      final Firestore first = await open('first');
      final Firestore second = await open('second');
      await refresh(first);
      expect(first.client.isPrimaryClient, isFalse);

      await second.disableNetwork();
      expect(second.client.isPrimaryClient, isFalse);
      await refresh(first);
      expect(first.client.isPrimaryClient, isTrue);

      await second.enableNetwork();
      await refresh(second);
      expect(second.client.isPrimaryClient, isFalse);
      expect(first.client.isPrimaryClient, isTrue);
    },
  );

  test('clearPersistence with another instance alive empties the cache in '
      'place, and the other instance terminates', () async {
    final Firestore first = await open('first');
    final Firestore other = await open('other');
    first.doc('col/a').set(<String, Object?>{'v': 1}).ignore();
    await first.doc('col/a').get(Source.cache);

    await first.terminate();
    await first.clearPersistence();
    expect(DatabaseMock.pathForName(dbName).existsSync(), isTrue);

    // The other instance notices at its next refresh (or transaction) and terminates.
    other.scheduler.runUntil(TaskId.clientMetadataRefresh);
    await pumpEventQueue();
    for (int i = 0; i < 100 && !other.client.isTerminated; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(other.client.isTerminated, isTrue);
    await expectLater(
      other.doc('col/a').get(Source.cache),
      throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)),
    );

    // A new instance starts on the emptied cache.
    final Firestore again = await open('again');
    expect(again.client.isPrimaryClient, isTrue);
    await expectLater(
      again.doc('col/a').get(Source.cache),
      throwsA(firestoreErrorWithCode(FirestoreErrorCode.unavailable)),
    );
  });

  test('clearPersistence without another instance deletes the file', () async {
    final Firestore first = await open('first');
    await first.terminate();
    await first.clearPersistence();
    expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);
  });

  test('the client id is unique per instance', () async {
    final Firestore first = await open('first');
    final Firestore second = await open('second');
    final List<Map<String, dynamic>> rows =
        await (first.client.persistence as SQLitePersistence).query(
          'SELECT client_id FROM clients',
        );
    expect(
      rows.map((Map<String, dynamic> row) => row['client_id']).toSet(),
      hasLength(2),
    );
    expect(
      (second.client.persistence as SQLitePersistence).clientMetadata.clientId,
      isNot(
        (first.client.persistence as SQLitePersistence).clientMetadata.clientId,
      ),
    );
  });
}
