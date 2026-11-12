import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:grpc/grpc.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../local/persistence_test_helpers.dart';

/// Records the order in which the sync engine talks to the remote store and to its listener.
class _RecordingRemoteStore extends Fake implements RemoteStore {
  _RecordingRemoteStore(this.events);

  final List<String> events;

  @override
  Future<void> listen(QueryData queryData) async {
    events.add('remoteStore.listen');
  }
}

class _RecordingCallback implements SyncEngineCallback {
  _RecordingCallback(this.events);

  final List<String> events;
  final List<ViewSnapshot> snapshots = <ViewSnapshot>[];

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    events.add('onViewSnapshots');
    snapshots.addAll(snapshotList);
  }

  @override
  void onError(Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

class _ScriptedRemoteStore extends Fake implements RemoteStore {
  _ScriptedRemoteStore(this.events);

  final List<String> events;
  final List<QueryData> listens = <QueryData>[];
  Future<void> Function(int targetId)? onStopListening;
  Future<void> Function(QueryData queryData)? onListen;

  @override
  Future<void> listen(QueryData queryData) async {
    events.add('remoteStore.listen');
    listens.add(queryData);
    await onListen?.call(queryData);
  }

  @override
  Future<void> stopListening(int targetId) async {
    events.add('remoteStore.stopListening');
    await onStopListening?.call(targetId);
  }

  @override
  Future<void> fillWritePipeline() async {}
}

RemoteEvent _currentEvent(int versionMicros, int targetId,
    [List<Document> docs = const <Document>[]]) {
  return RemoteEvent(
    snapshotVersion: version(versionMicros),
    targetChanges: <int, TargetChange>{
      targetId: TargetChange.createSynthesizedTargetChangeForCurrentChange(
          true, Uint8List(0)),
    },
    documentUpdates: <DocumentKey, Document>{
      for (final Document d in docs) d.key: d
    },
    resolvedLimboDocuments: const <DocumentKey>{},
  );
}

void main() {
  test('listen raises the local snapshot before starting the backend query',
      () async {
    final List<String> events = <String>[];
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();

    final SyncEngine syncEngine = SyncEngine(
        localStore, _RecordingRemoteStore(events), User.unauthenticated)
      ..syncEngineListener = _RecordingCallback(events);

    await syncEngine.listen(query('foo'));

    // The view must exist when the listen request is built: it provides the expected count of a resumed target.
    expect(events, <String>['onViewSnapshots', 'remoteStore.listen']);
    await persistence.shutdown();
  });

  test('a backend reply to the listen finds the query view', () async {
    final List<String> events = <String>[];
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final _ScriptedRemoteStore remoteStore = _ScriptedRemoteStore(events);
    final _RecordingCallback callback = _RecordingCallback(events);
    final SyncEngine syncEngine =
        SyncEngine(localStore, remoteStore, User.unauthenticated)
          ..syncEngineListener = callback;

    // The backend answers (CURRENT) as soon as the remote listen starts.
    remoteStore.onListen = (QueryData queryData) async {
      await syncEngine.handleRemoteEvent(_currentEvent(1, queryData.targetId));
    };
    await syncEngine.listen(query('foo'));
    // The listen does not wait for the backend (starting the watch stream needs the network, see
    // [SyncEngine.listen]), so let the scripted backend reply finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(callback.snapshots.any((ViewSnapshot s) => !s.isFromCache), isTrue,
        reason: 'the CURRENT of the target must reach the registered view');
    await persistence.shutdown();
  });

  test('emitting snapshots survives listens started while it awaits', () async {
    final List<String> events = <String>[];
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final _ScriptedRemoteStore remoteStore = _ScriptedRemoteStore(events);
    final SyncEngine syncEngine =
        SyncEngine(localStore, remoteStore, User.unauthenticated)
          ..syncEngineListener = _RecordingCallback(events);

    final int target = await syncEngine.listen(query('foo'));
    await syncEngine.listen(query('bar'));

    // The limbo listen started while the views are updated adds another view meanwhile.
    Future<void>? concurrentListen;
    remoteStore.onListen = (QueryData queryData) async {
      if (queryData.purpose == QueryPurpose.limboResolution &&
          concurrentListen == null) {
        concurrentListen = syncEngine.listen(query('baz'));
        await concurrentListen;
      }
    };
    await syncEngine.handleRemoteEvent(_currentEvent(
        1, target, <Document>[doc('foo/a', 1, <String, Object?>{})]));
    expect(concurrentListen, isNotNull);
    await persistence.shutdown();
  });

  test(
      'a document that re-enters limbo while its limbo listen is removed is '
      'resolved', () async {
    final List<String> events = <String>[];
    final MemoryPersistence persistence = await createLRUMemoryPersistence();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final _ScriptedRemoteStore remoteStore = _ScriptedRemoteStore(events);
    final SyncEngine syncEngine =
        SyncEngine(localStore, remoteStore, User.unauthenticated)
          ..syncEngineListener = _RecordingCallback(events);

    final Query a = query('foo');
    final int targetA = await syncEngine.listen(a);
    // The document arrives in a current target but is not part of the target: it is in limbo.
    await syncEngine.handleRemoteEvent(_currentEvent(
        1, targetA, <Document>[doc('foo/a', 1, <String, Object?>{})]));
    List<QueryData> limboListens() => remoteStore.listens
        .where((QueryData d) => d.purpose == QueryPurpose.limboResolution)
        .toList();
    expect(limboListens(), hasLength(1));

    // While the limbo listen is being stopped, a second view is created that finds the same document in limbo.
    final int limboTarget = limboListens().single.targetId;
    remoteStore.onStopListening = (int targetId) async {
      if (targetId != limboTarget) {
        return;
      }
      remoteStore.onStopListening = null;
      final int targetB = await syncEngine.listen(query('foo').limit(5));
      await syncEngine.handleRemoteEvent(_currentEvent(2, targetB));
    };
    await syncEngine.stopListening(a);

    expect(limboListens(), hasLength(2),
        reason: 'the document is in limbo again and needs a new resolution');
    await persistence.shutdown();
  });

  group('mirror queries', () {
    // A limit query and a limitToLast query with the flipped ordering share
    // the same target.
    final Query limit = query('foo').orderBy(orderBy('sort')).limit(2);
    final Query limitToLast =
        query('foo').orderBy(orderBy('sort', 'desc')).limitToLast(2);

    test('map to the same target and release it with the last query',
        () async {
      final List<String> events = <String>[];
      final MemoryPersistence persistence =
          MemoryPersistence.createEagerGcMemoryPersistence();
      await persistence.start();
      final LocalStore localStore =
          LocalStore(persistence, User.unauthenticated);
      await localStore.start();
      final _ScriptedRemoteStore remoteStore = _ScriptedRemoteStore(events);
      final SyncEngine syncEngine =
          SyncEngine(localStore, remoteStore, User.unauthenticated)
            ..syncEngineListener = _RecordingCallback(events);

      final int first = await syncEngine.listen(limit);
      final int second = await syncEngine.listen(limitToLast);
      expect(second, first);
      expect(remoteStore.listens.map((QueryData d) => d.targetId),
          <int>[first, first]);

      // Stopping one of the queries keeps the target alive.
      await syncEngine.stopListening(limit);
      expect(events.where((String e) => e == 'remoteStore.stopListening'),
          isEmpty);

      // The target can still be updated: the remaining view receives it.
      await syncEngine.handleRemoteEvent(_currentEvent(1, first));

      // Stopping the last query releases the target.
      await syncEngine.stopListening(limitToLast);
      expect(events.where((String e) => e == 'remoteStore.stopListening'),
          hasLength(1));

      // The queries can be listened to again (a new target is allocated).
      final int relisten = await syncEngine.listen(limitToLast);
      expect(relisten, greaterThan(0));
      await persistence.shutdown();
    });

    test('apply the sync state of the existing query to the new one',
        () async {
      final List<String> events = <String>[];
      final MemoryPersistence persistence =
          MemoryPersistence.createEagerGcMemoryPersistence();
      await persistence.start();
      final LocalStore localStore =
          LocalStore(persistence, User.unauthenticated);
      await localStore.start();
      final _ScriptedRemoteStore remoteStore = _ScriptedRemoteStore(events);
      final _RecordingCallback callback = _RecordingCallback(events);
      final SyncEngine syncEngine =
          SyncEngine(localStore, remoteStore, User.unauthenticated)
            ..syncEngineListener = callback;

      final int target = await syncEngine.listen(limit);
      await syncEngine.handleRemoteEvent(_currentEvent(1, target));
      expect(callback.snapshots.last.query, limit);
      expect(callback.snapshots.last.isFromCache, isFalse);

      // The target is already current: the new query must not wait for a
      // backend event that will never come.
      callback.snapshots.clear();
      await syncEngine.listen(limitToLast);
      expect(callback.snapshots, hasLength(1));
      expect(callback.snapshots.single.query, limitToLast);
      expect(callback.snapshots.single.isFromCache, isFalse);
      await persistence.shutdown();
    });

    test('listening to a different limit type creates a new target', () async {
      final List<String> events = <String>[];
      final MemoryPersistence persistence =
          MemoryPersistence.createEagerGcMemoryPersistence();
      await persistence.start();
      final LocalStore localStore =
          LocalStore(persistence, User.unauthenticated);
      await localStore.start();
      final SyncEngine syncEngine = SyncEngine(
          localStore, _ScriptedRemoteStore(events), User.unauthenticated)
        ..syncEngineListener = _RecordingCallback(events);

      final int first = await syncEngine.listen(limit);
      final int second = await syncEngine
          .listen(query('foo').orderBy(orderBy('sort')).limitToLast(2));
      expect(second, isNot(first));
      await persistence.shutdown();
    });
  });
}
