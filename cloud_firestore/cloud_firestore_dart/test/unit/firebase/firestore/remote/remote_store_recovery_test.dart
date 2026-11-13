// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../local/persistence_fault_injector.dart';
import 'mock_datastore.dart';
import 'remote_store_test.dart' show MockRemoteStoreCallback;

/// How the [RemoteStore] recovers from a persistence that fails (the JS `disableNetworkUntilRecovery`,
/// `executeWithRecovery` and the credential change through `enqueueRetryable`). The JS SDK covers this only with the
/// recovery spec tests; these tests pin the single steps.
void main() {
  late TaskScheduler scheduler;
  late MockDatastore datastore;
  late BehaviorSubject<bool> onNetworkConnected;
  late MemoryPersistence persistence;
  late PersistenceFaultInjector faults;
  late LocalStore localStore;
  late _FailingCallback callback;
  late RemoteStore remoteStore;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// Runs the retry that waits for its backoff (at least half a second) right away.
  Future<void> runRetry() async {
    scheduler.runUntil(TaskId.asyncQueueRetry);
    await settle();
  }

  QueryData target() =>
      QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen);

  setUp(() async {
    scheduler = TaskScheduler('recovery-test');
    datastore = MockDatastore(scheduler);
    onNetworkConnected = BehaviorSubject<bool>.seeded(true);
    persistence = MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    faults = PersistenceFaultInjector(persistence);
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    callback = _FailingCallback();
    remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      onNetworkConnected,
      scheduler,
    );
    await remoteStore.start();
  });

  tearDown(() async {
    await remoteStore.shutdown();
    await onNetworkConnected.close();
  });

  test(
    'a write acknowledgement that can not be stored is stored by a retry, with the network offline meanwhile',
    () async {
      await localStore.writeLocally(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ]);
      await remoteStore.fillWritePipeline();
      await settle();
      expect(datastore.waitForWriteSend(), hasLength(1));

      callback.failWrites = true;
      await datastore.ackWrite(version(1), <MutationResult>[
        MutationResult(version(1), <FieldValue>[]),
      ]);
      await settle();

      expect(remoteStore.canUseNetwork, isFalse);
      expect(callback.successfulWrites, isEmpty);
      expect(callback.failedWriteAttempts, greaterThan(0));
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNotNull);

      callback.failWrites = false;
      await runRetry();

      // The same result is stored once, and the network is back.
      expect(callback.successfulWrites, hasLength(1));
      expect(callback.successfulWrites.single.commitVersion, version(1));
      expect(remoteStore.canUseNetwork, isTrue);
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
    },
  );

  test(
    'a write rejection that can not be stored is stored by a retry',
    () async {
      await localStore.writeLocally(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ]);
      await remoteStore.fillWritePipeline();
      await settle();
      expect(datastore.waitForWriteSend(), hasLength(1));

      callback.failWrites = true;
      await datastore.failWrite(
        const GrpcError.failedPrecondition('Simulated test error'),
      );
      await settle();
      expect(remoteStore.canUseNetwork, isFalse);
      expect(callback.rejectedWrites, isEmpty);

      callback.failWrites = false;
      await runRetry();
      expect(callback.rejectedWrites, hasLength(1));
      expect(remoteStore.canUseNetwork, isTrue);
    },
  );

  test(
    'a watch snapshot whose snapshot version can not be read takes the network offline until the persistence works',
    () async {
      await remoteStore.listen(target());
      await settle();
      final int remoteTargetId = remoteStore.getRemoteTargetId(2)!;
      expect(datastore.activeTargets.keys, <int>[remoteTargetId]);

      faults.failActions = <String>['Get last remote snapshot version'];
      await datastore.writeWatchChange(
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[
          remoteTargetId,
        ]),
        SnapshotVersion.none,
      );
      await datastore.writeWatchChange(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.current,
          <int>[remoteTargetId],
          Uint8List.fromList(utf8.encode('resume-token-1000')),
        ),
        SnapshotVersion.none,
      );
      await datastore.writeWatchChange(
        WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[]),
        version(1000),
      );
      await settle();

      // The snapshot is not raised, the streams are down, and the persistence is probed with a backoff.
      expect(callback.remoteEvents, isEmpty);
      expect(remoteStore.canUseNetwork, isFalse);
      expect(datastore.activeTargets, isEmpty);
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNotNull);

      // A probe while the persistence still fails keeps the network offline.
      await runRetry();
      expect(remoteStore.canUseNetwork, isFalse);

      faults.failActions = <String>[];
      await runRetry();
      expect(remoteStore.canUseNetwork, isTrue);
      // The target is listened to again, without the resume token of the snapshot that was not stored.
      expect(datastore.activeTargets.keys, <int>[remoteTargetId]);
      expect(datastore.activeTargets[remoteTargetId]!.resumeToken, isEmpty);
    },
  );

  test(
    'a listen rejection that can not be stored keeps the target, which is listened to again',
    () async {
      await remoteStore.listen(target());
      await settle();
      final int remoteTargetId = remoteStore.getRemoteTargetId(2)!;

      // The probe of the persistence (a read of the last remote snapshot version) fails too, as with the
      // ASYNC_QUEUE_PROBER of the JS recovery specs: otherwise the network would come back at once.
      callback.failRejectedListens = true;
      faults.failActions = <String>['Get last remote snapshot version'];
      await datastore.writeWatchChange(
        WatchChangeWatchTargetChange(
          WatchTargetChangeType.removed,
          <int>[remoteTargetId],
          null,
          const GrpcError.permissionDenied('Simulated target error'),
        ),
        SnapshotVersion.none,
      );
      await settle();
      expect(remoteStore.canUseNetwork, isFalse);
      expect(remoteStore.getRemoteTargetId(2), remoteTargetId);

      // Once the probe works, the network is back and the target is sent again, so that the backend rejects it
      // again.
      callback.failRejectedListens = false;
      faults.failActions = <String>[];
      await runRetry();
      expect(remoteStore.canUseNetwork, isTrue);
      expect(datastore.activeTargets.keys, <int>[remoteTargetId]);
      expect(callback.rejectedListens, isEmpty);
    },
  );

  test(
    'a credential change that can not be stored keeps the network offline and the changes after it wait',
    () async {
      await remoteStore.listen(target());
      await settle();

      bool failing = true;
      final List<String> switched = <String>[];
      Future<void> change(String uid) => remoteStore.enqueueRetryable(
        () => remoteStore.handleCredentialChange(() async {
          if (failing) {
            throw TransientDatabaseException('Simulated error');
          }
          switched.add(uid);
        }),
      );

      await change('user2');
      await settle();
      expect(remoteStore.canUseNetwork, isFalse);
      expect(datastore.activeTargets, isEmpty);

      await change('user1');
      await settle();
      expect(switched, isEmpty);
      expect(remoteStore.canUseNetwork, isFalse);

      failing = false;
      await runRetry();
      // Both changes are applied, in the order they were made, and the network is back.
      await settle();
      expect(switched, <String>['user2', 'user1']);
      expect(remoteStore.canUseNetwork, isTrue);
      expect(datastore.activeTargets, hasLength(1));
    },
  );

  test(
    'a credential change that fails with another error brings the network back',
    () async {
      await expectLater(
        remoteStore.enqueueRetryable(
          () => remoteStore.handleCredentialChange(
            () async => throw StateError('Simulated failure'),
          ),
        ),
        throwsStateError,
      );
      expect(remoteStore.canUseNetwork, isTrue);
      expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
    },
  );
}

/// Records what the [RemoteStore] reports, and fails on demand as a persistence that is not available would.
class _FailingCallback extends MockRemoteStoreCallback {
  bool failWrites = false;
  bool failRejectedListens = false;
  int failedWriteAttempts = 0;
  final List<MutationBatchResult> successfulWrites = <MutationBatchResult>[];
  final List<int> rejectedWrites = <int>[];
  final List<int> rejectedListens = <int>[];
  final List<RemoteEvent> remoteEvents = <RemoteEvent>[];

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    remoteEvents.add(remoteEvent);
  }

  @override
  Future<void> handleSuccessfulWrite(
    MutationBatchResult successfulWrite,
  ) async {
    if (failWrites) {
      failedWriteAttempts++;
      throw TransientDatabaseException('Simulated error');
    }
    successfulWrites.add(successfulWrite);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {
    if (failWrites) {
      throw TransientDatabaseException('Simulated error');
    }
    rejectedWrites.add(batchId);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    if (failRejectedListens) {
      throw TransientDatabaseException('Simulated error');
    }
    rejectedListens.add(targetId);
  }
}
