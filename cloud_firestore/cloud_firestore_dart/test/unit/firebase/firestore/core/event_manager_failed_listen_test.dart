import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class _Listener extends Fake implements QueryStream {
  _Listener(this.query, {this.listensToRemoteStore = true});

  @override
  final Query query;

  @override
  final bool listensToRemoteStore;

  @override
  bool onOnlineStateChanged(OnlineState onlineState) => false;

  @override
  Future<bool> onViewSnapshot(ViewSnapshot newSnapshot) async => false;
}

/// A sync engine whose listens fail while [failListen] / [failRemote] are set.
class _SyncEngine extends Fake implements SyncEngine {
  bool failListen = false;
  bool failRemote = false;
  int listens = 0;
  int remoteListens = 0;
  int stops = 0;
  int remoteStops = 0;

  @override
  set syncEngineListener(SyncEngineCallback callback) {}

  @override
  Future<int> listen(Query query, {bool shouldListenToRemote = true}) async {
    listens++;
    if (failListen) {
      throw StateError('listen failed');
    }
    return 2;
  }

  @override
  Future<void> listenToRemoteStore(Query query) async {
    remoteListens++;
    if (failRemote) {
      throw StateError('remote listen failed');
    }
  }

  @override
  Future<void> stopListening(
    Query query, {
    bool shouldUnlistenToRemote = true,
  }) async {
    stops++;
  }

  @override
  Future<void> stopListeningToRemoteStore(Query query) async {
    remoteStops++;
  }
}

void main() {
  final Query q = query('rooms');

  test(
    'a failed listen forgets the query so a later listener listens again',
    () async {
      final _SyncEngine syncEngine = _SyncEngine()..failListen = true;
      final EventManager manager = EventManager(syncEngine);
      final _Listener first = _Listener(q);

      await expectLater(manager.addQueryListener(first), throwsStateError);
      // The failed listener is not registered any more.
      expect(await manager.removeQueryListener(first), isFalse);
      expect(syncEngine.stops, 0);

      syncEngine.failListen = false;
      final _Listener second = _Listener(q);
      expect(await manager.addQueryListener(second), 2);
      expect(syncEngine.listens, 2);

      expect(await manager.removeQueryListener(second), isTrue);
      expect(syncEngine.stops, 1);
    },
  );

  test(
    'a failed remote listen on a cache-only query keeps the cache listener',
    () async {
      final _SyncEngine syncEngine = _SyncEngine();
      final EventManager manager = EventManager(syncEngine);
      final _Listener cacheOnly = _Listener(q, listensToRemoteStore: false);
      await manager.addQueryListener(cacheOnly);
      expect(syncEngine.listens, 1);

      syncEngine.failRemote = true;
      final _Listener remote = _Listener(q);
      await expectLater(manager.addQueryListener(remote), throwsStateError);
      expect(syncEngine.remoteListens, 1);
      expect(await manager.removeQueryListener(remote), isFalse);

      // A later remote listener asks for the remote listen again.
      syncEngine.failRemote = false;
      final _Listener remote2 = _Listener(q);
      await manager.addQueryListener(remote2);
      expect(syncEngine.remoteListens, 2);
      // No second local listen: the query stayed registered.
      expect(syncEngine.listens, 1);

      // Removing the last remote listener only stops the remote side.
      expect(await manager.removeQueryListener(remote2), isTrue);
      expect(syncEngine.remoteStops, 1);
      expect(syncEngine.stops, 0);
      expect(await manager.removeQueryListener(cacheOnly), isTrue);
      expect(syncEngine.stops, 1);
    },
  );

  test('ListenOptions.copyWith replaces only the given fields', () {
    const ListenOptions options = ListenOptions(
      includeDocumentMetadataChanges: true,
      includeQueryMetadataChanges: false,
      waitForSyncWhenOnline: true,
      source: ListenSource.defaultSource,
    );
    final ListenOptions copy = options.copyWith(
      includeQueryMetadataChanges: true,
      source: ListenSource.cache,
    );
    expect(copy.includeDocumentMetadataChanges, isTrue);
    expect(copy.includeQueryMetadataChanges, isTrue);
    expect(copy.waitForSyncWhenOnline, isTrue);
    expect(copy.source, ListenSource.cache);
    final ListenOptions same = options.copyWith();
    expect(same.includeQueryMetadataChanges, isFalse);
    expect(same.source, ListenSource.defaultSource);
  });
}
