// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:firebase_app_dart/internal.dart';

/// View is responsible for computing the final merged truth of what docs are in a query. It gets notified of local and
/// remote changes to docs, and applies the query filters and limits to determine the most correct possible results.
class View {
  View(this.query, this._syncedDocuments, {this.limboResolutionEnabled = true})
    : _syncState = ViewSnapshotSyncState.none,
      documentSet = DocumentSet.emptySet(query.comparator),
      _limboDocuments = DocumentKey.emptyKeySet,
      mutatedKeys = DocumentKey.emptyKeySet;

  final Query query;

  /// Whether [applyChanges] computes the limbo documents. Only the primary client of a shared persistence resolves
  /// limbo documents; the views of the other clients do not have any. Set before each [applyChanges].
  bool limboResolutionEnabled;

  ViewSnapshotSyncState _syncState;

  ViewSnapshotSyncState get syncState => _syncState;

  /// A flag whether the view is current with the backend. A view is considered current after it has seen the current
  /// flag from the backend and did not lose consistency within the watch stream (e.g. because of an existence filter
  /// mismatch).
  bool _current = false;

  /// The snapshot version of the last remote event applied to this view (see [ViewSnapshot.readTime]).
  SnapshotVersion _readTime = SnapshotVersion.none;

  SnapshotVersion get readTime => _readTime;

  DocumentSet documentSet;

  /// The set of documents that the server has told us belongs to the target associated with this view.
  ImmutableSortedSet<DocumentKey> _syncedDocuments;

  // The set is immutable, so it can be shared without copying.
  ImmutableSortedSet<DocumentKey> get syncedDocuments => _syncedDocuments;

  /// Documents in the view but not in the remote target
  ImmutableSortedSet<DocumentKey> _limboDocuments;

  List<DocumentKey> get limboDocuments => _limboDocuments.toList();

  /// Documents that have local changes
  ImmutableSortedSet<DocumentKey> mutatedKeys;

  /// Documents whose local version the view still shows although their writes were acknowledged or rejected, because
  /// the change was held back until watch sends the document (see [shouldWaitForSyncedDocument]).
  ///
  /// The value is the version of the cached document (the commit version of its last write).
  Map<DocumentKey, SnapshotVersion> _awaitingSync =
      const <DocumentKey, SnapshotVersion>{};

  /// Documents of the view that watch shows are not in the target: it took them out (and did not put them back), or
  /// a snapshot of watch at or after the commit of a document of [_awaitingSync] did not have it. Watch will not send
  /// them unless they match again. Only kept for documents in the view.
  final Set<DocumentKey> _removedByWatch = <DocumentKey>{};

  /// Documents that are left out of this view although they are in the cache and match [query] locally, because the
  /// backend has shown that it does not consider them results of the query (see [backendMismatches]).
  ///
  /// PORTING NOTE: this does not exist upstream, where such a document stays in limbo forever.
  final Set<DocumentKey> _backendRejected = <DocumentKey>{};

