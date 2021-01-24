// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// View is responsible for computing the final merged truth of what docs are in a query. It gets notified of local and
/// remote changes to docs, and applies the query filters and limits to determine the most correct possible results.
class View {
  View(this.query, this._syncedDocuments) {
    _syncState = ViewSnapshotSyncState.none;
    documentSet = DocumentSet.emptySet(query.comparator);
    _limboDocuments = DocumentKey.emptyKeySet;
    mutatedKeys = DocumentKey.emptyKeySet;
  }

  final Query query;

  ViewSnapshotSyncState _syncState;

  /// A flag whether the view is current with the backend. A view is considered current after it has seen the current
  /// flag from the backend and did not lose consistency within the watch stream (e.g. because of an existence filter
  /// mismatch).
  bool _current = false;

  DocumentSet documentSet;

  /// The set of documents that the server has told us belongs to the target associated with this view.
  ImmutableSortedSet<DocumentKey> _syncedDocuments;

  ImmutableSortedSet<DocumentKey> get syncedDocuments => ImmutableSortedSet<DocumentKey>(_syncedDocuments.toList());

  /// Documents in the view but not in the remote target
  ImmutableSortedSet<DocumentKey> _limboDocuments;

  List<DocumentKey> get limboDocuments => _limboDocuments.toList();

  /// Documents that have local changes
  ImmutableSortedSet<DocumentKey> mutatedKeys;

  ViewSnapshotSyncState get syncState => _syncState;

  /// Iterates over a set of doc changes, applies the query limit, and computes what the new results should be, what the
  /// changes were, and whether we may need to go back to the local cache for more results. Does not make any changes to
  /// the view.
  ///
  /// If this is being called with a refill, then start with [previousChanges] of docs and changes instead of the
  /// current view. Returns a new set of docs, changes, and refill flag.
  ViewDocumentChanges computeDocChanges<D extends MaybeDocument>(ImmutableSortedMap<DocumentKey, D> docChanges,
      [ViewDocumentChanges previousChanges]) {
    final DocumentViewChangeSet changeSet =
        previousChanges != null ? previousChanges.changeSet : DocumentViewChangeSet();
    final DocumentSet oldDocumentSet = previousChanges != null //
        ? previousChanges.documentSet
        : documentSet;
    ImmutableSortedSet<DocumentKey> newMutatedKeys = previousChanges != null //
        ? previousChanges.mutatedKeys
        : mutatedKeys;

    DocumentSet newDocumentSet = oldDocumentSet;
    bool needsRefill = false;

    // Track the last doc in a (full) limit. This is necessary, because some update (a delete, or an update moving a doc
    // past the old limit) might mean there is some other document in the local cache that either should come (1)
    // between the old last limit doc and the new last document, in the case of updates, or (2) after the new last
    // document, in the case of deletes. So we keep this doc at the old limit to compare the updates to.
    //
    // Note that this should never get used in a refill (when previousChanges is set), because there will only be adds
    // -- no deletes or updates.
    final Document lastDocInLimit = query.hasLimitToFirst && oldDocumentSet.length == query.getLimitToFirst() //
        ? oldDocumentSet.last
        : null;
    final Document firstDocInLimit = query.hasLimitToLast && oldDocumentSet.length == query.getLimitToLast() //
        ? oldDocumentSet.first
        : null;

    for (MapEntry<DocumentKey, MaybeDocument> entry in docChanges) {
      final DocumentKey key = entry.key;
      final Document oldDoc = oldDocumentSet.getDocument(key);
      Document newDoc;
      final MaybeDocument maybeDoc = entry.value;

      if (maybeDoc is Document) {
        newDoc = maybeDoc;
      }

      if (newDoc != null) {
        hardAssert(key == newDoc.key, 'Mismatching key in doc change $key != ${newDoc.key}');
        if (!query.matches(newDoc)) {
          newDoc = null;
        }
      }

      final bool oldDocHadPendingMutations = oldDoc != null && mutatedKeys.contains(oldDoc.key);

      // We only consider committed mutations for documents that were mutated during the lifetime of the view.
      final bool newDocHasPendingMutations = newDoc != null &&
          (newDoc.hasLocalMutations || (mutatedKeys.contains(newDoc.key) && newDoc.hasCommittedMutations));

      bool changeApplied = false;

      // Calculate change
      if (oldDoc != null && newDoc != null) {
        final bool docsEqual = oldDoc.data == newDoc.data;
        if (!docsEqual) {
          if (!shouldWaitForSyncedDocument(oldDoc, newDoc)) {
            changeSet.addChange(DocumentViewChange(DocumentViewChangeType.modified, newDoc));
            changeApplied = true;

            if ((lastDocInLimit != null && query.comparator(newDoc, lastDocInLimit) > 0) ||
                (firstDocInLimit != null && query.comparator(newDoc, firstDocInLimit) < 0)) {
              // This doc moved from inside the limit to outside the limit. That means there may be
              // some doc in the local cache that should be included instead.
              needsRefill = true;
            }
          }
        } else if (oldDocHadPendingMutations != newDocHasPendingMutations) {
          changeSet.addChange(DocumentViewChange(DocumentViewChangeType.metadata, newDoc));
          changeApplied = true;
        }
      } else if (oldDoc == null && newDoc != null) {
        changeSet.addChange(DocumentViewChange(DocumentViewChangeType.added, newDoc));
        changeApplied = true;
      } else if (oldDoc != null && newDoc == null) {
        changeSet.addChange(DocumentViewChange(DocumentViewChangeType.removed, oldDoc));
        changeApplied = true;
        if (lastDocInLimit != null || firstDocInLimit != null) {
          // A doc was removed from a full limit query. We'll need to requery from the local cache to see if we know
          // about some other doc that should be in the results.
          needsRefill = true;
        }
      }

      if (changeApplied) {
        if (newDoc != null) {
          newDocumentSet = newDocumentSet.add(newDoc);
          if (newDoc.hasLocalMutations) {
            newMutatedKeys = newMutatedKeys.insert(newDoc.key);
          } else {
            newMutatedKeys = newMutatedKeys.remove(newDoc.key);
          }
        } else {
          newDocumentSet = newDocumentSet.remove(key);
          newMutatedKeys = newMutatedKeys.remove(key);
        }
      }
    }

    // Drop documents out to meet limitToFirst/limitToLast requirement.
    if (query.hasLimitToFirst || query.hasLimitToLast) {
      final int limit = query.hasLimitToFirst ? query.getLimitToFirst() : query.getLimitToLast();
      for (int i = newDocumentSet.length - limit; i > 0; --i) {
        final Document oldDoc = query.hasLimitToFirst ? newDocumentSet.last : newDocumentSet.first;
        newDocumentSet = newDocumentSet.remove(oldDoc.key);
        newMutatedKeys = newMutatedKeys.remove(oldDoc.key);
        changeSet.addChange(DocumentViewChange(DocumentViewChangeType.removed, oldDoc));
      }
    }

    hardAssert(
        !needsRefill || previousChanges == null, 'View was refilled using docs that themselves needed refilling.');

    return ViewDocumentChanges._(newDocumentSet, changeSet, newMutatedKeys, needsRefill);
  }

