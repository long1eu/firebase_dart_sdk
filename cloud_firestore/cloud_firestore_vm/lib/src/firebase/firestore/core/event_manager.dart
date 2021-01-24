// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/rxdart.dart';

/// EventManager is responsible for mapping queries to query event listeners.
/// It handles 'fan-out.' (Identical queries will re-use the same watch on the
/// backend.)
class EventManager implements SyncEngineCallback {
  EventManager(this._syncEngine)
      : _queries = <Query, _QueryListenersInfo>{},
        _controller = BehaviorSubject<void>.seeded(null) {
    _syncEngine.syncEngineListener = this;
  }

  final SyncEngine _syncEngine;
  final Map<Query, _QueryListenersInfo> _queries;

  // We user BehaviorSubject because it emits the last value received
  final BehaviorSubject<void> _controller;

  OnlineState _onlineState = OnlineState.unknown;

  /// Global snapshots stream
  Stream<void> get snapshotsInSync => _controller;

  /// Adds a query listener that will be called with new snapshots for the
  /// query. The [EventManager] is responsible for multiplexing many listeners
  /// to a single listen in the [SyncEngine] and will perform a listen if it's
  /// the first [QueryStream] added for a query.
  ///
  /// Returns the targetId of the listen call in the [SyncEngine].
  Future<int> addQueryListener(QueryStream queryListener) async {
    final Query query = queryListener.query;

    _QueryListenersInfo queryInfo = _queries[query];
    final bool firstListen = queryInfo == null;

    if (firstListen) {
      queryInfo = _QueryListenersInfo();
      _queries[query] = queryInfo;
    }

    queryInfo.listeners.add(queryListener);

    // Run global snapshot listeners if a consistent snapshot has been emitted.
    bool raisedEvent = queryListener.onOnlineStateChanged(_onlineState);
    hardAssert(!raisedEvent, "onOnlineStateChanged() shouldn't raise an event for brand-new listeners.");

    if (queryInfo.viewSnapshot != null) {
      raisedEvent = queryListener.onViewSnapshot(queryInfo.viewSnapshot);
      if (raisedEvent) {
        _controller.add(null);
      }
    }

    if (firstListen) {
      queryInfo.targetId = await _syncEngine.listen(query);
    }
    return queryInfo.targetId;
  }

  /// It's a no-op if the listener is not found.
  Future<void> removeQueryListener(QueryStream listener) async {
    final Query query = listener.query;
    final _QueryListenersInfo queryInfo = _queries[query];
    bool lastListen = false;
    if (queryInfo != null) {
      queryInfo.listeners.remove(listener);
      lastListen = queryInfo.listeners.isEmpty;
    }

    if (lastListen) {
      _queries.remove(query);
      await _syncEngine.stopListening(query);
    }
  }

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    bool raisedEvent = false;
    for (ViewSnapshot viewSnapshot in snapshotList) {
      final Query query = viewSnapshot.query;
      final _QueryListenersInfo info = _queries[query];
      if (info != null) {
        for (QueryStream listener in info.listeners.toList()) {
          if (listener.onViewSnapshot(viewSnapshot)) {
            raisedEvent = true;
          }
        }
        info.viewSnapshot = viewSnapshot;
      }
    }
    if (raisedEvent) {
      _controller.add(null);
    }
  }

  @override
  void onError(Query query, GrpcError error) {
    final _QueryListenersInfo info = _queries[query];
    if (info != null) {
      for (QueryStream listener in info.listeners.toList()) {
        listener.onError(exceptionFromStatus(error));
      }
    }
    _queries.remove(query);
  }

  @override
  void handleOnlineStateChange(OnlineState onlineState) {
    bool raisedEvent = false;
    _onlineState = onlineState;
    for (_QueryListenersInfo info in _queries.values) {
      for (QueryStream listener in info.listeners.toList()) {
        if (listener.onOnlineStateChanged(onlineState)) {
          raisedEvent = true;
        }
      }
    }
    if (raisedEvent) {
      _controller.add(null);
    }
  }
}

class _QueryListenersInfo {
  _QueryListenersInfo() : listeners = <QueryStream>[];

  final List<QueryStream> listeners;
  ViewSnapshot viewSnapshot;
  int targetId;
}

/// Holds (internal) options for listening
class ListenOptions {
  const ListenOptions({
    this.includeDocumentMetadataChanges = false,
    this.includeQueryMetadataChanges = false,
    this.waitForSyncWhenOnline = false,
  })
      : assert(includeDocumentMetadataChanges != null),
        assert(includeQueryMetadataChanges != null),
        assert(waitForSyncWhenOnline != null);

  const ListenOptions.all()
      : includeDocumentMetadataChanges = true,
        includeQueryMetadataChanges = true,
        waitForSyncWhenOnline = true;

  /// Raise events when only metadata of documents changes
  final bool includeDocumentMetadataChanges;

  /// Raise events when only metadata of the query changes
  final bool includeQueryMetadataChanges;

  /// Wait for a sync with the server when online, but still raise events while
  /// offline.
  final bool waitForSyncWhenOnline;

  ListenOptions copyWith({
    bool includeDocumentMetadataChanges,
    bool includeQueryMetadataChanges,
    bool waitForSyncWhenOnline,
  }) {
    return ListenOptions(
      includeDocumentMetadataChanges: includeDocumentMetadataChanges ?? this.includeDocumentMetadataChanges,
      includeQueryMetadataChanges: includeQueryMetadataChanges ?? this.includeQueryMetadataChanges,
      waitForSyncWhenOnline: waitForSyncWhenOnline ?? this.waitForSyncWhenOnline,
    );
  }
}
