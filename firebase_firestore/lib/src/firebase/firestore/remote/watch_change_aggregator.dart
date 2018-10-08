// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:meta/meta.dart';

/// A helper class to accumulate watch changes into a [RemoteEvent] and other
/// target information.
class WatchChangeAggregator {
  final TargetMetadataProvider _targetMetadataProvider;

  /// The internal state of all tracked targets.
  final Map<int, TargetState> _targetStates = <int, TargetState>{};

  /// Keeps track of the documents to update since the last raised snapshot.
  Map<DocumentKey, MaybeDocument> _pendingDocumentUpdates =
      <DocumentKey, MaybeDocument>{};

  /// A mapping of document keys to their set of target IDs.
  Map<DocumentKey, Set<int>> _pendingDocumentTargetMapping =
      <DocumentKey, Set<int>>{};

  /// A list of targets with existence filter mismatches. These targets are
  /// known to be inconsistent and their listens needs to be re-established by
  /// [RemoteStore].
  Set<int> _pendingTargetResets = Set<int>();

  WatchChangeAggregator(this._targetMetadataProvider);

  /// Processes and adds the [WatchChangeDocumentChange] to the current set of
  /// changes.
  void handleDocumentChange(WatchChangeDocumentChange documentChange) {
    final MaybeDocument document = documentChange.newDocument;
    final DocumentKey documentKey = documentChange.documentKey;

    for (int targetId in documentChange.updatedTargetIds) {
      if (document is Document) {
        _addDocumentToTarget(targetId, document);
      } else if (document is NoDocument) {
        _removeDocumentFromTarget(targetId, documentKey, document);
      }
    }

    for (int targetId in documentChange.removedTargetIds) {
      _removeDocumentFromTarget(
          targetId, documentKey, documentChange.newDocument);
    }
  }

  /// Processes and adds the [WatchChangeWatchTargetChange] to the current set
  /// of changes.
  void handleTargetChange(WatchChangeWatchTargetChange targetChange) {
    for (int targetId in _getTargetIds(targetChange)) {
      final TargetState targetState = _ensureTargetState(targetId);

      switch (targetChange.changeType) {
        case WatchTargetChangeType.NoChange:
          if (_isActiveTarget(targetId)) {
            targetState.updateResumeToken(targetChange.resumeToken);
          }
          break;
        case WatchTargetChangeType.Added:
          // We need to decrement the number of pending acks needed from watch
          // for this [targetId].
          targetState.recordTargetResponse();
          if (!targetState.isPending()) {
            // We have a freshly added target, so we need to reset any state
            // that we had previously. This can happen e.g. when remove and add
            // back a target for existence filter mismatches.
            targetState.clearChanges();
          }
          targetState.updateResumeToken(targetChange.resumeToken);
          break;
        case WatchTargetChangeType.Removed:
          // We need to keep track of removed targets to we can post-filter and
          // remove any target changes.
          // We need to decrement the number of pending acks needed from watch
          // for this targetId.
          targetState.recordTargetResponse();
          if (!targetState.isPending()) {
            removeTarget(targetId);
          }
          Assert.hardAssert(targetChange.cause == null,
              'WatchChangeAggregator does not handle errored targets');
          break;
        case WatchTargetChangeType.Current:
          if (_isActiveTarget(targetId)) {
            targetState.markCurrent();
            targetState.updateResumeToken(targetChange.resumeToken);
          }
          break;
        case WatchTargetChangeType.Reset:
          if (_isActiveTarget(targetId)) {
            // Reset the target and synthesizes removes for all existing
            // documents. The backend will re-add any documents that still match
            // the target before it sends the next global snapshot.
            _resetTarget(targetId);
            targetState.updateResumeToken(targetChange.resumeToken);
          }
          break;
        default:
          throw Assert.fail(
              'Unknown target watch change state: ${targetChange.changeType}');
      }
    }
  }

  /// Returns all [targetIds] that the watch change applies to: either the
  /// [targetIds] explicitly listed in the change or the [targetIds] of all
  /// currently active targets.
  Iterable<int> _getTargetIds(WatchChangeWatchTargetChange targetChange) {
    final List<int> targetIds = targetChange.targetIds;
    if (targetIds.isNotEmpty) {
      return targetIds;
    } else {
      return _targetStates.keys;
    }
  }

