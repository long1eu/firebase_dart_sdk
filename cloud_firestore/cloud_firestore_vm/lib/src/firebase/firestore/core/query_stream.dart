// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// Signature called when the stream is no longer being actively listened to.
typedef OnCancelListener = Future<void> Function(QueryStream listener);

/// [QueryStream] takes a series of internal view snapshots and determines
/// when to raise events.
class QueryStream extends Stream<ViewSnapshot> {
  factory QueryStream(
    Query query, [
    ListenOptions options = const ListenOptions(),
    OnCancelListener? onCancel,
  ]) {
    late final QueryStream stream;
    return stream = QueryStream._(
      query,
      options,
      StreamController<ViewSnapshot>(
        onCancel: () async => onCancel?.call(stream),
      ),
    );
  }

  QueryStream._(
    this._query,
    this._options,
    this._sink,
  );

  final Query _query;
  final ListenOptions _options;
  final StreamController<ViewSnapshot> _sink;

  /// Initial snapshots (e.g. from cache) may not be propagated to the wrapped
  /// observer. This flag is set to true once we've actually raised an event.
  bool _raisedInitialEvent = false;
  OnlineState _onlineState = OnlineState.unknown;
  ViewSnapshot? _snapshot;

  Query get query => _query;

  ListenOptions get options => _options;

  /// Whether this listener needs the backend (false for cache only listeners).
  bool get listensToRemoteStore => _options.source != ListenSource.cache;

  /// Handles a new view snapshot. Returns true if this raised an event to the listener.
  Future<bool> onViewSnapshot(ViewSnapshot newSnapshot) async {
    bool raisedEvent = false;
    hardAssert(newSnapshot.changes.isNotEmpty || newSnapshot.didSyncStateChange,
        'We got a new snapshot with no changes?');

    if (!options.includeDocumentMetadataChanges) {
      // Remove the metadata only changes
      newSnapshot = newSnapshot.copyWith(
        excludesMetadataChanges: true,
        changes: newSnapshot.changes
            .where((DocumentViewChange change) =>
                change.type != DocumentViewChangeType.metadata)
            .toList(),
      );
    }

    if (!_raisedInitialEvent) {
      final bool shouldRaiseInitialEvent =
          _shouldRaiseInitialEvent(newSnapshot, _onlineState);

      if (shouldRaiseInitialEvent) {
        _raiseInitialEvent(newSnapshot);
        raisedEvent = true;
      }
    } else if (_shouldRaiseEvent(newSnapshot)) {
      _sink.add(newSnapshot);
      raisedEvent = true;
    }

    _snapshot = newSnapshot;
    return raisedEvent;
  }

  void onError(FirestoreError error) {
    _sink.addError(error);
    // An error is terminal: the event manager already dropped this listener, so close the stream instead of leaving
    // the subscriber waiting forever.
    if (!_sink.isClosed) {
      _sink.close();
    }
  }

  /// Handles a change of the online state. Returns true if this raised an event to the listener.
  bool onOnlineStateChanged(OnlineState onlineState) {
    _onlineState = onlineState;
    final ViewSnapshot? snapshot = _snapshot;
    if (snapshot != null &&
        !_raisedInitialEvent &&
        _shouldRaiseInitialEvent(snapshot, onlineState)) {
      _raiseInitialEvent(snapshot);
      return true;
    }
    return false;
  }

  bool _shouldRaiseInitialEvent(
    ViewSnapshot snapshot,
    OnlineState onlineState,
  ) {
    hardAssert(!_raisedInitialEvent,
        'Determining whether to raise first event but already had first event.');

    // Always raise the first event when we're synced
    if (!snapshot.isFromCache) {
      return true;
    }

    // Always raise the event if listening to the cache only: there is nothing
    // to wait for.
    if (!listensToRemoteStore) {
      return true;
    }

    // NOTE: We consider OnlineState.unknown as [online] (it should become
    // [offline] or [online] if we wait long enough).
    final bool maybeOnline = onlineState != OnlineState.offline;
    // Don't raise the event if we're online, aren't synced yet (checked above)
    // and are waiting for a sync.
    if (options.waitForSyncWhenOnline && maybeOnline) {
      hardAssert(snapshot.isFromCache,
          'Waiting for sync, but snapshot is not from cache');
      return false;
    }

    // Raise data from cache if we have any documents or we are offline
    return snapshot.documents.isNotEmpty ||
        snapshot.hasCachedResults ||
        onlineState == OnlineState.offline;
  }

  bool _shouldRaiseEvent(ViewSnapshot snapshot) {
    // We don't need to handle includeDocumentMetadataChanges here because the
    // Metadata only changes have already been stripped out if needed. At this
    // point the only changes we will see are the ones we should propagate.
    if (snapshot.changes.isNotEmpty) {
      return true;
    }

    final bool hasPendingWritesChanged = _snapshot != null &&
        _snapshot!.hasPendingWrites != snapshot.hasPendingWrites;
    if (snapshot.didSyncStateChange || hasPendingWritesChanged) {
      return options.includeQueryMetadataChanges;
    }

    // Generally we should have hit one of the cases above, but it's possible to
    // get here if there were only metadata docChanges and they got stripped out.
    return false;
  }

  void _raiseInitialEvent(ViewSnapshot snapshot) {
    hardAssert(
        !_raisedInitialEvent, 'Trying to raise initial event for second time');

    _raisedInitialEvent = true;
    _sink.add(ViewSnapshot.fromInitialDocuments(
      snapshot.query,
      snapshot.documents,
      snapshot.mutatedKeys,
      isFromCache: snapshot.isFromCache,
      excludesMetadataChanges: snapshot.excludesMetadataChanges,
      hasCachedResults: snapshot.hasCachedResults,
    ));
  }

  @override
  StreamSubscription<ViewSnapshot> listen(
      void Function(ViewSnapshot event)? onData,
      {Function? onError,
      void Function()? onDone,
      bool? cancelOnError}) {
    return _sink.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
