// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// QueryListener takes a series of internal view snapshots and determines when
/// to raise events.
///
/// * It uses an [EventListener] to dispatch events.
class QueryListener {
  final Query query;

  final ListenOptions options;

  final EventListener<ViewSnapshot> listener;

  /// Initial snapshots (e.g. from cache) may not be propagated to the wrapped
  /// observer. This flag is set to true once we've actually raised an event.
  bool raisedInitialEvent = false;

  OnlineState onlineState = OnlineState.unknown;

  ViewSnapshot snapshot;

  QueryListener(this.query, this.options, this.listener);

  void onViewSnapshot(ViewSnapshot newSnapshot) {
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
      if (_shouldRaiseInitialEvent(newSnapshot, onlineState)) {
        raiseInitialEvent(newSnapshot);
      }
    } else if (shouldRaiseEvent(newSnapshot)) {
      listener(newSnapshot, null);
    }

    snapshot = newSnapshot;
  }

  void onError(FirebaseFirestoreError error) {
    listener(null, error);
  }

  void onOnlineStateChanged(OnlineState onlineState) {
    this.onlineState = onlineState;
    if (snapshot != null &&
        !raisedInitialEvent &&
        _shouldRaiseInitialEvent(snapshot, onlineState)) {
      raiseInitialEvent(snapshot);
    }
  }

  bool _shouldRaiseInitialEvent(
      ViewSnapshot snapshot, OnlineState onlineState) {
    Assert.hardAssert(!raisedInitialEvent,
        'Determining whether to raise first event but already had first event.');

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

  bool shouldRaiseEvent(ViewSnapshot snapshot) {
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

  void raiseInitialEvent(ViewSnapshot snapshot) {
    Assert.hardAssert(
        !raisedInitialEvent, 'Trying to raise initial event for second time');

    snapshot = snapshot.copyWith(
      oldDocuments: DocumentSet.emptySet(snapshot.query.comparator),
      changes: QueryListener._getInitialViewChanges(snapshot),
      didSyncStateChange: true,
    );

    raisedInitialEvent = true;
    listener(snapshot, null);
  }

  static List<DocumentViewChange> _getInitialViewChanges(
      ViewSnapshot snapshot) {
    final List<DocumentViewChange> res = <DocumentViewChange>[];
    for (Document doc in snapshot.documents) {
      res.add(DocumentViewChange(DocumentViewChangeType.added, doc));
    }
    return res;
  }
}
