// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

/// EventManager is responsible for mapping queries to query event listeners.
/// It handles 'fan-out.' (Identical queries will re-use the same watch on the
/// backend.)
class EventManager implements SyncEngineCallback {
  EventManager(this._syncEngine) : _queries = <Query, _QueryListenersInfo>{} {
    _syncEngine.syncEngineListener = this;
  }

  final SyncEngine _syncEngine;
  final Map<Query, _QueryListenersInfo> _queries;

  /// The listeners that are notified when all the query listeners are in sync with each other.
  final List<void Function()> _snapshotsInSyncListeners = <void Function()>[];

  OnlineState _onlineState = OnlineState.unknown;

  /// Adds a query listener that will be called with new snapshots for the
  /// query. The [EventManager] is responsible for multiplexing many listeners
  /// to a single listen in the [SyncEngine] and will perform a listen if it's
  /// the first [QueryStream] added for a query.
  ///
  /// Returns the targetId of the listen call in the [SyncEngine].
  Future<int> addQueryListener(QueryStream queryListener) async {
    final Query query = queryListener.query;

    final _QueryListenersInfo? existing = _queries[query];
    final _QueryListenersInfo queryInfo = existing ?? _QueryListenersInfo();

    // What the sync engine has to do for this listener: a new query is listened
    // locally (and from the backend unless the listener is cache only), an
    // existing query that so far only listened to the cache has to start
    // listening to the backend when the new listener needs it.
    bool listenLocally = false;
    bool listenRemotely = false;
    if (existing == null) {
      _queries[query] = queryInfo;
      listenLocally = true;
      listenRemotely = queryListener.listensToRemoteStore;
    } else if (!queryInfo.hasRemoteListeners &&
        queryListener.listensToRemoteStore) {
      listenRemotely = true;
    }

    queryInfo.listeners.add(queryListener);

    final bool raisedEventOnOnlineState = queryListener.onOnlineStateChanged(
      _onlineState,
    );
    hardAssert(
      !raisedEventOnOnlineState,
      'onOnlineStateChanged() shouldn\'t raise an event for brand-new listeners.',
    );

    final ViewSnapshot? viewSnapshot = queryInfo.viewSnapshot;
    if (viewSnapshot != null) {
      if (await queryListener.onViewSnapshot(viewSnapshot)) {
        _raiseSnapshotsInSyncEvent();
      }
    }

    try {
      if (listenLocally) {
        queryInfo.targetId = await _syncEngine.listen(
          query,
          shouldListenToRemote: listenRemotely,
        );
      } else if (listenRemotely) {
        await _syncEngine.listenToRemoteStore(query);
      }
    } catch (_) {
      // Do not leave a half registered listener behind: later listeners would never trigger a listen.
      queryInfo.listeners.remove(queryListener);
      if (listenLocally && identical(_queries[query], queryInfo)) {
        _queries.remove(query);
      }
      rethrow;
    }
    return queryInfo.targetId;
  }

  /// Removes a previously added listener and returns true if the listener was
  /// found.
  Future<bool> removeQueryListener(QueryStream listener) async {
    final Query query = listener.query;
    final _QueryListenersInfo? queryInfo = _queries[query];
    bool found = false;
    if (queryInfo != null) {
      found = queryInfo.listeners.remove(listener);
      if (!found) {
        return false;
      }
      if (queryInfo.listeners.isEmpty) {
        _queries.remove(query);
        await _syncEngine.stopListening(
          query,
          shouldUnlistenToRemote: listener.listensToRemoteStore,
        );
      } else if (listener.listensToRemoteStore &&
          !queryInfo.hasRemoteListeners) {
        // The removed listener was the last one sourced from the backend.
        await _syncEngine.stopListeningToRemoteStore(query);
      }
    }

    return found;
  }

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    bool raisedEvent = false;
    for (ViewSnapshot viewSnapshot in snapshotList) {
      final Query query = viewSnapshot.query;
      final _QueryListenersInfo? info = _queries[query];
      if (info != null) {
        for (QueryStream listener in info.listeners.toList()) {
          if (await listener.onViewSnapshot(viewSnapshot)) {
            raisedEvent = true;
          }
        }
        info.viewSnapshot = viewSnapshot;
      }
    }
    if (raisedEvent) {
      _raiseSnapshotsInSyncEvent();
    }
  }

  @override
  void onError(Query query, GrpcError error) {
    final _QueryListenersInfo? info = _queries[query];
    if (info != null) {
      for (QueryStream listener in info.listeners.toList()) {
        listener.onError(exceptionFromStatus(error));
      }
    }
    _queries.remove(query);
  }

  @override
  void handleOnlineStateChange(OnlineState onlineState) {
    _onlineState = onlineState;
    bool raisedEvent = false;
    for (_QueryListenersInfo info in _queries.values) {
      for (QueryStream listener in info.listeners.toList()) {
        if (listener.onOnlineStateChanged(onlineState)) {
          raisedEvent = true;
        }
      }
    }
    if (raisedEvent) {
      _raiseSnapshotsInSyncEvent();
    }
  }

  /// Adds a listener that is called whenever all the query listeners have been given their snapshots (and once right
  /// away, with the current state).
  void addSnapshotsInSyncListener(void Function() listener) {
    _snapshotsInSyncListeners.add(listener);
    listener();
  }

  /// Removes a listener that was added with [addSnapshotsInSyncListener].
  void removeSnapshotsInSyncListener(void Function() listener) {
    _snapshotsInSyncListeners.remove(listener);
  }

  void _raiseSnapshotsInSyncEvent() {
    for (void Function() listener in _snapshotsInSyncListeners.toList()) {
      listener();
    }
  }
}

class _QueryListenersInfo {
  _QueryListenersInfo() : listeners = <QueryStream>[];

  final List<QueryStream> listeners;
  ViewSnapshot? viewSnapshot;
  int targetId = 0;

  /// Whether any of the listeners of the query listens to the backend.
  bool get hasRemoteListeners =>
      listeners.any((QueryStream listener) => listener.listensToRemoteStore);
}

/// Holds (internal) options for listening
class ListenOptions {
  const ListenOptions({
    this.includeDocumentMetadataChanges = false,
    this.includeQueryMetadataChanges = false,
    this.waitForSyncWhenOnline = false,
    this.source = ListenSource.defaultSource,
  });

  const ListenOptions.all()
    : includeDocumentMetadataChanges = true,
      includeQueryMetadataChanges = true,
      waitForSyncWhenOnline = true,
      source = ListenSource.defaultSource;

  /// Raise events when only metadata of documents changes
  final bool includeDocumentMetadataChanges;

  /// Raise events when only metadata of the query changes
  final bool includeQueryMetadataChanges;

  /// Wait for a sync with the server when online, but still raise events while
  /// offline.
  final bool waitForSyncWhenOnline;

  /// The source the query listens to.
  final ListenSource source;

  ListenOptions copyWith({
    bool? includeDocumentMetadataChanges,
    bool? includeQueryMetadataChanges,
    bool? waitForSyncWhenOnline,
    ListenSource? source,
  }) {
    return ListenOptions(
      includeDocumentMetadataChanges:
          includeDocumentMetadataChanges ?? this.includeDocumentMetadataChanges,
      includeQueryMetadataChanges:
          includeQueryMetadataChanges ?? this.includeQueryMetadataChanges,
      waitForSyncWhenOnline:
          waitForSyncWhenOnline ?? this.waitForSyncWhenOnline,
      source: source ?? this.source,
    );
  }
}