  /// The documents of this view that the backend demonstrably does not consider results of the query.
  ///
  /// The local evaluation of a query can disagree with the backend (the filter semantics differ in a few places, and
  /// between editions of the backend). A cached document that only the client matches is in limbo: it is in the view
  /// but not in the target although the target is CURRENT. A limbo resolution normally ends that state, because the
  /// document turns out to be deleted, or changed so that it no longer matches. If it [confirmedToExist] instead (its
  /// limbo resolution is CURRENT and has the document, unchanged or still matching), nothing ever would: the view would
  /// stay `fromCache` forever. The backend is the authority on the result of a query, so the document is then taken
  /// out of this view (only; other queries are not affected).
  ///
  /// [targetChange] is the change of this view's target in the remote event that is about to be applied. The caller
  /// must only pass [confirmedToExist] when no local write can explain the difference (see
  /// `SyncEngine.handleRemoteEvent`).
  ///
  /// The returned documents are recorded as rejected and must be passed through [computeDocChanges] (as changed
  /// documents) so that they are removed. A rejected document is admitted again when the backend adds it to the target
  /// or when it gets a local mutation.
  List<Document> backendMismatches(
    Set<DocumentKey> confirmedToExist,
    TargetChange? targetChange,
    ImmutableSortedMap<DocumentKey, MaybeDocument> changes,
  ) {
    if (targetChange != null) {
      // The backend now says that the document is a result.
      targetChange.addedDocuments.forEach(_backendRejected.remove);
    }
    final bool current = targetChange?.current ?? _current;
    if (!current || confirmedToExist.isEmpty) {
      return const <Document>[];
    }

    final List<Document> result = <Document>[];
    for (final DocumentKey key in confirmedToExist) {
      if (documentSet.getDocument(key) == null) {
        continue;
      }
      final bool synced = targetChange == null
          ? _syncedDocuments.contains(key)
          : targetChange.addedDocuments.contains(key) ||
                (_syncedDocuments.contains(key) &&
                    !targetChange.removedDocuments.contains(key));
      if (synced) {
        continue;
      }
      // The version that is about to be applied, if the document changes in this event.
      final MaybeDocument? changed = changes[key];
      final MaybeDocument document = changed ?? documentSet.getDocument(key)!;
      if (document is! Document ||
          document.hasPendingWrites ||
          !query.matches(document)) {
        // A local write explains the difference, or the change resolves it.
        continue;
      }
      _backendRejected.add(key);
      result.add(document);
    }
    return result;
  }

