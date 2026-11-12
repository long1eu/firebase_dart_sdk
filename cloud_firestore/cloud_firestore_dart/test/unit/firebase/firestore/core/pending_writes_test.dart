// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:grpc/grpc.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class _FakeRemoteStore extends Fake implements RemoteStore {
  @override
  bool canUseNetwork = true;

  @override
  Future<void> fillWritePipeline() async {}

  @override
  Future<void> handleCredentialChange() async {}
}

class _NoopCallback implements SyncEngineCallback {
  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {}

  @override
  void onError(Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

void main() {
  late MemoryPersistence persistence;
  late LocalStore localStore;
  late SyncEngine syncEngine;

  setUp(() async {
    persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    syncEngine =
        SyncEngine(localStore, _FakeRemoteStore(), User.unauthenticated)
          ..syncEngineListener = _NoopCallback();
  });

  tearDown(() => persistence.shutdown());

  Future<void> writeLocally(String path) {
    final Completer<void> writeTask = Completer<void>();
    // A rejected write fails its task; the tests only look at the pending writes tasks.
    writeTask.future.catchError((Object _) {});
    return syncEngine.writeMutations(<Mutation>[
      setMutation(path, map(<String>['a', 'b']))
    ], writeTask);
  }

  Future<MutationBatchResult> resultOfNextBatch() async {
    final MutationBatch batch =
        (await localStore.getNextMutationBatch(MutationBatch.unknown))!;
    return MutationBatchResult.create(
        batch,
        version(10),
        <MutationResult>[MutationResult(version(10), <FieldValue>[])],
        Uint8List(0));
  }

  test('a pending writes task completes right away without pending writes',
      () async {
    final Completer<void> task = Completer<void>();
    await syncEngine.registerPendingWritesTask(task);
    expect(task.isCompleted, isTrue);
  });

  test('a pending writes task completes when the pending write is acknowledged',
      () async {
    await writeLocally('foo/bar');

    final Completer<void> task = Completer<void>();
    await syncEngine.registerPendingWritesTask(task);
    expect(task.isCompleted, isFalse);

    await syncEngine.handleSuccessfulWrite(await resultOfNextBatch());
    expect(task.isCompleted, isTrue);
  });

  test('a pending writes task waits for the last write that was pending',
      () async {
    await writeLocally('foo/a');
    final Completer<void> task = Completer<void>();
    await syncEngine.registerPendingWritesTask(task);
    // A write that is made later does not matter to the task.
    await writeLocally('foo/b');

    await syncEngine.handleSuccessfulWrite(await resultOfNextBatch());
    expect(task.isCompleted, isTrue);
  });

  test('a pending writes task completes when the pending write is rejected',
      () async {
    await writeLocally('foo/bar');
    final Completer<void> task = Completer<void>();
    await syncEngine.registerPendingWritesTask(task);

    final MutationBatch batch =
        (await localStore.getNextMutationBatch(MutationBatch.unknown))!;
    await syncEngine.handleRejectedWrite(
        batch.batchId, const GrpcError.permissionDenied());
    expect(task.isCompleted, isTrue);
  });

  test('a pending writes task fails when the user changes', () async {
    await writeLocally('foo/bar');
    final Completer<void> task = Completer<void>();
    await syncEngine.registerPendingWritesTask(task);
    final Future<void> outcome = task.future;
    final Future<void> expectation = expectLater(
        outcome,
        throwsA(isA<FirestoreError>()
            .having((FirestoreError e) => e.code, 'code',
                FirestoreErrorCode.cancelled)
            .having((FirestoreError e) => e.message, 'message',
                "'waitForPendingWrites' task is cancelled due to User change.")));

    await syncEngine.handleCredentialChange(const User('new user'));
    await expectation;
  });
}