  /// Handles existence filters and synthesizes deletes for filter mismatches.
  /// Targets that are invalidated by filter mismatches are added to
  /// [pendingTargetResets].
  void handleExistenceFilter(
      WatchChangeExistenceFilterWatchChange watchChange) {
    final int targetId = watchChange.targetId;
    final int expectedCount = watchChange.existenceFilter.count;

    final QueryData queryData = _queryDataForActiveTarget(targetId);
    if (queryData != null) {
      final Query query = queryData.query;
      if (query.isDocumentQuery) {
        if (expectedCount == 0) {
          // The existence filter told us the document does not exist. We deduce
          // that this document does not exist and apply a deleted document to
          // our updates. Without applying this deleted document there might be
          // another query that will raise this document as part of a snapshot
          // until it is resolved, essentially exposing inconsistency between
          // queries.
          final DocumentKey key = DocumentKey.fromPath(query.path);
          _removeDocumentFromTarget(
              targetId, key, NoDocument(key, SnapshotVersion.none));
        } else {
          Assert.hardAssert(expectedCount == 1,
              'Single document existence filter with count: $expectedCount');
        }
      } else {
        final int currentSize = _getCurrentDocumentCountForTarget(targetId);
        if (currentSize != expectedCount) {
          // Existence filter mismatch: We reset the mapping and raise a new
          // snapshot with [isFromCache:true].
          _resetTarget(targetId);
          _pendingTargetResets.add(targetId);
        }
      }
    }
  }

  /// Converts the currently accumulated state into a remote event at the
  /// provided snapshot version. Resets the accumulated changes before
  /// returning.
  RemoteEvent createRemoteEvent(SnapshotVersion snapshotVersion) {
    final Map<int, TargetChange> targetChanges = <int, TargetChange>{};

    for (MapEntry<int, TargetState> entry in _targetStates.entries) {
      final int targetId = entry.key;
      final TargetState targetState = entry.value;

      final QueryData queryData = _queryDataForActiveTarget(targetId);
      if (queryData != null) {
        if (targetState.isCurrent && queryData.query.isDocumentQuery) {
          // Document queries for document that don't exist can produce an empty
          // result set. To update our local cache, we synthesize a document
          // delete if we have not previously received the document. This
          // resolves the limbo state of the document, removing it from
          // [limboDocumentRefs].
          final DocumentKey key = DocumentKey.fromPath(queryData.query.path);
          if (_pendingDocumentUpdates[key] == null &&
              !_targetContainsDocument(targetId, key)) {
            _removeDocumentFromTarget(
                targetId, key, NoDocument(key, snapshotVersion));
          }
        }

        if (targetState.hasChanges) {
          targetChanges[targetId] = targetState.toTargetChange();
          targetState.clearChanges();
        }
      }
    }

    final Set<DocumentKey> resolvedLimboDocuments = Set<DocumentKey>();

    // We extract the set of limbo-only document updates as the GC logic
    // special-cases documents that do not appear in the query cache.
    for (MapEntry<DocumentKey, Set<int>> entry
        in _pendingDocumentTargetMapping.entries) {
      final DocumentKey key = entry.key;
      final Set<int> targets = entry.value;

      bool isOnlyLimboTarget = true;

      for (int targetId in targets) {
        final QueryData queryData = _queryDataForActiveTarget(targetId);
        if (queryData != null &&
            queryData.purpose != QueryPurpose.limboResolution) {
          isOnlyLimboTarget = false;
          break;
        }
      }

      if (isOnlyLimboTarget) {
        resolvedLimboDocuments.add(key);
      }
    }

    final RemoteEvent remoteEvent = RemoteEvent(
      snapshotVersion,
      Map<int, TargetChange>.from(targetChanges),
      Set<int>.from(_pendingTargetResets),
      Map<DocumentKey, MaybeDocument>.from(_pendingDocumentUpdates),
      Set<DocumentKey>.from(resolvedLimboDocuments),
    );

    // Re-initialize the current state to ensure that we do not modify the
    // generated [RemoteEvent].
    _pendingDocumentUpdates = <DocumentKey, MaybeDocument>{};
    _pendingDocumentTargetMapping = <DocumentKey, Set<int>>{};
    _pendingTargetResets = Set<int>();

    return remoteEvent;
  }

  /// Adds the provided document to the internal list of document updates and
  /// its document key to the given target's mapping.
  void _addDocumentToTarget(int targetId, MaybeDocument document) {
    if (!_isActiveTarget(targetId)) {
      return;
    }

    final DocumentViewChangeType changeType =
        _targetContainsDocument(targetId, document.key)
            ? DocumentViewChangeType.modified
            : DocumentViewChangeType.added;

    final TargetState targetState = _ensureTargetState(targetId);
    targetState.addDocumentChange(document.key, changeType);

    _pendingDocumentUpdates[document.key] = document;

    _ensureDocumentTargetMapping(document.key).add(targetId);
  }

