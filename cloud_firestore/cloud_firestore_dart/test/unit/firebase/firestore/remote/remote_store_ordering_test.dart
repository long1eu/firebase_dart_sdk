import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock_datastore.dart';

/// Records when each callback of the remote store starts and ends. Every callback takes a while to complete, like
/// the real ones that talk to the local store.
class _SlowCallback implements RemoteStoreCallback {
  _SlowCallback({this.delay = const Duration(milliseconds: 20)});

  final Duration delay;
  final List<String> events = <String>[];

  Future<void> _slow(String name) async {
    events.add('$name:start');
    await Future<void>.delayed(delay);
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

  test('a listen while the watch stream opens is sent to the backend once',
      () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> connected = BehaviorSubject<bool>.seeded(true);
    addTearDown(connected.close);
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final RemoteStore remoteStore = RemoteStore(
        _SlowCallback(), localStore, datastore, connected, scheduler);
    await remoteStore.start();

    // The first listen starts the watch stream; the second one comes after the stream is open but before the
    // remote store handled the open event, which sends every target it listens to. The backend fails the stream
    // when a target is added twice.
    final Future<void> first = remoteStore
        .listen(QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen));
    final Future<void> second = remoteStore
        .listen(QueryData(query('bar').toTarget(), 4, 1, QueryPurpose.listen));
    await Future.wait(<Future<void>>[first, second]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(datastore.activeTargets, hasLength(2));
    expect(datastore.watchStreamRequestCount, 2);
  });

  test(
      'a write stream that fails before its handshake is handled gets no '
      'writes', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> connected = BehaviorSubject<bool>.seeded(true);
    addTearDown(connected.close);
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    // Every watch snapshot keeps the queue of the remote store busy for a while.
    final _SlowCallback callback =
        _SlowCallback(delay: const Duration(milliseconds: 200));
    final RemoteStore remoteStore =
        RemoteStore(callback, localStore, datastore, connected, scheduler);
    Future<void> watchSnapshot() => datastore.writeWatchChange(
        WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[],
            Uint8List.fromList(<int>[1, 2, 3])),
        version(10));

    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b']))
    ]);
    await remoteStore.start();
    await remoteStore
        .listen(QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(datastore.writesSent, 1);

    // The write stream fails and is restarted while a snapshot is handled; a second snapshot comes after the open
    // event of the new stream, so that the report of its handshake waits behind it.
    await datastore.failWrite(const GrpcError.unavailable());
    await watchSnapshot();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await watchSnapshot();
    // The new stream sent its handshake (after the first snapshot), and fails while the second snapshot is handled.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final int requestsBeforeFailure = datastore.writeStreamRequestCount;
    await datastore.failWrite(const GrpcError.unavailable());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Only the stream started after the second failure got requests: its handshake and the write.
    expect(datastore.writeStreamRequestCount - requestsBeforeFailure, 2);
    expect(datastore.writesSent, 1);
  });
}
