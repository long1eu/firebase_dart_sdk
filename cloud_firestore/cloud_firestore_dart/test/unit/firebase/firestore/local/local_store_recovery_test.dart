// File created by
// Lung Razvan <long1eu>
// on 13/11/2026

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_fault_injector.dart';
import 'persistence_test_helpers.dart';

/// The [LocalStore] when a transaction fails because the persistence is not available (the
/// `isIndexedDbTransactionError` branches of the JS `local_store_impl.ts`, which JS covers only with the recovery
/// spec tests): which failures are ignored, and which leave the in-memory state as it was.
void main() {
  late MemoryPersistence persistence;
  late PersistenceFaultInjector faults;
  late LocalStore localStore;

  setUp(() async {
    persistence = await createLRUMemoryPersistence();
    faults = PersistenceFaultInjector(persistence);
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
  });

  tearDown(() => persistence.shutdown());

  Target target() => query('foo').toTarget();

  test('a target that can not be allocated fails the listen', () async {
    faults.failActions = <String>['Allocate target'];
    await expectLater(
      localStore.allocateTarget(target()),
      throwsA(isA<TransientDatabaseException>()),
    );
    expect(await localStore.getQueryData(target()), isNull);

    faults.failActions = <String>[];
    expect((await localStore.allocateTarget(target())).targetId, 2);
  });

  test(
    'a cached target that can not be allocated fails the listen too',
    () async {
      final QueryData queryData = await localStore.allocateTarget(target());
      await localStore.releaseTarget(queryData.targetId);

      faults.failActions = <String>['Allocate target'];
      await expectLater(
        localStore.allocateTarget(target()),
        throwsA(isA<TransientDatabaseException>()),
      );
    },
  );

  test(
    'a release that can not be stored releases the target in memory',
    () async {
      final QueryData queryData = await localStore.allocateTarget(target());

      faults.failActions = <String>['Release target'];
      await localStore.releaseTarget(queryData.targetId);

      faults.failActions = <String>[];
      // The target is gone from memory; the persisted one is found and reused by the next listen.
      final QueryData again = await localStore.allocateTarget(target());
      expect(again.targetId, queryData.targetId);
    },
  );

  test(
    'a view change that can not be stored still advances the limbo free snapshot version',
    () async {
      final QueryData queryData = await localStore.allocateTarget(target());
      await localStore.applyRemoteEvent(
        _event(queryData.targetId, version(1000), 'resume-token-1000'),
      );

      faults.failActions = <String>['notifyLocalViewChanges'];
      await localStore.notifyLocalViewChanges(<LocalViewChanges>[
        LocalViewChanges(
          queryData.targetId,
          /* fromCache= */ false,
          DocumentKey.emptyKeySet,
          DocumentKey.emptyKeySet,
        ),
      ]);

      final QueryData? updated = await localStore.getQueryData(target());
      expect(updated!.lastLimboFreeSnapshotVersion, version(1000));
    },
  );

  test(
    'a remote event that can not be stored leaves the target data as it was',
    () async {
      final QueryData queryData = await localStore.allocateTarget(target());

      faults.failActions = <String>['Apply remote event'];
      await expectLater(
        localStore.applyRemoteEvent(
          _event(queryData.targetId, version(1000), 'resume-token-1000'),
        ),
        throwsA(isA<TransientDatabaseException>()),
      );
      final QueryData? unchanged = await localStore.getQueryData(target());
      expect(unchanged!.resumeToken, isEmpty);
      expect(unchanged.snapshotVersion, SnapshotVersion.none);
      expect(localStore.getLastRemoteSnapshotVersion(), SnapshotVersion.none);

      faults.failActions = <String>[];
      await localStore.applyRemoteEvent(
        _event(queryData.targetId, version(1000), 'resume-token-1000'),
      );
      final QueryData? applied = await localStore.getQueryData(target());
      expect(utf8.decode(applied!.resumeToken), 'resume-token-1000');
    },
  );

  test(
    'a user change that can not be stored keeps the mutation queue of the previous user',
    () async {
      await localStore.writeLocally(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ]);

      faults.failActions = <String>['Handle user change'];
      await expectLater(
        localStore.handleUserChange(const User('other')),
        throwsA(isA<TransientDatabaseException>()),
      );
      // Still the queue of the unauthenticated user.
      expect(
        await localStore.getNextMutationBatch(MutationBatch.unknown),
        isNotNull,
      );

      faults.failActions = <String>[];
      await localStore.handleUserChange(const User('other'));
      expect(
        await localStore.getNextMutationBatch(MutationBatch.unknown),
        isNull,
      );
    },
  );

  test('a write that can not be stored is not queued', () async {
    faults.failActions = <String>['Locally write mutations'];
    await expectLater(
      localStore.writeLocally(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ]),
      throwsA(isA<TransientDatabaseException>()),
    );
    expect(
      await localStore.getNextMutationBatch(MutationBatch.unknown),
      isNull,
    );
  });

  test(
    'the last remote snapshot version is read in a transaction of its own',
    () async {
      faults.failActions = <String>['Get last remote snapshot version'];
      await expectLater(
        localStore.readLastRemoteSnapshotVersion(),
        throwsA(isA<TransientDatabaseException>()),
      );
      faults.failActions = <String>[];
      expect(
        await localStore.readLastRemoteSnapshotVersion(),
        SnapshotVersion.none,
      );
    },
  );
}

/// A global snapshot at [snapshotVersion] that makes [targetId] current with [resumeToken].
RemoteEvent _event(
  int targetId,
  SnapshotVersion snapshotVersion,
  String resumeToken,
) {
  return RemoteEvent(
    documentUpdates: const <DocumentKey, MaybeDocument>{},
    resolvedLimboDocuments: const <DocumentKey>{},
    snapshotVersion: snapshotVersion,
    targetChanges: <int, TargetChange>{
      targetId: targetChange(
        Uint8List.fromList(utf8.encode(resumeToken)),
        null,
        null,
        null,
        current: true,
      ),
    },
  );
}