  /// Removes the provided document from the target mapping. If the document no
  /// inter matches the target, but the document's state is still known (e.g.
  /// we know that the document was deleted or we received the change that
  /// caused the filter mismatch), the new document can be provided to update
  /// the remote document cache.
  void _removeDocumentFromTarget(
      int targetId, DocumentKey key, MaybeDocument updatedDocument) {
    if (!_isActiveTarget(targetId)) {
      return;
    }

    final TargetState targetState = _ensureTargetState(targetId);
    if (_targetContainsDocument(targetId, key)) {
      targetState.addDocumentChange(key, DocumentViewChangeType.removed);
    } else {
      // The document may have entered and left the target before we raised a
      // snapshot, so we can just ignore the change.
      targetState.removeDocumentChange(key);
    }

    _ensureDocumentTargetMapping(key).add(targetId);

    if (updatedDocument != null) {
      _pendingDocumentUpdates[key] = updatedDocument;
    }
  }

  void removeTarget(int targetId) => _targetStates.remove(targetId);

  /// Returns the current count of documents in the target. This includes both
  /// the number of documents that the [LocalStore] considers to be part of the
  /// target as well as any accumulated changes.
  int _getCurrentDocumentCountForTarget(int targetId) {
    final TargetState targetState = _ensureTargetState(targetId);
    final TargetChange targetChange = targetState.toTargetChange();
    return _targetMetadataProvider.getRemoteKeysForTarget(targetId).length +
        targetChange.addedDocuments.length -
        targetChange.removedDocuments.length;
  }

  /// Increment the number of acks needed from watch before we can consider the
  /// server to be "in-sync" with the client's active targets.
  void recordPendingTargetRequest(int targetId) {
    // For each request we get we need to record we need a response for it.
    final TargetState targetState = _ensureTargetState(targetId);
    targetState.recordPendingTargetRequest();
  }

  TargetState _ensureTargetState(int targetId) {
    return _targetStates[targetId] ??= TargetState();
  }

  Set<int> _ensureDocumentTargetMapping(DocumentKey key) {
    Set<int> targetMapping = _pendingDocumentTargetMapping[key];

    if (targetMapping == null) {
      targetMapping = Set<int>();
      _pendingDocumentTargetMapping[key] = targetMapping;
    }

    return targetMapping;
  }

  /// Verifies that the user is still interested in this target (by calling
  /// [getQueryDataForTarget]) and that we are not waiting for pending ADDs
  /// from watch.
  bool _isActiveTarget(int targetId) {
    return _queryDataForActiveTarget(targetId) != null;
  }

  /// Returns the [QueryData] for an active target (i.e. a target that the user
  /// is still interested in that has no outstanding target change requests).
  QueryData _queryDataForActiveTarget(int targetId) {
    final TargetState targetState = _targetStates[targetId];
    return targetState != null && targetState.isPending()
        ? null
        : _targetMetadataProvider.getQueryDataForTarget(targetId);
  }

  /// Resets the state of a [Watch] target to its initial state (e.g. sets
  /// [current] to false, clears the resume token and removes its target mapping
  /// from all documents).
  void _resetTarget(int targetId) {
    Assert.hardAssert(
        _targetStates[targetId] != null && !_targetStates[targetId].isPending(),
        'Should only reset active targets');
    _targetStates[targetId] = TargetState();

    // Trigger removal for any documents currently mapped to this target. These
    // removals will be part of the initial snapshot if [Watch] does not resend
    // these documents.
    final ImmutableSortedSet<DocumentKey> existingKeys =
        _targetMetadataProvider.getRemoteKeysForTarget(targetId);
    for (DocumentKey key in existingKeys) {
      _removeDocumentFromTarget(targetId, key, null);
    }
  }

  /// Returns whether the LocalStore considers the document to be part of the
  /// specified target.
  bool _targetContainsDocument(int targetId, DocumentKey key) {
    final ImmutableSortedSet<DocumentKey> existingKeys =
        _targetMetadataProvider.getRemoteKeysForTarget(targetId);
    return existingKeys.contains(key);
  }
}

/// Interface implemented by [RemoteStore] to expose target metadata to the
/// [WatchChangeAggregator].
class TargetMetadataProvider {
  /// Returns the set of remote document keys for the given target id as of the
  /// last raised snapshot or an empty set of document keys for unknown targets.
  final ImmutableSortedSet<DocumentKey> Function(int targetId)
      getRemoteKeysForTarget;

  /// Returns the [QueryData] for an active target id or 'null' if this query is
  /// unknown or has become inactive.
  final QueryData Function(int targetId) getQueryDataForTarget;

  const TargetMetadataProvider(
      {@required this.getRemoteKeysForTarget,
      @required this.getQueryDataForTarget});
}