  bool shouldWaitForSyncedDocument(Document oldDoc, Document newDoc) {
    // We suppress the initial change event for documents that were modified as part of a write acknowledgment (e.g.
    // when the value of a server transform is applied) as Watch will send us the same document again. By suppressing
    // the event, we only raise two user visible events (one with [hasPendingWrites] and the final state of the
    // document) instead of three (one with [hasPendingWrites], the modified document with [hasPendingWrites] and the
    // final state of the document).
    return oldDoc.hasLocalMutations && newDoc.hasCommittedMutations && !newDoc.hasLocalMutations;
  }

  /// Updates the view with the given [ViewDocumentChanges] and updates limbo docs and sync state from the given
  /// (optional) target change. Returns a new [ViewChange] with the given docs, changes, and sync state.
  ViewChange applyChanges(ViewDocumentChanges docChanges, [TargetChange targetChange]) {
    hardAssert(!docChanges.needsRefill, 'Cannot apply changes that need a refill');

    final DocumentSet oldDocumentSet = documentSet;
    documentSet = docChanges.documentSet;
    mutatedKeys = docChanges.mutatedKeys;

    // Sort changes based on type and query comparator.
    final List<DocumentViewChange> viewChanges = docChanges.changeSet.getChanges()
      ..sort((DocumentViewChange a, DocumentViewChange b) {
        final int typeComp = View._changeTypeOrder(a).compareTo(View._changeTypeOrder(b));
        a.type.compareTo(b.type);
        if (typeComp != 0) {
          return typeComp;
        }
        return query.comparator(a.document, b.document);
      });

    _applyTargetChange(targetChange);

    final List<LimboDocumentChange> limboDocumentChanges = _updateLimboDocuments();
    final bool synced = _limboDocuments.isEmpty && _current;

    final ViewSnapshotSyncState newSyncState = synced //
        ? ViewSnapshotSyncState.synced
        : ViewSnapshotSyncState.local;
    final bool syncStatedChanged = newSyncState != _syncState;
    _syncState = newSyncState;
    ViewSnapshot snapshot;
    if (viewChanges.isNotEmpty || syncStatedChanged) {
      final bool fromCache = newSyncState == ViewSnapshotSyncState.local;

      snapshot = ViewSnapshot(
        query,
        docChanges.documentSet,
        oldDocumentSet,
        viewChanges,
        docChanges.mutatedKeys,
        isFromCache: fromCache,
        didSyncStateChange: syncStatedChanged,
        excludesMetadataChanges: false,
      );
    }
    return ViewChange(snapshot, limboDocumentChanges);
  }

