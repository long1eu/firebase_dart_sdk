// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// [QueryListener] takes a series of internal view snapshots and determines
/// when to raise events.
class QueryListener extends Stream<ViewSnapshot> {
  QueryListener(this.query,
      [this.options = const ListenOptions(), this.onCancel])
      : assert(options != null) {
    sink = StreamController<ViewSnapshot>(onCancel: () => onCancel?.call(this));
  }

  final Query query;

  final ListenOptions options;

  final void Function(QueryListener listener) onCancel;

  StreamController<ViewSnapshot> sink;

  /// Initial snapshots (e.g. from cache) may not be propagated to the wrapped
  /// observer. This flag is set to true once we've actually raised an event.
  bool raisedInitialEvent = false;

  OnlineState onlineState = OnlineState.unknown;

  ViewSnapshot snapshot;

  Future<void> onViewSnapshot(ViewSnapshot newSnapshot) async {
    Assert.hardAssert(
        newSnapshot.changes.isNotEmpty || newSnapshot.didSyncStateChange,
        'We got a new snapshot with no changes?');

    if (!options.includeDocumentMetadataChanges) {
      // Remove the metadata only changes
      final List<DocumentViewChange> documentChanges = <DocumentViewChange>[];
      for (DocumentViewChange change in newSnapshot.changes) {
        if (change.type != DocumentViewChangeType.metadata) {
          documentChanges.add(change);
        }
      }
      newSnapshot = newSnapshot.copyWith(changes: documentChanges);
    }

    if (!raisedInitialEvent) {
      final bool shouldRaiseInitialEvent =
          _shouldRaiseInitialEvent(newSnapshot, onlineState);

      if (shouldRaiseInitialEvent) {
        _raiseInitialEvent(newSnapshot);
      }
    } else if (_shouldRaiseEvent(newSnapshot)) {
      sink.add(newSnapshot);
    }

    snapshot = newSnapshot;
  }

  void onError(FirebaseFirestoreError error) {
    sink.addError(error);
  }

  void onOnlineStateChanged(OnlineState onlineState) {
    this.onlineState = onlineState;
    if (snapshot != null &&
        !raisedInitialEvent &&
        _shouldRaiseInitialEvent(snapshot, onlineState)) {
      _raiseInitialEvent(snapshot);
    }
  }

  bool _shouldRaiseInitialEvent(
      ViewSnapshot snapshot, OnlineState onlineState) {
    Assert.hardAssert(
      !raisedInitialEvent,
      'Determining whether to raise first event but already had first event.',
    );

    // Always raise the first event when we're synced
    if (!snapshot.isFromCache) {
      return true;
    }

    // NOTE: We consider OnlineState.unknown as [online] (it should become
    // [offline] or [online] if we wait long enough).
    final bool maybeOnline = onlineState != OnlineState.offline;
    // Don't raise the event if we're online, aren't synced yet (checked
    // above) and are waiting for a sync.
    if (options.waitForSyncWhenOnline && maybeOnline) {
      Assert.hardAssert(snapshot.isFromCache,
          'Waiting for sync, but snapshot is not from cache');
      return false;
    }

    // Raise data from cache if we have any documents or we are offline
    return snapshot.documents.isNotEmpty || onlineState == OnlineState.offline;
  }

  bool _shouldRaiseEvent(ViewSnapshot snapshot) {
    // We don't need to handle includeDocumentMetadataChanges here because the
    // Metadata only changes have already been stripped out if needed. At this
    // point the only changes we will see are the ones we should propagate.
    if (snapshot.changes.isNotEmpty) {
      return true;
    }

    final bool hasPendingWritesChanged = this.snapshot != null &&
        this.snapshot.hasPendingWrites != snapshot.hasPendingWrites;
    if (snapshot.didSyncStateChange || hasPendingWritesChanged) {
      return options.includeQueryMetadataChanges;
    }

    // Generally we should have hit one of the cases above, but it's possible
    // to get here if there were only metadata docChanges and they got
    // stripped out.
    return false;
  }

  void _raiseInitialEvent(ViewSnapshot snapshot) {
    Assert.hardAssert(
        !raisedInitialEvent, 'Trying to raise initial event for second time');

    snapshot = snapshot.copyWith(
      oldDocuments: DocumentSet.emptySet(snapshot.query.comparator),
      changes: QueryListener._getInitialViewChanges(snapshot),
      didSyncStateChange: true,
    );

    raisedInitialEvent = true;
    sink.add(snapshot);
  }

  static List<DocumentViewChange> _getInitialViewChanges(
      ViewSnapshot snapshot) {
    final List<DocumentViewChange> res = <DocumentViewChange>[];
    for (Document doc in snapshot.documents) {
      res.add(DocumentViewChange(DocumentViewChangeType.added, doc));
    }
    return res;
  }

  @override
  StreamSubscription<ViewSnapshot> listen(
          void Function(ViewSnapshot event) onData,
          {Function onError,
          void Function() onDone,
          bool cancelOnError}) =>
      sink.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}
