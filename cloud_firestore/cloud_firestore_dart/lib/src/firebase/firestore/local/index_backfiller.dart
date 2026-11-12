import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
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
            () => localStore.localDocumentsForCurrentUser);

  IndexBackfiller.forTesting(this._persistence, this._indexManagerOfCurrentUser,
      this._localDocumentsViewOfCurrentUser);

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
    return _persistence.runTransactionAndReturn<int>(
        'Backfill Indexes', _writeIndexEntries);
  }

  /// Writes index entries until the cap is reached. Returns the number of
  /// documents processed.
  Future<int> _writeIndexEntries() async {
    final IndexManager indexManager = _indexManagerOfCurrentUser();
    final Set<String> processedCollectionGroups = <String>{};
    int documentsRemaining = maxDocumentsToProcess;
    while (documentsRemaining > 0) {
      final String? collectionGroup =
          indexManager.getNextCollectionGroupToUpdate();
      if (collectionGroup == null ||
          processedCollectionGroups.contains(collectionGroup)) {
        break;
      }
      Log.d(_tag, 'Processing collection: $collectionGroup');
      documentsRemaining -= await _writeEntriesForCollectionGroup(
          collectionGroup, documentsRemaining);
      processedCollectionGroups.add(collectionGroup);
    }
    return maxDocumentsToProcess - documentsRemaining;
  }

  /// Writes entries for the provided collection group. Returns the number of
  /// documents processed.
  Future<int> _writeEntriesForCollectionGroup(
      String collectionGroup, int documentsRemainingUnderCap) async {
    final IndexManager indexManager = _indexManagerOfCurrentUser();
    final LocalDocumentsView localDocumentsView =
        _localDocumentsViewOfCurrentUser();

    // Use the earliest offset of all field indexes to query the local cache.
    final IndexOffset existingOffset =
        indexManager.getMinOffset(collectionGroup);

    final LocalDocumentsResult nextBatch =
        await localDocumentsView.getNextDocuments(
            collectionGroup, existingOffset, documentsRemainingUnderCap);
    await indexManager.updateIndexEntries(nextBatch.documents);

    final IndexOffset newOffset = _getNewOffset(existingOffset, nextBatch);
    Log.d(_tag, 'Updating offset: $newOffset');
    await indexManager.updateCollectionGroup(collectionGroup, newOffset);

    return nextBatch.documents.length;
  }

  /// Returns the next offset based on the provided documents.
  IndexOffset _getNewOffset(
      IndexOffset existingOffset, LocalDocumentsResult lookupResult) {
    IndexOffset maxOffset = existingOffset;
    for (final DocumentKey key in lookupResult.documents.keys) {
      final IndexOffset newOffset = IndexOffset(
          lookupResult.readTimes[key] ?? SnapshotVersion.none,
          key,
          FieldIndex.initialLargestBatchId);
      if (newOffset.compareTo(maxOffset) > 0) {
        maxOffset = newOffset;
      }
    }
    return IndexOffset(maxOffset.readTime, maxOffset.documentKey,
        max(lookupResult.batchId, existingOffset.largestBatchId));
  }
}

/// Schedules the index backfill: a first run shortly after the client
/// started, then one every minute. Port of `IndexBackfiller.Scheduler`.
class IndexBackfillerScheduler {
  /// [run] executes a backfill; the client passes a function that puts it on
  /// its serial queue, so that a backfill never interleaves with the other
  /// operations of the local store.
  IndexBackfillerScheduler(this._backfiller, this._scheduler,
      {Future<int> Function(Future<int> Function() backfill)? run})
      : _run = run ?? ((Future<int> Function() backfill) => backfill());

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

  void start() {
    _scheduleBackfill(initialBackfillDelay);
  }

  void stop() {
    // A run that is already in flight must not reschedule itself afterwards.
    _stopped = true;
    _backfillTask?.cancel();
  }

  void _scheduleBackfill(Duration delay) {
    _backfillTask = _scheduler.add(
      TaskId.indexBackfill,
      delay,
      () async {
        try {
          final int documentsProcessed = await _run(_backfiller.backfill);
          Log.d(_tag, 'Documents written: $documentsProcessed');
        } catch (e) {
          // A failed run (for example a closed database) must not end the
          // scheduling for the whole process.
          Log.w(_tag, 'Index backfill failed: $e');
        }
        if (!_stopped) {
          _scheduleBackfill(regularBackfillDelay);
        }
      },
    );
  }
}
