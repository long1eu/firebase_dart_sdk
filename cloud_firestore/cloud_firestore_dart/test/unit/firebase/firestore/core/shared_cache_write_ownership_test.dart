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

// Two clients on one SQLite cache that do not share state (as two Firestore instances do today): the primary sends
// only its own batches and those of clients that are gone, so that the client that wrote a batch learns its result
// (notes/reviews/final_review_today.md, finding 1).

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';
import '../remote/mock_datastore.dart';

/// Forwards the callbacks of a remote store to the sync engine, which is created after it.
class _Callback implements RemoteStoreCallback {
  late SyncEngine syncEngine;

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) =>
      syncEngine.handleRemoteEvent(remoteEvent);

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) =>
      syncEngine.handleRejectedListen(targetId, error);

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult result) =>
      syncEngine.handleSuccessfulWrite(result);

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) =>
      syncEngine.handleRejectedWrite(batchId, error);

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      syncEngine.handleOnlineStateChange(onlineState);

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      syncEngine.getRemoteKeysForTarget;
}

/// A client stack (as a Firestore instance builds it, without shared client state) on the shared cache.
class _Client {
  _Client._(
    this.persistence,
    this.datastore,
    this.remoteStore,
    this.syncEngine,
  );

  static Future<_Client> start(
    String name,
    String clientId,
    int Function() clock,
  ) async {
    final SQLitePersistence persistence =
        await createSharedSQLitePersistenceForProject(
          'test-project',
          name,
          clientId,
          clock,
        );
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final TaskScheduler scheduler = TaskScheduler(clientId);
    final MockDatastore datastore = MockDatastore(scheduler);
    final _Callback callback = _Callback();
    final RemoteStore remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
    );
    final SyncEngine syncEngine = SyncEngine(
      localStore,
      remoteStore,
      User.unauthenticated,
    );
    callback.syncEngine = syncEngine;
    EventManager(syncEngine);
    await localStore.start();
    // As the client: the primary state is applied after the transaction that changed it.
    persistence.setPrimaryStateListener((bool isPrimary) {
      scheduleMicrotask(() => syncEngine.applyPrimaryState(isPrimary));
    });
    await _settle();
    await remoteStore.start();
    await _settle();
    return _Client._(persistence, datastore, remoteStore, syncEngine)
      ..scheduler = scheduler;
  }

  final SQLitePersistence persistence;
  final MockDatastore datastore;
  final RemoteStore remoteStore;
  final SyncEngine syncEngine;
  late final TaskScheduler scheduler;
  bool _shutDown = false;

  /// Writes [mutation] and returns the future of the user (completed by the acknowledgement).
  Future<void> write(Mutation mutation) async {
    final Completer<void> userTask = Completer<void>();
    await syncEngine.writeMutations(<Mutation>[mutation], userTask);
    await _settle();
    return userTask.future;
  }

  Future<void> refresh() async {
    await persistence.refreshClientMetadata();
    await _settle();
  }

  /// The backend acknowledges the oldest write in flight, which must be [expected].
  Future<void> acknowledge(Mutation expected, int commitVersion) async {
    expect(datastore.waitForWriteSend(), <Mutation>[expected]);
    await datastore.ackWrite(version(commitVersion), <MutationResult>[
      MutationResult(version(commitVersion), const <FieldValue>[]),
    ]);
    await _settle();
  }

  Future<void> shutdown() async {
    if (_shutDown) {
      return;
    }
    _shutDown = true;
    await remoteStore.shutdown();
    await persistence.shutdown();
  }
}

/// Waits until [datastore] sent [count] writes that were not acknowledged yet, then a little longer, and checks that
/// it sent exactly [count].
Future<void> _expectSent(MockDatastore datastore, int count) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (datastore.writesSent < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await _settle();
  expect(datastore.writesSent, count);
}

