import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:grpc/grpc.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class _RemoteStore extends Fake implements RemoteStore {
  final List<QueryData> listens = <QueryData>[];

  @override
  Future<void> listen(QueryData queryData) async => listens.add(queryData);

  @override
  Future<void> stopListening(int targetId) async {}

  @override
  Future<void> fillWritePipeline() async {}
}

class _Callback implements SyncEngineCallback {
  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {}

  @override
  void onError(Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

/// A sync engine whose query `foo` has `foo/a` in limbo, with the limbo
/// listen at [limboTarget].
class _Fixture {
  _Fixture._(this.persistence, this.syncEngine, this.limboTarget);

  static Future<_Fixture> create() async {
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final _RemoteStore remoteStore = _RemoteStore();
    final SyncEngine syncEngine = SyncEngine(
      localStore,
      remoteStore,
      User.unauthenticated,
    )..syncEngineListener = _Callback();

    final int target = await syncEngine.listen(query('foo'));
    // foo/a is in the view but the CURRENT target does not contain it: limbo.
    await syncEngine.handleRemoteEvent(
      RemoteEvent(
        snapshotVersion: version(1),
        targetChanges: <int, TargetChange>{
          target: TargetChange.createSynthesizedTargetChangeForCurrentChange(
            true,
            Uint8List(0),
          ),
        },
        documentUpdates: <DocumentKey, MaybeDocument>{
          key('foo/a'): doc('foo/a', 1, <String, Object?>{}),
        },
        resolvedLimboDocuments: const <DocumentKey>{},
      ),
    );
    final QueryData limbo = remoteStore.listens.singleWhere(
      (QueryData d) => d.purpose == QueryPurpose.limboResolution,
    );
    return _Fixture._(persistence, syncEngine, limbo.targetId);
  }

  final MemoryPersistence persistence;
  final SyncEngine syncEngine;
  final int limboTarget;

  Future<void> limboChange({
    List<String> added = const <String>[],
    List<String> modified = const <String>[],
    List<String> removed = const <String>[],
    Document? document,
    int atVersion = 2,
  }) {
    return syncEngine.handleRemoteEvent(
      RemoteEvent(
        snapshotVersion: version(atVersion),
        targetChanges: <int, TargetChange>{
          limboTarget: TargetChange(
            resumeToken: Uint8List(0),
            current: false,
            addedDocuments: keySet(added.map(key).toList()),
            modifiedDocuments: keySet(modified.map(key).toList()),
            removedDocuments: keySet(removed.map(key).toList()),
          ),
        },
        documentUpdates: <DocumentKey, MaybeDocument>{
          // The key is read from the document, so `?document` cannot replace the check.
          // ignore: use_null_aware_elements
          if (document != null) document.key: document,
        },
        resolvedLimboDocuments: const <DocumentKey>{},
      ),
    );
  }

  Iterable<DocumentKey> remoteKeys() =>
      syncEngine.getRemoteKeysForTarget(limboTarget);
}

void main() {
  late _Fixture f;

  setUp(() async => f = await _Fixture.create());
  tearDown(() => f.persistence.shutdown());

  test(
    'add, modify and remove of the limbo document track receivedDocument',
    () async {
      expect(f.remoteKeys(), isEmpty);

      await f.limboChange(
        added: <String>['foo/a'],
        document: doc('foo/a', 2, map(<Object>['v', 1])),
      );
      expect(f.remoteKeys(), <DocumentKey>[key('foo/a')]);

      await f.limboChange(
        modified: <String>['foo/a'],
        document: doc('foo/a', 3, map(<Object>['v', 2])),
        atVersion: 3,
      );
      expect(f.remoteKeys(), <DocumentKey>[key('foo/a')]);

      await f.limboChange(removed: <String>['foo/a'], atVersion: 4);
      expect(f.remoteKeys(), isEmpty);
    },
  );

  test('a modification without a preceding add is rejected', () async {
    await expectLater(
      f.limboChange(
        modified: <String>['foo/a'],
        document: doc('foo/a', 2, <String, Object?>{}),
      ),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('change for limbo target document without add'),
        ),
      ),
    );
  });

  test('a removal without a preceding add is rejected', () async {
    await expectLater(
      f.limboChange(removed: <String>['foo/a']),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('remove for limbo target document without add'),
        ),
      ),
    );
  });

  test('more than one change in a limbo target is rejected', () async {
    await expectLater(
      f.limboChange(added: <String>['foo/a'], removed: <String>['foo/b']),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          contains('multiple changes'),
        ),
      ),
    );
  });
}
