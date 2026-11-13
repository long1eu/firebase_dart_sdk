// File created by
// Lung Razvan <long1eu>
// on 26/09/2018
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

/// Records the events a [QueryStream] receives, in the order they are received.
class QueryListenerMock extends Fake implements QueryStream {
  QueryListenerMock(this.query, [List<Object>? log]) : log = log ?? <Object>[];

  @override
  final Query query;

  final List<Object> log;
  final List<OnlineState> onlineStates = <OnlineState>[];

  /// Default listeners (not cache only), like upstream's mocked QueryListener.
  @override
  bool get listensToRemoteStore => true;

  @override
  bool onOnlineStateChanged(OnlineState onlineState) {
    onlineStates.add(onlineState);
    return false;
  }

  @override
  Future<bool> onViewSnapshot(ViewSnapshot newSnapshot) async {
    log.add(<Object>[this, newSnapshot]);
    return false;
  }
}

/// Records the calls made on a [SyncEngine].
class SyncEngineMock extends Fake implements SyncEngine {
  final List<Query> listened = <Query>[];
  final List<Query> stopped = <Query>[];
  final List<bool> listenedToRemote = <bool>[];
  final List<bool> unlistenedFromRemote = <bool>[];
  final List<Query> remoteListened = <Query>[];
  final List<Query> remoteStopped = <Query>[];

  @override
  set syncEngineListener(SyncEngineCallback callback) {}

  @override
  Future<int> listen(Query query, {bool shouldListenToRemote = true}) async {
    listened.add(query);
    listenedToRemote.add(shouldListenToRemote);
    return 0;
  }

  @override
  Future<void> listenToRemoteStore(Query query) async {
    remoteListened.add(query);
  }

  @override
  Future<void> stopListening(
    Query query, {
    bool shouldUnlistenToRemote = true,
  }) async {
    stopped.add(query);
    unlistenedFromRemote.add(shouldUnlistenToRemote);
  }

  @override
  Future<void> stopListeningToRemoteStore(Query query) async {
    remoteStopped.add(query);
  }
}

class ViewSnapshotMock extends Fake implements ViewSnapshot {
  ViewSnapshotMock(this.query);

  @override
  final Query query;
}

// ignore_for_file: unawaited_futures, avoid_implementing_value_types
void main() {
  listenSourceTests();

  QueryStream queryListener(Query query) {
    return QueryStream(query)..listen(null);
  }

  test('testMultipleListensPerQuery', () async {
    final Query query = Query(path('foo/bar'));

    final QueryStream listener1 = queryListener(query);
    final QueryStream listener2 = queryListener(query);

    final SyncEngineMock syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy)
      ..addQueryListener(listener1)
      ..addQueryListener(listener2);

    await manager.removeQueryListener(listener1);
    await manager.removeQueryListener(listener2);

    expect(syncSpy.listened.where((Query q) => q == query).length, 1);
    expect(syncSpy.stopped.where((Query q) => q == query).length, 1);
  });

  test('testUnlistensOnUnknownListeners', () async {
    final Query query = Query(path('foo/bar'));
    final SyncEngineMock syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy);
    await manager.removeQueryListener(queryListener(query));
    expect(syncSpy.stopped.where((Query q) => q == query), isEmpty);
  });

  test('testListenCalledInOrder', () async {
    final Query query1 = Query(path('foo/bar'));
    final Query query2 = Query(path('bar/baz'));

    final SyncEngineMock syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final List<Object> log = <Object>[];
    final QueryListenerMock spy1 = QueryListenerMock(query1, log);
    final QueryListenerMock spy2 = QueryListenerMock(query2, log);
    final QueryListenerMock spy3 = QueryListenerMock(query1, log);
    eventManager
      ..addQueryListener(spy1)
      ..addQueryListener(spy2)
      ..addQueryListener(spy3);

    expect(syncSpy.listened.where((Query q) => q == query1).length, 1);
    expect(syncSpy.listened.where((Query q) => q == query2).length, 1);

    final ViewSnapshot snap1 = ViewSnapshotMock(query1);
    final ViewSnapshot snap2 = ViewSnapshotMock(query2);

    log.clear();
    await eventManager.onViewSnapshots(<ViewSnapshot>[snap1, snap2]);

    expect(log, <Object>[
      <Object>[spy1, snap1],
      <Object>[spy3, snap1],
      <Object>[spy2, snap2],
    ]);
  });

  test('testWillForwardOnOnlineStateChangedCalls', () {
    final Query query1 = Query(path('foo/bar'));

    final SyncEngineMock syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final QueryListenerMock spy = QueryListenerMock(query1);

    unawaited(eventManager.addQueryListener(spy));
    expect(spy.onlineStates, <OnlineState>[OnlineState.unknown]);
    eventManager.handleOnlineStateChange(OnlineState.online);
    expect(spy.onlineStates, <OnlineState>[
      OnlineState.unknown,
      OnlineState.online,
    ]);
  });
}

