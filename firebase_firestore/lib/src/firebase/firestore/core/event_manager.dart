// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';

/// EventManager is responsible for mapping queries to query event listeners.
/// It handles 'fan-out.' (Identical queries will re-use the same watch on the
/// backend.)
class EventManager implements SyncEngineCallback {
  EventManager(this._syncEngine) : _queries = <Query, QueryListenersInfo>{} {
    _syncEngine.syncEngineListener = this;
  }

  final SyncEngine _syncEngine;

  final Map<Query, QueryListenersInfo> _queries;

  OnlineState _onlineState = OnlineState.unknown;

  /// Adds a query listener that will be called with new snapshots for the
  /// query. The [EventManager] is responsible for multiplexing many listeners
  /// to a single listen in the [SyncEngine] and will perform a listen if it's
  /// the first [QueryListener] added for a query.
  ///
  /// Returns the targetId of the listen call in the [SyncEngine].
  Future<int> addQueryListener(QueryListener queryListener) async {
    final Query query = queryListener.query;

    QueryListenersInfo queryInfo = _queries[query];
    final bool firstListen = queryInfo == null;

    if (firstListen) {
      queryInfo = QueryListenersInfo();
      _queries[query] = queryInfo;
    }

    queryInfo._listeners.add(queryListener);

    queryListener.onOnlineStateChanged(_onlineState);

    if (queryInfo._viewSnapshot != null) {
      await queryListener.onViewSnapshot(queryInfo._viewSnapshot);
    }

    if (firstListen) {
      queryInfo._targetId = await _syncEngine.listen(query);
    }
    return queryInfo._targetId;
  }

  /// Removes a previously added listener and returns true if the listener was
  /// found.
  Future<bool> removeQueryListener(QueryListener listener) async {
    final Query query = listener.query;
    final QueryListenersInfo queryInfo = _queries[query];
    bool lastListen = false;
    bool found = false;
    if (queryInfo != null) {
      found = queryInfo._listeners.remove(listener);
      lastListen = queryInfo._listeners.isEmpty;
    }

    if (lastListen) {
      _queries.remove(query);
      await _syncEngine.stopListening(query);
    }

    return found;
  }

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    for (ViewSnapshot viewSnapshot in snapshotList) {
      final Query query = viewSnapshot.query;
      final QueryListenersInfo info = _queries[query];
      if (info != null) {
        for (QueryListener listener in info._listeners) {
          await listener.onViewSnapshot(viewSnapshot);
        }
        info._viewSnapshot = viewSnapshot;
      }
    }
  }

  @override
  void onError(Query query, GrpcError error) {
    final QueryListenersInfo info = _queries[query];
    if (info != null) {
      for (QueryListener listener in info._listeners) {
        listener.onError(exceptionFromStatus(error));
      }
    }
    _queries.remove(query);
  }

  @override
  void handleOnlineStateChange(OnlineState onlineState) {
    _onlineState = onlineState;
    for (QueryListenersInfo info in _queries.values) {
      for (QueryListener listener in info._listeners) {
        listener.onOnlineStateChanged(onlineState);
      }
    }
  }
}

class QueryListenersInfo {
  QueryListenersInfo() : _listeners = <QueryListener>[];

  final List<QueryListener> _listeners;

  ViewSnapshot _viewSnapshot;
  int _targetId;
}

/// Holds (internal) options for listening
class ListenOptions {
  const ListenOptions({
    this.includeDocumentMetadataChanges = false,
    this.includeQueryMetadataChanges = false,
    this.waitForSyncWhenOnline = false,
  })  : assert(includeDocumentMetadataChanges != null),
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
      includeDocumentMetadataChanges: includeDocumentMetadataChanges ??
          this.includeDocumentMetadataChanges ??
          false,
      includeQueryMetadataChanges: includeQueryMetadataChanges ??
          this.includeQueryMetadataChanges ??
          false,
      waitForSyncWhenOnline:
          waitForSyncWhenOnline ?? this.waitForSyncWhenOnline ?? false,
    );
  }
}
