// File created by
// Lung Razvan <long1eu>
// on 13/03/2020

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';

// ignore_for_file: cascade_invocations
void main() {
  test('testRemoteStoreStreamStopsWhenNetworkUnreachable', () async {
    final AsyncQueue scheduler = AsyncQueue('');
    final Datastore datastore = Datastore(
      scheduler,
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);
    final Persistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();

    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final MockRemoteStoreCallback callback = MockRemoteStoreCallback();
    when(callback.handleOnlineStateChange(any)).thenAnswer((_) async => null);

    final RemoteStore remoteStore = RemoteStore(
        callback, localStore, datastore, onNetworkConnected, scheduler);

    remoteStore.forceEnableNetwork();
    onNetworkConnected.add(false);
    remoteStore.forceEnableNetwork();
    onNetworkConnected.add(true);
    await onNetworkConnected.close();
  });
}

class MockRemoteStoreCallback extends Mock implements RemoteStoreCallback {}
