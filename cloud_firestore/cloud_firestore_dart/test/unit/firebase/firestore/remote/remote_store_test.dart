// File created by
// Lung Razvan <long1eu>
// on 13/03/2020

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock_datastore.dart';

// ignore_for_file: cascade_invocations
void main() {
  test('testRemoteStoreStreamStopsWhenNetworkUnreachable', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);
    final Persistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();

    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final MockRemoteStoreCallback callback = MockRemoteStoreCallback();
    final RemoteStore remoteStore = RemoteStore(
        callback, localStore, datastore, onNetworkConnected, scheduler);

    // An active listen and a pending write, so that both streams are in use.
    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b']))
    ]);
    await remoteStore.start();
    await remoteStore
        .listen(QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(datastore.writesSent, 1);
    expect(datastore.isWatchStreamOpen, isTrue);
    final int watchRequests = datastore.watchStreamRequestCount;
    final int writeRequests = datastore.writeStreamRequestCount;

    // The network becomes unreachable: nothing happens until it is reachable again.
    await remoteStore.onNetworkConnectivityChanged(false);
    expect(datastore.watchStreamRequestCount, watchRequests);
    expect(datastore.writeStreamRequestCount, writeRequests);

    // When it is reachable again, both streams are torn down and set up again: the target is watched again and the
    // pending write is sent again.
    await remoteStore.onNetworkConnectivityChanged(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(datastore.isWatchStreamOpen, isTrue);
    expect(datastore.watchStreamRequestCount, greaterThan(watchRequests));
    expect(datastore.writeStreamRequestCount, greaterThan(writeRequests));
    expect(datastore.writesSent, 1);
    expect(datastore.activeTargets.keys, <int>[2]);

    await remoteStore.shutdown();
    await onNetworkConnected.close();
  });

  test('the empty write stream token is empty', () {
    expect(WriteStream.emptyStreamToken, isEmpty);
  });

  test('a connectivity change resets the backoff of the streams', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore datastore = MockDatastore(scheduler);
    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);
    final Persistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final RemoteStore remoteStore = RemoteStore(
      MockRemoteStoreCallback(),
      LocalStore(persistence, User.unauthenticated),
      datastore,
      onNetworkConnected,
      scheduler,
      networkDebounce: Duration.zero,
    );
    await remoteStore.enableNetwork();

    // Android calls inhibitBackoff() on both streams, otherwise a stream that
    // is waiting for its backoff would delay the reconnection.
    onNetworkConnected.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(datastore.watchStreamInhibitBackoffCount, 1);
    expect(datastore.writeStreamInhibitBackoffCount, 1);

    await remoteStore.shutdown();
    await onNetworkConnected.close();
  });
}

class MockRemoteStoreCallback implements RemoteStoreCallback {
  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {}

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {}

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult successfulWrite) async {}

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {}

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {}

  @override
  ImmutableSortedSet<DocumentKey> Function(int targetId)
      get getRemoteKeysForTarget => (int targetId) => DocumentKey.emptyKeySet;
}
