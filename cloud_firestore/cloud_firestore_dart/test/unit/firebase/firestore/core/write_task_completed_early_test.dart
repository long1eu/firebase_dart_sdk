// FirestoreClient.write fails the task of a write with any error of the queued work (b61e2b58). When that error
// comes after the batch was stored (here: filling the write pipeline fails), the batch is still sent, and its
// acknowledgement or rejection must not complete the task a second time (StateError: Future already completed,
// thrown into the handling of the acknowledgement).

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

class _FailingFillRemoteStore extends Fake implements RemoteStore {
  @override
  bool canUseNetwork = true;

  @override
  Future<void> fillWritePipeline() async {
    throw FirestoreError('fill failed', FirestoreErrorCode.failedPrecondition);
  }

  @override
  Future<void> enqueueRetryable(Future<void> Function() operation) =>
      operation();
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
    syncEngine = SyncEngine(
      localStore,
      _FailingFillRemoteStore(),
      User.unauthenticated,
    )..syncEngineListener = _NoopCallback();
  });

  tearDown(() => persistence.shutdown());

  /// Writes like FirestoreClient.write: an error of the queued work fails the task of the write.
  Future<Completer<void>> write() async {
    final Completer<void> task = Completer<void>();
    unawaited(task.future.catchError((Object _) {}));
    try {
      await syncEngine.writeMutations(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ], task);
    } catch (e) {
      if (!task.isCompleted) {
        task.completeError(e);
      }
    }
    return task;
  }

  Future<MutationBatch> nextBatch() async =>
      (await localStore.getNextMutationBatch(MutationBatch.unknown))!;

  test(
    'an acknowledgement after the task failed does not complete it again',
    () async {
      final Completer<void> task = await write();
      expect(task.isCompleted, isTrue);
      await expectLater(task.future, throwsA(isA<FirestoreError>()));

      final MutationBatch batch = await nextBatch();
      await syncEngine.handleSuccessfulWrite(
        MutationBatchResult.create(batch, version(10), <MutationResult>[
          MutationResult(version(10), <FieldValue>[]),
        ], Uint8List(0)),
      );
      expect(
        await localStore.getNextMutationBatch(MutationBatch.unknown),
        isNull,
      );
    },
  );

  test(
    'a rejection after the task failed does not complete it again',
    () async {
      final Completer<void> task = await write();
      expect(task.isCompleted, isTrue);

      final MutationBatch batch = await nextBatch();
      await syncEngine.handleRejectedWrite(
        batch.batchId,
        const GrpcError.permissionDenied('no'),
      );
      expect(
        await localStore.getNextMutationBatch(MutationBatch.unknown),
        isNull,
      );
    },
  );
}