Future<void> _settle() async {
  // The mock streams open and answer on timers: give them real time.
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late String name;
  late int now;
  int clock() => now;
  final List<_Client> clients = <_Client>[];

  setUp(() {
    name = 'firebase/firestore/core/write_ownership_${const Uuid().v4()}';
    now = 1700000000000;
    clients.clear();
  });

  tearDown(() async {
    for (final _Client client in clients) {
      await client.shutdown();
    }
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<_Client> start(String clientId) async {
    final _Client client = await _Client.start(name, clientId, clock);
    clients.add(client);
    return client;
  }

  test(
    'the primary does not send the batch of a secondary; the secondary sends it once primary',
    () async {
      final _Client b = await start('B');
      final _Client a = await start('A');
      expect(b.syncEngine.isPrimaryClient, isTrue);
      expect(a.syncEngine.isPrimaryClient, isFalse);

      final Mutation writeA = setMutation('col/a', <String, Object?>{
        'by': 'A',
      });
      final Mutation writeB = setMutation('col/b', <String, Object?>{
        'by': 'B',
      });

      bool aDone = false;
      final Future<void> aWritten = a.write(writeA)..then((_) => aDone = true);
      expect(a.datastore.writesSent, 0, reason: 'a secondary sends nothing');

      final Future<void> bWritten = b.write(writeB);
      // B sends its own batch only (before the fix it sent A's batch first).
      await _expectSent(b.datastore, 1);
      expect(a.datastore.writesSent, 0);

      // B's waitForPendingWrites waits for B's own batch, not for A's.
      bool bPendingDone = false;
      final Completer<void> bPending = Completer<void>();
      await b.syncEngine.registerPendingWritesTask(bPending);
      unawaited(bPending.future.then((_) => bPendingDone = true));

      await b.acknowledge(writeB, 1000);
      await bWritten;
      expect(bPendingDone, isTrue);
      expect(b.datastore.writesSent, 0, reason: 'A\'s batch is still not sent');
      expect(aDone, isFalse);

      // B terminates (it releases the lease and removes its metadata): A becomes primary at its next refresh and
      // sends its batch, and A's future completes with the acknowledgement.
      await b.shutdown();
      await a.refresh();
      expect(a.syncEngine.isPrimaryClient, isTrue);
      await _expectSent(a.datastore, 1);
      await a.acknowledge(writeA, 2000);
      await aWritten;
      expect(aDone, isTrue);
    },
  );

  test('the primary sends the batch of a client that is gone', () async {
    final _Client b = await start('B');
    final _Client c = await start('C');
    expect(c.syncEngine.isPrimaryClient, isFalse);

    final Mutation writeC = setMutation('col/c', <String, Object?>{'by': 'C'});
    final Mutation writeB = setMutation('col/b', <String, Object?>{'by': 'B'});
    unawaited(c.write(writeC));
    expect(c.datastore.writesSent, 0);

    // C stops refreshing (it crashed): once its metadata is older than the batch owner age (60 s), its batch is sent
    // by the primary, which refreshed its own lease meanwhile.
    expect(SQLiteClientMetadata.maxBatchOwnerAgeMs, 60000);
    now += SQLiteClientMetadata.maxBatchOwnerAgeMs + 1;
    await b.refresh();
    expect(b.syncEngine.isPrimaryClient, isTrue);

    final Future<void> bWritten = b.write(writeB);
    await _expectSent(b.datastore, 2);
    await b.acknowledge(writeC, 1000);
    await b.acknowledge(writeB, 2000);
    await bWritten;
  });

  test(
    'after a refresh, the primary sends the batch of a client that is gone without writing itself',
    () async {
      final _Client b = await start('B');
      final _Client c = await start('C');
      final Mutation writeC = setMutation('col/c', <String, Object?>{
        'by': 'C',
      });
      unawaited(c.write(writeC));
      expect(c.datastore.writesSent, 0);

      // C crashed. B's next refresh (as the client runs it every 4 s) makes B send C's batch.
      now += SQLiteClientMetadata.maxBatchOwnerAgeMs + 1;
      await b.refresh();
      await b.syncEngine.handleClientMetadataRefresh();
      await _expectSent(b.datastore, 1);
      await b.acknowledge(writeC, 1000);
    },
  );

  test('the fill after a refresh does nothing without batches to send', () async {
    final _Client b = await start('B');

    // An idle client: no write stream is opened, however often the metadata is refreshed.
    for (int i = 0; i < 3; i++) {
      await b.refresh();
      await b.syncEngine.handleClientMetadataRefresh();
    }
    await _settle();
    expect(b.datastore.writeStreamRequestCount, 0);
    expect(b.scheduler.getTask(TaskId.writeStreamIdle), isNull);

    // After a write the stream is open and idle: the fills do not send anything and do not restart its idle timer
    // (the stream would never close with a refresh every 4 s).
    final Mutation writeB = setMutation('col/b', <String, Object?>{'by': 'B'});
    final Future<void> bWritten = b.write(writeB);
    await _expectSent(b.datastore, 1);
    await b.acknowledge(writeB, 1000);
    await bWritten;
    final int requests = b.datastore.writeStreamRequestCount;
    final TimerTask? idleTimer = b.scheduler.getTask(TaskId.writeStreamIdle);
    expect(idleTimer, isNotNull);
    for (int i = 0; i < 3; i++) {
      await b.refresh();
      await b.syncEngine.handleClientMetadataRefresh();
    }
    await _settle();
    expect(b.datastore.writeStreamRequestCount, requests);
    expect(b.datastore.writesSent, 0);
    expect(b.scheduler.getTask(TaskId.writeStreamIdle), same(idleTimer));
  });

  test('a client that refreshed 30 s ago keeps its batch', () async {
    final _Client b = await start('B');
    final _Client c = await start('C');
    final Mutation writeC = setMutation('col/c', <String, Object?>{'by': 'C'});
    final Mutation writeB = setMutation('col/b', <String, Object?>{'by': 'B'});
    unawaited(c.write(writeC));

    // C refreshed its metadata 30 s ago (a slow refresh, a short stall): it is alive, B does not send its batch.
    now += 30000;
    await b.refresh();
    expect(b.syncEngine.isPrimaryClient, isTrue);
    final Future<void> bWritten = b.write(writeB);
    await _expectSent(b.datastore, 1);
    await b.acknowledge(writeB, 1000);
    await bWritten;
    expect(b.datastore.writesSent, 0);
  });

  test('a batch written before schema 18 (no owner) is sent', () async {
    final _Client b = await start('B');
    final _Client a = await start('A');
    final Mutation writeA = setMutation('col/a', <String, Object?>{'by': 'A'});
    unawaited(a.write(writeA));
    // Once A's batch is stored: as a row of an older cache.
    await _settle();
    expect(
      await b.persistence.query('SELECT client_id FROM mutations'),
      <Map<String, dynamic>>[
        <String, dynamic>{'client_id': 'A'},
      ],
    );
    await b.persistence.execute('UPDATE mutations SET client_id = NULL');

    final Mutation writeB = setMutation('col/b', <String, Object?>{'by': 'B'});
    final Future<void> bWritten = b.write(writeB);
    await _expectSent(b.datastore, 2);
    await b.acknowledge(writeA, 1000);
    await b.acknowledge(writeB, 2000);
    await bWritten;
  });
}
