// `mergeUnsentWrites` through the sync engine and the remote store, with a mock backend: what is sent after a time
// offline, and what happens to the future of every write that was merged.

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
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

Future<void> _settle() async {
  // The mock streams open and answer on timers: give them real time.
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late String name;
  late SQLitePersistence persistence;
  late LocalStore localStore;
  late MockDatastore datastore;
  late RemoteStore remoteStore;
  late SyncEngine syncEngine;
  late SerialQueue queue;

  Future<void> start({required bool merge}) async {
    name = 'firebase/firestore/core/merge_unsent_${const Uuid().v4()}';
    persistence = await createSharedSQLitePersistenceForProject(
      'test-project',
      name,
      'client',
      () => 1700000000000,
      exclusive: true,
      leaseMode: PrimaryLeaseMode.forceOwnership,
    );
    localStore = LocalStore(persistence, User.unauthenticated)
      ..mergeUnsentWrites = merge;
    final TaskScheduler scheduler = TaskScheduler('client');
    datastore = MockDatastore(scheduler);
    final _Callback callback = _Callback();
    queue = SerialQueue();
    remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
      queue: queue,
    );
    syncEngine = SyncEngine(localStore, remoteStore, User.unauthenticated);
    callback.syncEngine = syncEngine;
    EventManager(syncEngine);
    await queue.run<void>(() async {
      await localStore.start();
      await remoteStore.start();
    });
    await _settle();
  }

  tearDown(() async {
    await remoteStore.shutdown();
    await persistence.shutdown();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  /// Writes [mutation]; the returned list gets 'done' or the error once the future of the write completes.
  Future<List<Object>> write(Mutation mutation) async {
    final Completer<void> userTask = Completer<void>();
    final List<Object> outcome = <Object>[];
    unawaited(
      userTask.future.then<void>(
        (_) => outcome.add('done'),
        onError: (Object error) => outcome.add(error),
      ),
    );
    await queue.run<void>(
      () => syncEngine.writeMutations(<Mutation>[mutation], userTask),
    );
    return outcome;
  }

  Future<List<Object>> waitForPendingWrites() async {
    final Completer<void> task = Completer<void>();
    final List<Object> outcome = <Object>[];
    unawaited(task.future.then<void>((_) => outcome.add('done')));
    await queue.run<void>(() => syncEngine.registerPendingWritesTask(task));
    return outcome;
  }

  Future<void> goOffline() async {
    await queue.run<void>(remoteStore.disableNetwork);
    await _settle();
  }

  Future<void> goOnline() async {
    await queue.run<void>(remoteStore.enableNetwork);
    await _settle();
  }

  Future<void> acknowledge(int commitVersion) async {
    await datastore.ackWrite(version(commitVersion), <MutationResult>[
      MutationResult(version(commitVersion), const <FieldValue>[]),
    ]);
    await _settle();
  }

  Mutation setA(int i) => setMutation('col/a', <String, Object?>{'i': i});
  Mutation setB(int i) => setMutation('col/b', <String, Object?>{'i': i});

  test(
    'writes made offline are sent as one write per document, and every future completes',
    () async {
      await start(merge: true);
      await goOffline();

      final List<List<Object>> outcomesA = <List<Object>>[];
      final List<List<Object>> outcomesB = <List<Object>>[];
      late List<Object> waiting;
      late Mutation lastA;
      late Mutation lastB;
      for (int i = 0; i < 30; i++) {
        outcomesA.add(await write(lastA = setA(i)));
        if (i == 10) {
          waiting = await waitForPendingWrites();
        }
        if (i < 20) {
          outcomesB.add(await write(lastB = setB(i)));
        }
      }
      await _settle();
      expect(
        outcomesA.followedBy(outcomesB).expand((List<Object> o) => o),
        isEmpty,
      );
      expect(
        (await localStore.readDocument(key('col/a')))!.hasPendingWrites,
        isTrue,
      );

      await goOnline();
      // The queue order is that of the last write of each document: b (written last at i = 19), then a.
      expect(datastore.writesSent, 2);
      expect(datastore.waitForWriteSend(), <Mutation>[lastB]);
      expect(datastore.waitForWriteSend(), <Mutation>[lastA]);

      await acknowledge(10);
      expect(outcomesB, everyElement(<Object>['done']));
      expect(outcomesA.expand((List<Object> o) => o), isEmpty);
      expect(
        waiting,
        isEmpty,
        reason: 'the write of a it waits for is not acknowledged yet',
      );

      await acknowledge(20);
      expect(outcomesA, everyElement(<Object>['done']));
      expect(waiting, <Object>['done']);
      expect(datastore.writesSent, 0);
      expect(
        ((await localStore.readDocument(key('col/a')))! as Document)
            .hasLocalMutations,
        // Acknowledged; only the watch stream has not delivered it yet.
        isFalse,
      );
    },
  );

  test('a rejection fails every write that was merged', () async {
    await start(merge: true);
    await goOffline();
    final List<List<Object>> outcomes = <List<Object>>[
      for (int i = 0; i < 3; i++) await write(setA(i)),
    ];
    await goOnline();
    expect(datastore.writesSent, 1);

    await datastore.failWrite(GrpcError.permissionDenied('no'));
    await _settle();
    for (final List<Object> outcome in outcomes) {
      expect(outcome.single, isNot('done'));
    }
    expect(await localStore.readDocument(key('col/a')), isNull);
  });

  test('writes handed to the write stream are not merged', () async {
    await start(merge: true);
    final List<List<Object>> outcomes = <List<Object>>[
      for (int i = 0; i < 3; i++) await write(setA(i)),
    ];
    await _settle();
    expect(datastore.writesSent, 3);
    for (int i = 0; i < 3; i++) {
      await acknowledge(10 + i);
    }
    expect(outcomes, everyElement(<Object>['done']));
  });

  test('nothing is merged without the setting', () async {
    await start(merge: false);
    await goOffline();
    for (int i = 0; i < 3; i++) {
      await write(setA(i));
    }
    await goOnline();
    expect(datastore.writesSent, 3);
  });
}