// Listen source tests, ported from the cache source cases of the upstream
// EventManagerTest / SnapshotListenerSourceTest (b77c218).
void listenSourceTests() {
  QueryStream listenerFor(Query query, ListenSource source) {
    return QueryStream(query, ListenOptions(source: source))..listen(null);
  }

  group('listen source', () {
    test('a cache only listener listens locally without the backend', () async {
      final Query query = Query(path('foo/bar'));
      final SyncEngineMock sync = SyncEngineMock();
      final EventManager manager = EventManager(sync);

      await manager.addQueryListener(listenerFor(query, ListenSource.cache));

      expect(sync.listened, <Query>[query]);
      expect(sync.listenedToRemote, <bool>[false]);
      expect(sync.remoteListened, isEmpty);
    });

    test('a default listener listens to the backend', () async {
      final Query query = Query(path('foo/bar'));
      final SyncEngineMock sync = SyncEngineMock();
      final EventManager manager = EventManager(sync);

      await manager.addQueryListener(
        listenerFor(query, ListenSource.defaultSource),
      );

      expect(sync.listenedToRemote, <bool>[true]);
    });

    test(
      'a default listener added to a cache query starts the backend listen',
      () async {
        final Query query = Query(path('foo/bar'));
        final SyncEngineMock sync = SyncEngineMock();
        final EventManager manager = EventManager(sync);

        final QueryStream cache = listenerFor(query, ListenSource.cache);
        final QueryStream remote = listenerFor(
          query,
          ListenSource.defaultSource,
        );
        final QueryStream remote2 = listenerFor(
          query,
          ListenSource.defaultSource,
        );
        await manager.addQueryListener(cache);
        await manager.addQueryListener(remote);
        await manager.addQueryListener(remote2);

        expect(sync.listened, <Query>[query]);
        expect(sync.listenedToRemote, <bool>[false]);
        // Only the first listener that needs the backend starts the listen.
        expect(sync.remoteListened, <Query>[query]);

        // Removing one of two remote listeners keeps the backend listen.
        await manager.removeQueryListener(remote);
        expect(sync.remoteStopped, isEmpty);
        // Removing the last remote listener stops it, the cache keeps listening.
        await manager.removeQueryListener(remote2);
        expect(sync.remoteStopped, <Query>[query]);
        expect(sync.stopped, isEmpty);

        await manager.removeQueryListener(cache);
        expect(sync.stopped, <Query>[query]);
        expect(sync.unlistenedFromRemote, <bool>[false]);
      },
    );

    test(
      'a cache listener added to a default query does not touch the backend',
      () async {
        final Query query = Query(path('foo/bar'));
        final SyncEngineMock sync = SyncEngineMock();
        final EventManager manager = EventManager(sync);

        final QueryStream remote = listenerFor(
          query,
          ListenSource.defaultSource,
        );
        final QueryStream cache = listenerFor(query, ListenSource.cache);
        await manager.addQueryListener(remote);
        await manager.addQueryListener(cache);

        expect(sync.listened, <Query>[query]);
        expect(sync.listenedToRemote, <bool>[true]);
        expect(sync.remoteListened, isEmpty);

        await manager.removeQueryListener(cache);
        expect(sync.remoteStopped, isEmpty);
        expect(sync.stopped, isEmpty);

        await manager.removeQueryListener(remote);
        expect(sync.stopped, <Query>[query]);
        expect(sync.unlistenedFromRemote, <bool>[true]);
      },
    );

    test(
      'removing the remote listener of a mixed query stops only the backend',
      () async {
        final Query query = Query(path('foo/bar'));
        final SyncEngineMock sync = SyncEngineMock();
        final EventManager manager = EventManager(sync);

        final QueryStream remote = listenerFor(
          query,
          ListenSource.defaultSource,
        );
        final QueryStream cache = listenerFor(query, ListenSource.cache);
        await manager.addQueryListener(remote);
        await manager.addQueryListener(cache);

        await manager.removeQueryListener(remote);
        expect(sync.remoteStopped, <Query>[query]);
        expect(sync.stopped, isEmpty);
      },
    );
  });
}