  /// Iterates over a set of doc changes, applies the query limit, and computes what the new results should be, what the
  /// changes were, and whether we may need to go back to the local cache for more results. Does not make any changes to
  /// the view.
  ///
  /// If this is being called with a refill, then start with [previousChanges] of docs and changes instead of the
  /// current view. Returns a new set of docs, changes, and refill flag.
  ViewDocumentChanges computeDocChanges<D extends MaybeDocument>(
    ImmutableSortedMap<DocumentKey, D> docChanges, [
    ViewDocumentChanges? previousChanges,
  ]) {
    final DocumentViewChangeSet changeSet = previousChanges != null
        ? previousChanges.changeSet
        : DocumentViewChangeSet();
    final DocumentSet oldDocumentSet =
        previousChanges !=
            null //
        ? previousChanges.documentSet
        : documentSet;
    ImmutableSortedSet<DocumentKey> newMutatedKeys =
        previousChanges !=
            null //
        ? previousChanges.mutatedKeys
        : mutatedKeys;
    final Map<DocumentKey, SnapshotVersion> newAwaitingSync =
        Map<DocumentKey, SnapshotVersion>.of(
          previousChanges != null
              ? previousChanges.awaitingSync
              : _awaitingSync,
        );

    DocumentSet newDocumentSet = oldDocumentSet;
    bool needsRefill = false;
    // The comparator is created on each access, so only ask for it once.
    final Comparator<Document> queryComparator = query.comparator;

    // Track the last doc in a (full) limit. This is necessary, because some update (a delete, or an update moving a doc
    // past the old limit) might mean there is some other document in the local cache that either should come (1)
    // between the old last limit doc and the new last document, in the case of updates, or (2) after the new last
    // document, in the case of deletes. So we keep this doc at the old limit to compare the updates to.
    //
    // Note that this should never get used in a refill (when previousChanges is set), because there will only be adds
    // -- no deletes or updates.
    final Document? lastDocInLimit =
        (query.hasLimitToFirst && oldDocumentSet.length == query.getLimit())
        ? oldDocumentSet.getLastDocument()
        : null;
    // For a limitToLast query the documents that fall off the limit are the first ones.
    final Document? firstDocInLimit =
        (query.hasLimitToLast && oldDocumentSet.length == query.getLimit())
        ? oldDocumentSet.getFirstDocument()
        : null;

    for (MapEntry<DocumentKey, MaybeDocument> entry in docChanges) {
      final DocumentKey key = entry.key;
      final Document? oldDoc = oldDocumentSet.getDocument(key);
      Document? newDoc;
      final MaybeDocument maybeDoc = entry.value;

      if (maybeDoc is Document) {
        newDoc = maybeDoc;
      }

      if (newDoc != null) {
        final DocumentKey newDocKey = newDoc.key;
        hardAssertLazy(
          key == newDocKey,
          () => 'Mismatching key in doc change $key != $newDocKey',
        );
        if (!query.matches(newDoc)) {
          newDoc = null;
        } else if (_backendRejected.contains(key) &&
            !newDoc.hasLocalMutations) {
          // The backend does not consider the document a result, see [backendMismatches].
          newDoc = null;
        }
      }

      final bool oldDocHadPendingMutations =
          oldDoc != null && mutatedKeys.contains(oldDoc.key);

      // We only consider committed mutations for documents that were mutated during the lifetime of the view.
      final bool newDocHasPendingMutations =
          newDoc != null &&
          (newDoc.hasLocalMutations ||
              (mutatedKeys.contains(newDoc.key) &&
                  newDoc.hasCommittedMutations));

      bool changeApplied = false;

      // Calculate change
      if (oldDoc != null && newDoc != null) {
        final bool docsEqual = oldDoc.data == newDoc.data;
        if (!docsEqual) {
          if (shouldWaitForSyncedDocument(oldDoc, newDoc)) {
            newAwaitingSync[key] = newDoc.version;
          } else {
            changeSet.addChange(
              DocumentViewChange(DocumentViewChangeType.modified, newDoc),
            );
            changeApplied = true;

            if ((lastDocInLimit != null &&
                    queryComparator(newDoc, lastDocInLimit) > 0) ||
                (firstDocInLimit != null &&
                    queryComparator(newDoc, firstDocInLimit) < 0)) {
              // This doc moved from inside the limit to outside the limit. That means there may be some doc in the
              // local cache that should be included instead.
              needsRefill = true;
            }
          }
        } else if (oldDocHadPendingMutations != newDocHasPendingMutations) {
          changeSet.addChange(
            DocumentViewChange(DocumentViewChangeType.metadata, newDoc),
          );
          changeApplied = true;
        } else if (shouldWaitForSyncedDocument(oldDoc, newDoc)) {
          // Acknowledged with the data of the local version: the view keeps showing the local version (with its
          // pending writes, see [newDocHasPendingMutations]) until watch sends the document, like a held back change.
          newAwaitingSync[key] = newDoc.version;
        }
      } else if (oldDoc == null && newDoc != null) {
        changeSet.addChange(
          DocumentViewChange(DocumentViewChangeType.added, newDoc),
        );
        changeApplied = true;
      } else if (oldDoc != null && newDoc == null) {
        changeSet.addChange(
          DocumentViewChange(DocumentViewChangeType.removed, oldDoc),
        );
        changeApplied = true;
        if (lastDocInLimit != null || firstDocInLimit != null) {
          // A doc was removed from a full limit query. We'll need to requery from the local cache to see if we know
          // about some other doc that should be in the results.
          needsRefill = true;
        }
      }

      if (changeApplied) {
        newAwaitingSync.remove(key);
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
    if (query.hasLimit) {
      for (int i = newDocumentSet.length - query.getLimit(); i > 0; --i) {
        final Document oldDoc = query.hasLimitToFirst
            ? newDocumentSet.getLastDocument()!
            : newDocumentSet.getFirstDocument()!;
        newDocumentSet = newDocumentSet.remove(oldDoc.key);
        newMutatedKeys = newMutatedKeys.remove(oldDoc.key);
        newAwaitingSync.remove(oldDoc.key);
        changeSet.addChange(
          DocumentViewChange(DocumentViewChangeType.removed, oldDoc),
        );
      }
    }

    hardAssert(
      !needsRefill || previousChanges == null,
      'View was refilled using docs that themselves needed refilling.',
    );

    return ViewDocumentChanges._(
      newDocumentSet,
      changeSet,
      newMutatedKeys,
      needsRefill,
      newAwaitingSync,
    );
  }

  bool shouldWaitForSyncedDocument(Document oldDoc, Document newDoc) {
    // We suppress the initial change event for documents that were modified as part of a write acknowledgment (e.g.
    // when the value of a server transform is applied) as Watch will send us the same document again. By suppressing
    // the event, we only raise two user visible events (one with [hasPendingWrites] and the final state of the
    // document) instead of three (one with [hasPendingWrites], the modified document with [hasPendingWrites] and the
    // final state of the document).
    return oldDoc.hasLocalMutations &&
        newDoc.hasCommittedMutations &&
        !newDoc.hasLocalMutations;
  }

  /// Updates the view with the given [ViewDocumentChanges] and updates limbo docs and sync state from the given
  /// (optional) target change. Returns a new [ViewChange] with the given docs, changes, and sync state.
  ///
  /// [targetIsPendingReset] is true if the target is going to be reset because of an existence filter mismatch. While
  /// it is pending, no limbo documents are computed and the view is not reported as synced.
  ///
  /// [snapshotVersion] is the version of the remote event the changes come from, if any. Synced snapshots report the
  /// last one as their [ViewSnapshot.readTime].
  ViewChange applyChanges(
    ViewDocumentChanges docChanges, [
    TargetChange? targetChange,
    bool targetIsPendingReset = false,
    SnapshotVersion? snapshotVersion,
  ]) {
    hardAssert(
      !docChanges.needsRefill,
      'Cannot apply changes that need a refill',
    );
    if (snapshotVersion != null && snapshotVersion.compareTo(_readTime) > 0) {
      _readTime = snapshotVersion;
    }

    final DocumentSet oldDocumentSet = documentSet;
    documentSet = docChanges.documentSet;
    mutatedKeys = docChanges.mutatedKeys;
    _awaitingSync = docChanges.awaitingSync;
    _removedByWatch.removeWhere(
      (DocumentKey key) => documentSet.getDocument(key) == null,
    );
    // A rejected document that is back in the view (it has a local mutation) is a regular document again.
    _backendRejected.removeWhere(documentSet.contains);

    // Sort changes based on type and query comparator.
    final Comparator<Document> queryComparator = query.comparator;
    final List<DocumentViewChange> viewChanges =
        docChanges.changeSet.getChanges()
          ..sort((DocumentViewChange a, DocumentViewChange b) {
            final int typeComp = View._changeTypeOrder(
              a,
            ).compareTo(View._changeTypeOrder(b));
            if (typeComp != 0) {
              return typeComp;
            }
            return queryComparator(a.document, b.document);
          });

    _applyTargetChange(targetChange);
    if (snapshotVersion != null && _current) {
      // A snapshot of watch at or after the commit of a document the view waits for, without the document: watch is
      // past the write and will not send it.
      _awaitingSync.forEach((DocumentKey key, SnapshotVersion committed) {
        if (!_syncedDocuments.contains(key) &&
            snapshotVersion.compareTo(committed) >= 0) {
          _removedByWatch.add(key);
        }
      });
    }

    final List<LimboDocumentChange> limboDocumentChanges =
        targetIsPendingReset || !limboResolutionEnabled
        ? <LimboDocumentChange>[]
        : _updateLimboDocuments();

    // We are synced if no limbo documents are waiting to be resolved, the view is current with the backend and the
    // query is not pending a reset due to an existence filter mismatch.
    final bool synced =
        _limboDocuments.isEmpty && _current && !targetIsPendingReset;

    final ViewSnapshotSyncState newSyncState =
        synced //
        ? ViewSnapshotSyncState.synced
        : ViewSnapshotSyncState.local;
    final bool syncStatedChanged = newSyncState != _syncState;
    _syncState = newSyncState;
    ViewSnapshot? snapshot;
    if (viewChanges.isNotEmpty || syncStatedChanged) {
      final bool fromCache = newSyncState == ViewSnapshotSyncState.local;
      final bool hasCachedResults =
          targetChange != null && targetChange.resumeToken.isNotEmpty;

      snapshot = ViewSnapshot(
        query,
        docChanges.documentSet,
        oldDocumentSet,
        viewChanges,
        docChanges.mutatedKeys,
        isFromCache: fromCache,
        didSyncStateChange: syncStatedChanged,
        excludesMetadataChanges: false,
        hasCachedResults: hasCachedResults,
        readTime: fromCache ? SnapshotVersion.none : _readTime,
      );
    }
    return ViewChange(snapshot, limboDocumentChanges);
  }

  /// Reconciles the view with the documents and the remote keys of the target in persistence: used when a client
  /// becomes or stops being the primary client, since a secondary client does not track the documents that the backend
  /// considers part of the target.
  ViewChange synchronizeWithPersistedState(QueryResult queryResult) {
    _syncedDocuments = queryResult.remoteKeys;
    _limboDocuments = DocumentKey.emptyKeySet;
    final ViewDocumentChanges docChanges = computeDocChanges(
      queryResult.documents,
    );
    final bool previous = limboResolutionEnabled;
    limboResolutionEnabled = true;
    try {
      return applyChanges(docChanges);
    } finally {
      limboResolutionEnabled = previous;
    }
  }

  /// Returns a snapshot of the current state of the view, as if all its documents were added. Used when a view that
  /// exists already (the primary client listens to the query for another client) gets its first local listener.
  ViewSnapshot computeInitialSnapshot() {
    final bool fromCache = _syncState == ViewSnapshotSyncState.local;
    return ViewSnapshot.fromInitialDocuments(
      query,
      documentSet,
      mutatedKeys,
      isFromCache: fromCache,
      excludesMetadataChanges: false,
      hasCachedResults: false,
      readTime: fromCache ? SnapshotVersion.none : _readTime,
    );
  }

  /// Applies an [OnlineState] change to the view, potentially generating a [ViewChange] if the view's syncState changes
  /// as a result.
  ViewChange applyOnlineStateChange(OnlineState onlineState) {
    if (_current && onlineState == OnlineState.offline) {
      // If we're offline, set `current` to false and then call applyChanges() to refresh our syncState and generate a
      // [ViewChange] as appropriate. We are guaranteed to get a new [TargetChange] that sets `current` back to true
      // once the client is back online.
      _current = false;
      return applyChanges(
        ViewDocumentChanges._(
          documentSet,
          DocumentViewChangeSet(),
          mutatedKeys,
          /*needsRefill*/ false,
          _awaitingSync,
        ),
      );
    } else {
      // No effect, just return a no-op [ViewChange].
      return const ViewChange(null, <LimboDocumentChange>[]);
    }
  }

  void _applyTargetChange(TargetChange? targetChange) {
    if (targetChange != null) {
      for (DocumentKey documentKey in targetChange.addedDocuments) {
        _syncedDocuments = _syncedDocuments.insert(documentKey);
        _removedByWatch.remove(documentKey);
      }
      for (DocumentKey documentKey in targetChange.modifiedDocuments) {
        hardAssertLazy(
          _syncedDocuments.contains(documentKey),
          () => 'Modified document $documentKey not found in view.',
        );
      }
      for (DocumentKey documentKey in targetChange.removedDocuments) {
        _syncedDocuments = _syncedDocuments.remove(documentKey);
        if (documentSet.getDocument(documentKey) != null) {
          _removedByWatch.add(documentKey);
        }
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
    final Document? doc = documentSet.getDocument(key);
    if (doc == null) {
      return false;
    }

    // If there are local changes to the doc, they might explain why the server doesn't know that it's part of the
    // query. So don't put it in limbo.
    //
    // TODO(long1eu): Ideally, we would only consider changes that might actually affect this specific query.
    //
    // PORTING NOTE: not for a local version that is only kept until watch sends the document (see [_awaitingSync])
    // when watch took the document out of the target meanwhile (deleted on the backend, or a target reset without
    // it): its writes are done and explain nothing, and watch will not send it again, so without limbo resolution the
    // view would show the stale local version, with pending writes, for ever. Upstream has the same gap.
    if (doc.hasLocalMutations &&
        !(_awaitingSync.containsKey(key) && _removedByWatch.contains(key))) {
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
    this.awaitingSync,
  );

  /// The new set of docs that should be in the view.
  final DocumentSet documentSet;

  /// The diff of these docs with the previous set of docs.
  final DocumentViewChangeSet changeSet;

  /// Whether the set of documents passed in was not sufficient to calculate the new state of the view and there needs
  /// to be another pass based on the local cache.
  final bool needsRefill;

  final ImmutableSortedSet<DocumentKey> mutatedKeys;

  /// The documents whose change is held back until watch sends them, see [View.shouldWaitForSyncedDocument].
  final Map<DocumentKey, SnapshotVersion> awaitingSync;

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
