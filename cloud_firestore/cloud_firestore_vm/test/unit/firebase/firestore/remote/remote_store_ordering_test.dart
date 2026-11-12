import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock_datastore.dart';

/// Records when each callback of the remote store starts and ends. Every callback takes a while to complete, like
/// the real ones that talk to the local store.
class _SlowCallback implements RemoteStoreCallback {
  final List<String> events = <String>[];

  Future<void> _slow(String name) async {
    events.add('$name:start');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.add('$name:end');
  }

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) => _slow('watch');

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult successfulWrite) =>
      _slow('ack');

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {}

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {}

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {}

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget => (int targetId) => DocumentKey.emptyKeySet;
}

void main() {
  test(
      'write acks and watch snapshots are handled one at a time, in arrival order',
      () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> connected = BehaviorSubject<bool>.seeded(true);
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final _SlowCallback callback = _SlowCallback();
    final RemoteStore remoteStore =
        RemoteStore(callback, localStore, datastore, connected, scheduler);

    // A pending write and an active listen, so that both streams are in use.
    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b']))
    ]);
    await remoteStore.start();
    await remoteStore
        .listen(QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(datastore.writesSent, 1);

    // The backend answers on both streams back to back: first the write ack, then a global watch snapshot.
    await datastore.ackWrite(version(10),
        <MutationResult>[MutationResult(version(10), <FieldValue>[])]);
    await datastore.writeWatchChange(
        WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[],
            Uint8List.fromList(<int>[1, 2, 3])),
        version(10));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(callback.events, <String>[
      'ack:start',
      'ack:end',
      'watch:start',
      'watch:end',
    ]);
  });

  test('concurrent fillWritePipeline calls add a batch to the pipeline once',
      () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> connected = BehaviorSubject<bool>.seeded(true);
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final RemoteStore remoteStore = RemoteStore(
        _SlowCallback(), localStore, datastore, connected, scheduler);
    await remoteStore.start();

    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b']))
    ]);

    // The sync engine and the write stream handlers can both ask for a refill at the same time.
    await Future.wait(<Future<void>>[
      remoteStore.fillWritePipeline(),
      remoteStore.fillWritePipeline(),
      remoteStore.fillWritePipeline(),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(datastore.writesSent, 1);
  });

  test('a network reachability change does not undo disableNetwork', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> connected = BehaviorSubject<bool>.seeded(true);
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final RemoteStore remoteStore = RemoteStore(
        _SlowCallback(), localStore, datastore, connected, scheduler);
    await remoteStore.start();

    await remoteStore.disableNetwork();
    await remoteStore.onNetworkConnectivityChanged(true);

    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b']))
    ]);
    await remoteStore.fillWritePipeline();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // The user disabled the network: nothing is sent.
    expect(datastore.writesSent, 0);
    expect(datastore.writeStreamRequestCount, 0);

    await remoteStore.enableNetwork();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(datastore.writesSent, 1);
  });
}