  /// Applies an [OnlineState] change to the view, potentially generating a [ViewChange] if the view's syncState changes
  /// as a result.
  ViewChange applyOnlineStateChange(OnlineState onlineState) {
    if (_current && onlineState == OnlineState.offline) {
      // If we're offline, set `current` to false and then call applyChanges() to refresh our syncState and generate a
      // [ViewChange] as appropriate. We are guaranteed to get a new [TargetChange] that sets `current` back to true
      // once the client is back online.
      _current = false;
      return applyChanges(ViewDocumentChanges._(
        documentSet,
        DocumentViewChangeSet(),
        mutatedKeys,
        /*needsRefill*/ false,
      ));
    } else {
      // No effect, just return a no-op [ViewChange].
      return const ViewChange(null, <LimboDocumentChange>[]);
    }
  }

  void _applyTargetChange(TargetChange targetChange) {
    if (targetChange != null) {
      for (DocumentKey documentKey in targetChange.addedDocuments) {
        _syncedDocuments = _syncedDocuments.insert(documentKey);
      }
      for (DocumentKey documentKey in targetChange.modifiedDocuments) {
        hardAssert(_syncedDocuments.contains(documentKey), 'Modified document $documentKey not found in view.');
      }
      for (DocumentKey documentKey in targetChange.removedDocuments) {
        _syncedDocuments = _syncedDocuments.remove(documentKey);
      }
      _current = targetChange.current;
    }
  }

  List<LimboDocumentChange> _updateLimboDocuments() {
    // We can only determine limbo documents when we're in-sync with the server.
    if (!_current) {
      return <LimboDocumentChange>[];
    }

    // TODO(long1eu): Do this incrementally so that it's not quadratic when updating many documents.
    final ImmutableSortedSet<DocumentKey> oldLimboDocs = _limboDocuments;
    _limboDocuments = DocumentKey.emptyKeySet;
    for (Document doc in documentSet) {
      if (_shouldBeLimboDoc(doc.key)) {
        _limboDocuments = _limboDocuments.insert(doc.key);
      }
    }

    // Diff the new limbo docs with the old limbo docs.
    final List<LimboDocumentChange> changes = <LimboDocumentChange>[];

    for (DocumentKey key in oldLimboDocs) {
      if (!_limboDocuments.contains(key)) {
        changes.add(LimboDocumentChange(LimboDocumentChangeType.removed, key));
      }
    }

    for (DocumentKey key in _limboDocuments) {
      if (!oldLimboDocs.contains(key)) {
        changes.add(LimboDocumentChange(LimboDocumentChangeType.added, key));
      }
    }
    return changes;
  }

  bool _shouldBeLimboDoc(DocumentKey key) {
    // If the remote end says it's part of this query, it's not in limbo.
    if (_syncedDocuments.contains(key)) {
      return false;
    }

    // The local store doesn't think it's a result, so it shouldn't be in limbo.
    final Document doc = documentSet.getDocument(key);
    if (doc == null) {
      return false;
    }

    // If there are local changes to the doc, they might explain why the server doesn't know that it's part of the
    // query. So don't put it in limbo.
    //
    // TODO(long1eu): Ideally, we would only consider changes that might actually affect this specific query.
    if (doc.hasLocalMutations) {
      return false;
    }

    // Everything else is in limbo
    return true;
  }

  /// Helper function to determine order of changes
  static int _changeTypeOrder(DocumentViewChange change) {
    if (change.type == DocumentViewChangeType.added) {
      return 1;
    } else if (change.type == DocumentViewChangeType.modified) {
      return 2;
    } else if (change.type == DocumentViewChangeType.metadata) {
      // A metadata change is converted to a modified change at the public api layer. Since we sort by document key and
      // then change type, metadata and modified changes must be sorted equivalently.
      return 2;
    } else if (change.type == DocumentViewChangeType.removed) {
      return 0;
    }

    throw ArgumentError('Unknown change type: ${change.type}');
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('syncState', _syncState)
          ..add('current', _current)
          ..add('documentSet', documentSet)
          ..add('syncedDocuments', _syncedDocuments)
          ..add('limboDocuments', _limboDocuments)
          ..add('mutatedKeys', mutatedKeys))
        .toString();
  }
}

/// The result of applying a set of doc changes to a view.
class ViewDocumentChanges {
  const ViewDocumentChanges._(
    this.documentSet,
    this.changeSet,
    this.mutatedKeys,
    this.needsRefill,
  );

  /// The new set of docs that should be in the view.
  final DocumentSet documentSet;

  /// The diff of these docs with the previous set of docs.
  final DocumentViewChangeSet changeSet;

  /// Whether the set of documents passed in was not sufficient to calculate the new state of the view and there needs
  /// to be another pass based on the local cache.
  final bool needsRefill;

  final ImmutableSortedSet<DocumentKey> mutatedKeys;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('documentSet', documentSet)
          ..add('changeSet', changeSet)
          ..add('mutatedKeys', mutatedKeys)
          ..add('needsRefill', needsRefill))
        .toString();
  }
}
