import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/internal.dart';

/// Implements the steps for backfilling indexes. Port of `IndexBackfiller` of
/// the Android SDK.
///
/// Only usable with a persistence that has field indexes (SQLite): with
/// memory persistence there is never a collection group to update.
class IndexBackfiller {
  /// Creates a backfiller that works on the index manager and the local
  /// documents view of the current user of [localStore].
  IndexBackfiller(Persistence persistence, LocalStore localStore)
    : this.forTesting(
        persistence,
        () => localStore.indexManagerForCurrentUser,
        () => localStore.localDocumentsForCurrentUser,
      );

  IndexBackfiller.forTesting(
    this._persistence,
    this._indexManagerOfCurrentUser,
    this._localDocumentsViewOfCurrentUser,
  );

  static const String _tag = 'IndexBackfiller';

  /// The maximum number of documents to process each time [backfill] is
  /// called.
  static const int defaultMaxDocumentsToProcess = 50;

  final Persistence _persistence;
  final IndexManager Function() _indexManagerOfCurrentUser;
  final LocalDocumentsView Function() _localDocumentsViewOfCurrentUser;

  /// The maximum number of documents to process each time [backfill] is
  /// called. Can be changed by tests.
  int maxDocumentsToProcess = defaultMaxDocumentsToProcess;

  /// Runs a single backfill operation and returns the number of documents
  /// processed.
  Future<int> backfill() {
    return _persistence.runPrimaryTransaction<int>(
      'Backfill Indexes',
      _writeIndexEntries,
    );
  }

  /// Writes index entries until the cap is reached. Returns the number of
  /// documents processed.
  Future<int> _writeIndexEntries() async {
    final IndexManager indexManager = _indexManagerOfCurrentUser();
    final Set<String> processedCollectionGroups = <String>{};
    int documentsRemaining = maxDocumentsToProcess;
    while (documentsRemaining > 0) {
      final String? collectionGroup = indexManager
          .getNextCollectionGroupToUpdate();
      if (collectionGroup == null ||
          processedCollectionGroups.contains(collectionGroup)) {
        break;
      }
      Log.d(_tag, 'Processing collection: $collectionGroup');
      documentsRemaining -= await _writeEntriesForCollectionGroup(
        collectionGroup,
        documentsRemaining,
      );
      processedCollectionGroups.add(collectionGroup);
    }
    return maxDocumentsToProcess - documentsRemaining;
  }

  /// Writes entries for the provided collection group. Returns the number of
  /// documents processed.
  Future<int> _writeEntriesForCollectionGroup(
    String collectionGroup,
    int documentsRemainingUnderCap,
  ) async {
    final IndexManager indexManager = _indexManagerOfCurrentUser();
    final LocalDocumentsView localDocumentsView =
        _localDocumentsViewOfCurrentUser();

    // Use the earliest offset of all field indexes to query the local cache.
    final IndexOffset existingOffset = indexManager.getMinOffset(
      collectionGroup,
    );

    final LocalDocumentsResult nextBatch = await localDocumentsView
        .getNextDocuments(
          collectionGroup,
          existingOffset,
          documentsRemainingUnderCap,
        );
    await indexManager.updateIndexEntries(nextBatch.documents);

    final IndexOffset newOffset = await _getNewOffset(
      existingOffset,
      nextBatch,
    );
    Log.d(_tag, 'Updating offset: $newOffset');
    await indexManager.updateCollectionGroup(collectionGroup, newOffset);

    // Documents that are only read again because the offset stops at the last snapshot version of watch (see
    // [_getNewOffset]) are not progress: a caller that backfills until nothing is processed must not loop on them.
    if (newOffset.compareTo(existingOffset) == 0) {
      return 0;
    }
    return nextBatch.documents.length;
  }

  /// Returns the next offset based on the provided documents.
  Future<IndexOffset> _getNewOffset(
    IndexOffset existingOffset,
    LocalDocumentsResult lookupResult,
  ) async {
    IndexOffset maxOffset = existingOffset;
    for (final DocumentKey key in lookupResult.documents.keys) {
      final IndexOffset newOffset = IndexOffset(
        lookupResult.readTimes[key] ?? SnapshotVersion.none,
        key,
        FieldIndex.initialLargestBatchId,
      );
      if (newOffset.compareTo(maxOffset) > 0) {
        maxOffset = newOffset;
      }
    }
    final int largestBatchId = max(
      lookupResult.batchId,
      existingOffset.largestBatchId,
    );
    // PORTING NOTE: an acknowledged write stores its document with the commit version as read time, which can be at
    // or ahead of the last snapshot version of watch. A document that watch delivers later, in a snapshot at or before
    // that commit version, would then be behind the offset and never indexed (the JS and Android SDKs have this gap).
    // So while such an acknowledged document (watch has not sent it yet) is read, the offset stops at the last
    // snapshot version of watch, which every later document of watch is at or after. The documents above it are read
    // again by the next backfill; queries find them meanwhile as documents changed after the offset.
    final SnapshotVersion lastRemoteSnapshotVersion =
        _persistence.queryCache.lastRemoteSnapshotVersion;
    if (maxOffset.readTime.compareTo(lastRemoteSnapshotVersion) >= 0 &&
        await _readsAcknowledgedAtOrAfter(
          lookupResult,
          lastRemoteSnapshotVersion,
        )) {
      return IndexOffset(
        lastRemoteSnapshotVersion,
        DocumentKey.empty(),
        largestBatchId,
      );
    }
    return IndexOffset(
      maxOffset.readTime,
      maxOffset.documentKey,
      largestBatchId,
    );
  }

  /// Whether [lookupResult] has a document, with a read time at or after [readTime], whose cached version comes from
  /// an acknowledged write (a set, an update or a delete) that watch has not sent yet.
  Future<bool> _readsAcknowledgedAtOrAfter(
    LocalDocumentsResult lookupResult,
    SnapshotVersion readTime,
  ) async {
    final List<DocumentKey> keys = <DocumentKey>[
      for (final MapEntry<DocumentKey, SnapshotVersion> entry
          in lookupResult.readTimes.entries)
        if (entry.value.compareTo(readTime) >= 0) entry.key,
    ];
    if (keys.isEmpty) {
      return false;
    }
    final Map<DocumentKey, MaybeDocument?> documents = await _persistence
        .remoteDocumentCache
        .getAll(keys);
    // Also a deleted or unknown document, from an acknowledged delete or update: it moves the offset all the same.
    // An entry of the remote document cache has no local mutations, so its pending writes are committed ones.
    return documents.values.any(
      (MaybeDocument? document) => document?.hasPendingWrites ?? false,
    );
  }
}

/// Schedules the index backfill: a first run shortly after the client
/// started, then one every minute. Port of `IndexBackfiller.Scheduler`.
class IndexBackfillerScheduler {
  /// [run] executes a backfill; the client passes a function that puts it on
  /// its serial queue, so that a backfill never interleaves with the other
  /// operations of the local store.
  IndexBackfillerScheduler(
    this._backfiller,
    this._scheduler, {
    Future<int> Function(Future<int> Function() backfill)? run,
  }) : _run = run ?? ((Future<int> Function() backfill) => backfill());

  static const String _tag = 'IndexBackfiller';

  /// How long we wait to try running index backfill after SDK initialization.
  static const Duration initialBackfillDelay = Duration(seconds: 15);

  /// Minimum amount of time between backfill checks, after the first one.
  static const Duration regularBackfillDelay = Duration(minutes: 1);

  final IndexBackfiller _backfiller;
  final TaskScheduler _scheduler;
  final Future<int> Function(Future<int> Function() backfill) _run;

  bool _stopped = false;
  TimerTask? _backfillTask;

  /// Incremented by every [start]: a run of an earlier start that finishes afterwards does not schedule another one.
  int _generation = 0;

  /// Whether the scheduler was started and not stopped since.
  bool get started => _backfillTask != null && !_stopped;

  /// Starts the scheduling, also after [stop] (a client that becomes the primary client of its cache again). Does
  /// nothing when it is running.
  void start() {
    if (started) {
      return;
    }
    _stopped = false;
    _generation++;
    _scheduleBackfill(initialBackfillDelay);
  }

  void stop() {
    // A run that is already in flight must not reschedule itself afterwards.
    _stopped = true;
    _backfillTask?.cancel();
    _backfillTask = null;
  }

  void _scheduleBackfill(Duration delay) {
    final int generation = _generation;
    _backfillTask = _scheduler.add(TaskId.indexBackfill, delay, () async {
      try {
        final int documentsProcessed = await _run(_backfiller.backfill);
        Log.d(_tag, 'Documents written: $documentsProcessed');
      } catch (e) {
        // A failed run (for example a closed database) must not end the
        // scheduling for the whole process. A persistence that is not
        // available right now is expected to work again (JS logs it at debug
        // level).
        if (isRecoverablePersistenceError(e)) {
          Log.d(_tag, 'Ignoring a retryable error during index backfill: $e');
        } else {
          Log.w(_tag, 'Index backfill failed: $e');
        }
      }
      if (!_stopped && generation == _generation) {
        _scheduleBackfill(regularBackfillDelay);
      }
    });
  }
}
